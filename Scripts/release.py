#!/usr/bin/env python3
"""Prepare and publish a Ting patch release with the shared bobuk.io release kit."""

import fcntl
import json
import os
from pathlib import Path
import re
import subprocess
import sys
from tempfile import NamedTemporaryFile
import time
from xml.etree import ElementTree

ROOT = Path(__file__).resolve().parents[1]
SPARKLE = "{http://www.andymatuschak.org/xml-namespaces/sparkle}"
UPDATE_TEXT = {
    "en": "Open Ting and choose Check for Updates… to install this release.",
    "ru": "Откройте Ting и выберите Check for Updates…, чтобы установить эту версию.",
    "uk": "Відкрийте Ting і виберіть Check for Updates…, щоб установити цю версію.",
}
FEED_TEST = """
test('Ting announces the version in its update feed in every locale', async () => {
  const feed = await readFile(new URL('./apps/ting/appcast.xml', dist), 'utf8');
  const version = feed.match(/sparkle:shortVersionString>([^<]+)</)?.[1];
  assert.ok(version);
  for (const locale of locales) {
    for (const route of ['apps/ting', 'apps/ting/support']) {
      const page = await html(pathFor(locale, route));
      assert.ok(page.includes(`>Ting ${version}<`) || page.includes(`>Ting ${version}:`));
    }
  }
});
"""


def output(*args: str, cwd: Path = ROOT) -> str:
    return subprocess.check_output(args, cwd=cwd, text=True).rstrip("\n")


def run(*args: str, cwd: Path = ROOT) -> None:
    subprocess.run(args, cwd=cwd, check=True)


def check_main(repo: Path) -> None:
    if output("git", "symbolic-ref", "--short", "HEAD", cwd=repo) != "main":
        raise ValueError(f"Check out main in {repo}.")
    run("git", "fetch", "--quiet", "origin", cwd=repo)
    run("git", "merge-base", "--is-ancestor", "origin/main", "HEAD", cwd=repo)


def configure_signing() -> None:
    if not os.environ.get("APP_IDENTITY"):
        identities = re.findall(
            r'^\s*\d+\)\s+[0-9A-Fa-f]+\s+"(Developer ID Application: [^"]+)"\s*$',
            output("security", "find-identity", "-v", "-p", "codesigning"), re.MULTILINE,
        )
        if len(identities) != 1:
            raise ValueError("Set APP_IDENTITY to the full name of your Developer ID Application certificate.")
        os.environ["APP_IDENTITY"] = identities[0]
    os.environ.setdefault("NOTARY_PROFILE", "ting")


def published_with_live_feed(version: str, build: str) -> bool:
    state = output("gh", "api", "--paginate", "repos/bobuk-io/ting/releases?per_page=100",
                   "--jq", f'.[] | select(.tag_name == "v{version}") | .draft')
    match state:
        case "":
            return False
        case "true":
            raise ValueError(f"A draft v{version} exists on GitHub. Resolve it before continuing.")
        case "false":
            site = os.environ.get("RELEASE_SITE_URL", "https://bobuk.io").rstrip("/")
            url = os.environ.get("RELEASE_FEED_URL", f"{site}/apps/ting/appcast.xml")
            feed = ElementTree.fromstring(output("curl", "-fsSL", "--max-time", "30",
                                                 f"{url}?v={time.time_ns()}"))
            builds = feed.findall(f"./channel/item/{SPARKLE}version")
            if not builds or any(not (node.text or "").isdigit() for node in builds):
                raise ValueError("The live Sparkle feed has no valid build number.")
            return any(node.text == build for node in builds)
        case _:
            raise ValueError(f"Unexpected GitHub release state for v{version}: {state!r}")


def add_announcement(source: str, version: str) -> str:
    # Keep the site's existing product and support copy, including hand-written
    # announcements for this version. Insert into the existing locale arrays.
    sections = re.split(r"(?m)^(  (?:en|ru|uk): \{\n)", source)
    if {header.strip()[:2] for header in sections[1::2]} != set(UPDATE_TEXT):
        raise ValueError("Could not locate Ting's three locales on the landing site.")
    for i in range(1, len(sections), 2):
        locale = sections[i].strip()[:2]
        title = f"Ting {version}"
        text = json.dumps(UPDATE_TEXT[locale], ensure_ascii=False)
        for section, field in (("features", f"text: {text}"), ("support", f"paragraphs: [{text}]")):
            start = f"    {section}: [\n"
            before, marker, after = sections[i + 1].partition(start)
            if not marker or "\n    ]," not in after:
                raise ValueError(f"Could not locate {locale}/{section} on the landing site.")
            entries = after.partition("\n    ],")[0]
            if not re.search(r"""title: ['"]""" + re.escape(title) + r"""[:'"]""", entries):
                sections[i + 1] = before + marker + f"      {{ title: '{title}', {field} }},\n" + after
    return "".join(sections)


