# Security policy

## Reporting a vulnerability

Please report security issues privately using GitHub's **Report a vulnerability**
feature:

<https://github.com/bobuk-io/ting/security/advisories/new>

If that feature is unavailable, email **bobuk@rubedo.cloud** with the subject
`Ting security report`.

Please do not disclose vulnerabilities in a public issue before we have had an
opportunity to investigate. Include the Ting and macOS versions, reproduction
steps, expected impact, and a minimal proof of concept where possible. Remove
private URLs, tokens or other personal data from any configuration you share.

This is a small community project. Reports are handled on a best-effort basis;
there is no guaranteed response or fix deadline. Supported fixes target the
latest published version.

## Security model

- Ting registers one global hotkey with the standard macOS hotkey API. It does
  not request Accessibility or Input Monitoring permission and does not observe
  keystrokes outside its own leader menu.
- Bindings and settings are stored in `~/.config/ting/config.json`. Anyone who can
  write that file can make Ting open any app or URL when you press a binding, or
  bind a key to a micro-app id. `config.json` holds no code.
- Ting opens apps by bundle identifier and URLs with the default handler chosen
  by macOS. App and URL bindings work as before: they run no shell commands and
  pass no arguments to apps. A URL scheme handler (for example `raycast://`) may perform its own actions.
- **Ting runs shell commands**, but only from micro-app files (described in
  `docs/micro-apps/FORMAT.md`) in the micro-apps folder `~/.config/ting/micro/`,
  and only after you approved the exact file content in the approval panel. The
  command runs with `/bin/sh -c` as your user, with your full rights. Ting puts
  no limit on what it does: there is no sandbox, and it can read and change your
  files, use the network and start other programs. Only the run time is limited
  (60 seconds). Approve only commands you understand.
- Ting stores the SHA-256 of each approved file by micro-app id in
  `~/Library/Application Support/Ting/micro-approvals.json`; any change of the
  file asks again, before any parameter is asked. `config.json` only names a
  micro-app id. Parameters reach the command only as `TING_*` environment
  variables and the clipboard only as stdin, never as text pasted into the
  command.
- Anyone who can write the micro-apps folder can offer a command; the approval
  stands between that file and a run. Anyone who can also write the approvals
  file can run commands as you. **Keep the micro-apps folder, `config.json` and
  `~/Library/Application Support/Ting/` writable only by your user account.**
- The command gets the PATH of your login shell, so whoever can change your
  shell start-up files can change which programs a micro-app runs.
- The parameter values of the last started run of each micro-app are stored as
  plain text in `~/Library/Application Support/Ting/micro-values.json`, unless
  the file says `remember: false`. Esc in the parameter panel saves nothing.
- Ting has no accounts, analytics or project servers. Apart from what your
  approved micro-app commands do, its only network access is Sparkle's update
  check against the public feed
  `https://github.com/bobuk-io/ting/releases/latest/download/appcast.xml` and the
  download of a newer release from GitHub.
- Sparkle accepts an update only if the archive's EdDSA signature matches the
  public key built into the app and the new app passes macOS code signature
  checks. Development builds contain no feed and never update.
- Official release apps are signed with Developer ID, notarized by Apple and
  include a stapled ticket. Notarization is not a guarantee that software is
  bug-free or safe for every use case.

## Release and contributor safety

Download official builds only from this repository's Releases. Keep the
Developer ID identity, `notarytool` credentials and the Sparkle private key
outside git and outside CI jobs for untrusted code. The Sparkle private key lives
in the maintainer's login Keychain; losing or leaking it affects every installed
copy.

`Scripts/release.sh` signs, notarizes and signs the appcast, then installs and
restarts `/Applications/Ting.app`. It is intended for a trusted maintainer
workstation, not for running against unreviewed pull requests. Release
artifacts must pass the local-path scan and the signature, bundle and
notarization checks before publication.
