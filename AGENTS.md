# Ting project rules

- Ting is a leader-key launcher for macOS: a global leader key opens a menu, then
  one key or a short sequence opens an app or a URL.
- The local checkout is `~/GitHub/bobuk.io/ting`. The GitHub repository is
  `bobuk-io/ting`. Do not change its visibility unless the user explicitly asks.
  Never publish credentials, signing keys or private configuration.
- Use `io.bobuk.ting` for the app and `io.bobuk` for new identifiers.
- Commit the changes you make for each task before reporting it complete. Use a
  clear subject that says what changed. Explain why in the body when the reason
  would be hard to infer from the subject alone.
- Keep README, release notes, security policy and other documentation in English.
  Keep the repository focused on the shipping application, without discarded
  design experiments, prototypes or their history. Local design material belongs
  in the ignored `/design/` directory.
- Original code is 0BSD; preserve the MIT attribution for the adapted scripts and
  the Sparkle license in `THIRD_PARTY_NOTICES.md`.
- A leader is any non-modifier key, alone or with modifiers. A modifier key on its
  own must never become a leader.
- `Sources/TingCore` holds pure logic with tests. Keep AppKit out of it. Run
  the fewest tests that prove a change after every change
  (`swift test --filter <name>` for the code you changed); do not run a test again after
  it passed, and docs-only changes need no tests. The seemasta checks after a Run and the
  release scripts run the full `swift test`; tests must pass without warnings.
- Do not add GitHub Actions or other hosted CI: they are slow. Run tests and
  release checks locally.
- Releases use the shared bobuk.io release kit in `Scripts/release/` (see its
  `README.md`). Ting holds the canonical copy: change the kit here, run
  `Scripts/release/test_kit.sh`, then copy it to the other apps with
  `Scripts/release/sync_kit.sh ../splash-fihish ../HAScS ../lowkey`. App facts live in
  `release.env`; never edit a kit copy in another repository.
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
  again: it goes on with the same version. Test the kit only with the offline
  `Scripts/release/test_kit.sh`; never run `release_next.sh`, `release.sh` or
  `publish.sh` for a check, since they publish or install a real release.
- Each release needs a higher `BUILD_NUMBER` in `version.env` and release notes in
  `docs/releases/v<version>.md`. Never modify a ZIP after the appcast signed it.
- The Sparkle EdDSA private key stays in the login Keychain under account
  `io.bobuk.ting`. Never export, print, commit or upload it.
- Release artifacts must pass `Scripts/check_bundle.swift` and
  `Scripts/release/check_privacy.swift`; do not ship local home or build paths.
- Never overwrite the user's `~/.config/ting/config.json` during development or
  testing. Use `TING_CONFIG=/tmp/...` for manual checks.
- Tests and manual checks of micro-apps use a temporary micro-apps folder through
  `TING_CONFIG` (`$TING_CONFIG.micro/`); never write to `~/.config/ting/micro/`,
  its error log or the approvals and values in `~/Library/Application Support/Ting/`.
- Do not send synthetic key presses while the user is working: the leader menu
  takes keyboard focus and can swallow their typing.
- For lowkey automation, use the native `lowkey` step, not shell commands or
  synthetic input. See `docs/CONFIGURING.md#lowkey-sites` for bindings and
  `docs/micro-apps/FORMAT.md#lowkey-steps` for action syntax. Validate examples
  with `ting-micro check`; use demo pages, never personal sites, for action tests.
- After every release, update the Ting pages on the landing site
  (`~/GitHub/bobuk.io/landing`) when the release needs it. See `../AGENTS.md`.