def write_atomic(path: Path, contents: str) -> None:
    with NamedTemporaryFile(dir=path.parent, mode="w", encoding="utf-8", delete=False) as tmp:
        temporary = Path(tmp.name)
        try:
            tmp.write(contents)
            tmp.flush()
            temporary.chmod(path.stat().st_mode if path.exists() else 0o644)
            temporary.replace(path)
        finally:
            temporary.unlink(missing_ok=True)


def prepare(current: str, version: str, landing: Path) -> None:
    notes = Path(f"docs/releases/v{version}.md")
    page = Path("src/data/apps/ting.ts")
    test = Path("scripts/site.test.mjs")
    for repo, allowed in ((ROOT, {str(notes), "Scripts/release.py"}), (landing, {str(page), str(test)})):
        status = output("git", "status", "--porcelain=v1", "-z", "-uall", cwd=repo)
        unexpected = {entry[3:] for entry in status.split("\0") if entry} - allowed
        if unexpected:
            raise ValueError(f"Uncommitted changes in {repo}: {', '.join(sorted(unexpected))}")

    changes: dict[Path, str] = {}
    for path in (page, test):
        original = output("git", "show", f"HEAD:{path}", cwd=landing) + "\n"
        updated = original
        if path == page:
            updated = add_announcement(original, version)
        elif FEED_TEST.strip() not in original:
            updated += FEED_TEST
        actual = (landing / path).read_text(encoding="utf-8")
        if actual not in (original, updated):
            raise ValueError(f"Uncommitted edits in {landing / path}.")
        if updated != original:
            changes[path] = updated

    notes_file = ROOT / notes
    if not notes_file.exists():
        subjects = output("git", "log", "--no-merges", "--format=%s", f"v{current}..HEAD")
        items = [f"- {line}" for line in subjects.splitlines() if line != "Automate Ting patch releases"]
        body = "\n".join(items) or UPDATE_TEXT["en"]
        write_atomic(notes_file, f"# Ting {version}\n\n{body}\n")
    elif not notes_file.read_text(encoding="utf-8").strip():
        raise ValueError(f"Release notes are empty: {notes_file}")
    for path, contents in changes.items():
        write_atomic(landing / path, contents)
    if changes:
        run("git", "commit", "--only", "-m", f"docs(ting): announce {version}",
            "--", *map(str, changes), cwd=landing)


def finish_pending_deploy(version: str, landing: Path) -> bool:
    # The feed can be live before the kit has committed and pushed the site.
    release_files = {"public/apps/ting/appcast.xml", "src/data/public-repos.json"}
    status = output("git", "status", "--porcelain=v1", "-z", "-uall", cwd=landing)
    changed = {entry[3:] for entry in status.split("\0") if entry}
    if changed & release_files:
        if changed - release_files:
            raise ValueError("Commit unrelated landing changes before finishing the deployment.")
        run("Scripts/release/landing.sh")
    elif output("git", "log", "-1", "--format=%s", "origin/main..HEAD", cwd=landing) == (
        f"Ting {version}: update feed"
    ):
        run("git", "push", "origin", "main", cwd=landing)
    else:
        return False
    return True


def main() -> None:
    if len(sys.argv) != 1:
        sys.exit("Usage: release.py")
    os.environ.setdefault("GIT_TERMINAL_PROMPT", "0")
    os.environ.setdefault("GH_PROMPT_DISABLED", "1")
    with Path(__file__).open("rb") as lock:
        try:
            fcntl.flock(lock, fcntl.LOCK_EX | fcntl.LOCK_NB)
        except BlockingIOError:
            raise ValueError("A Ting release is already running from this checkout.") from None
        configure_signing()
        run("Scripts/release/doctor.sh")
        settings = dict(re.findall(r"^(MARKETING_VERSION|BUILD_NUMBER)=(\S+)$",
                                   (ROOT / "version.env").read_text(), re.MULTILINE))
        current = settings["MARKETING_VERSION"]
        base, patch = current.rsplit(".", 1)
        following = f"{base}.{int(patch) + 1}"
        landing = (ROOT / os.environ.get("LANDING", "../landing")).resolve()
        check_main(ROOT)
        check_main(landing)
        live = published_with_live_feed(current, settings["BUILD_NUMBER"])
        if live and finish_pending_deploy(current, landing):
            return
        if live:
            prepare(current, following, landing)
        # The kit requires a clean app tree apart from its version and notes.
        # Include this entry point itself on its first run from a fresh checkout.
        entry = "Scripts/release.py"
        if output("git", "status", "--porcelain=v1", "--", entry):
            run("git", "add", "--", entry)
            run("git", "commit", "--only", "-m", "Automate Ting patch releases", "--", entry)
        run("Scripts/release_next.sh")


if __name__ == "__main__":
    try:
        main()
    except subprocess.CalledProcessError as exc:
        print(f"release: {exc}", file=sys.stderr)
        sys.exit(exc.returncode if exc.returncode > 0 else 128 - exc.returncode)
    except (ValueError, OSError, EOFError, ElementTree.ParseError) as exc:
        sys.exit(f"release: {exc}")
    except KeyboardInterrupt:
        sys.exit(130)
