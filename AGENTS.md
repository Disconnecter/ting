# Ting project rules

- Ting is a leader-key launcher for macOS: a global leader key opens a menu, then
  one key or a short sequence opens an app or a URL.
- The local checkout is `~/GitHub/bobuk.io/ting`. The GitHub repository is
  `bobuk-io/ting`. Do not change its visibility unless the user explicitly asks.
  Never publish credentials, signing keys or private configuration.
- Use `io.bobuk.ting` for the app and `io.bobuk` for new identifiers.
- When you merge a pull request from someone new, add them to `CONTRIBUTORS.md` and
  `Sources/TingCore/Contributors.swift` (shown in About Ting); a test keeps the two equal.
- Commit the changes you make for each task before reporting it complete. Use a
  clear subject that says what changed. Explain why in the body when the reason
  would be hard to infer from the subject alone.
- Shared UI and infrastructure come from BobukKit (`Vendor/BobukKit`, read-only); read
  `../BobukKit/README.md` before adding windows, panels, controls, hotkeys, file stores,
  processes or update code here, and follow `../AGENTS.md`. The release kit in
  `Scripts/release/` is a managed copy of `../BobukKit/ReleaseKit`; never edit it here.
- A leader is any non-modifier key, alone or with modifiers. A modifier key on its
  own must never become a leader.
- `Sources/TingCore` holds pure logic with tests (it re-exports BobukCore). Run
  the fewest tests that prove a change after every change
  (`swift test --filter <name>` for the code you changed); do not run a test again after
  it passed, and docs-only changes need no tests. The seemasta checks after a Run and the
  release scripts run the full `swift test`; tests must pass without warnings.
- Releases use the shared release kit (`Scripts/release/README.md`); app facts live in
  `release.env`.
- Every release must be signed with Developer ID, notarized and stapled, signed
  for Sparkle, published to GitHub Releases, **installed at `/Applications/Ting.app`
  and restarted**. The update feed of installed copies is
  `https://bobuk.io/apps/ting/appcast.xml`; the release is not done until the landing
  site with that file is deployed. Keep publishing `appcast.xml` to GitHub Releases
  too (`GITHUB_APPCAST=1`), for Ting 0.6.1 and older. Verify that the running process
  is from `/Applications`, not `build/` or `dist/`.
- `Scripts/release_next.sh` (no arguments) does the whole next patch release:
  version raise, tests in the background while the app builds and is notarized,
  install, commit `Release Ting <version>`, push, GitHub release, Homebrew cask,
  landing deploy and a check of the live page and feed, then the time of each stage.
  Prepare the notes file of the next version, commit the landing page changes (clean
  `../landing` on main) and set `APP_IDENTITY` and `NOTARY_PROFILE` (`ting`). Check
  readiness with `Scripts/release/doctor.sh`. After a failure, run the same command
  again: it goes on with the same version.
- Each release needs a higher `BUILD_NUMBER` in `version.env` and release notes in
  `docs/releases/v<version>.md`.
- The Sparkle EdDSA private key stays in the login Keychain under account
  `io.bobuk.ting`. Never export, print, commit or upload it.
- Release artifacts must also pass `Scripts/check_bundle.swift`.
- Never overwrite the user's `~/.config/ting/config.json` during development or
  testing. Use `TING_CONFIG=/tmp/...` for manual checks.
- Tests and manual checks of micro-apps use a temporary micro-apps folder through
  `TING_CONFIG` (`$TING_CONFIG.micro/`); never write to `~/.config/ting/micro/`,
  its error log or the approvals and values in `~/Library/Application Support/Ting/`.
- The leader menu takes keyboard focus and can swallow the user's typing: never send
  synthetic key presses while the user works.
- For lowkey automation, use the native `lowkey` step, not shell commands or
  synthetic input. See `docs/CONFIGURING.md#lowkey-sites` for bindings and
  `docs/micro-apps/FORMAT.md#lowkey-steps` for action syntax. Validate examples
  with `ting-micro check`; use demo pages, never personal sites, for action tests.
- After every release, update the Ting pages on the landing site
  (`~/GitHub/bobuk.io/landing`) when the release needs it. See `../AGENTS.md`.
