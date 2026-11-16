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

- Ting registers one global hotkey with the standard macOS hotkey API. It never
  requests Input Monitoring permission and does not observe keystrokes outside its
  own leader menu. It asks for Accessibility and Automation (Apple Events to
  Finder or a browser) only when an approved micro-app needs them, see below.
- Bindings and settings are stored in `~/.config/ting/config.json`. Anyone who can
  write that file can make Ting open any app or URL when you press a binding, or
  bind a key to a micro-app id. `config.json` holds no code.
- Ting opens apps by bundle identifier and URLs with the default handler chosen
  by macOS. App and URL bindings work as before: they run no shell commands and
  pass no arguments to apps. A URL scheme handler (for example `raycast://`) may perform its own actions.
- **Ting runs shell commands, Python code, HTTP requests and AI calls**, but only
  from micro-app files (described in `docs/micro-apps/FORMAT.md`) in the
  micro-apps folder `~/.config/ting/micro/`, and only after you approved the
  exact file content in the approval panel. The steps run as your user, with
  your full rights. Ting puts no limit on what they do: there is no sandbox, and
  they can read and change your files, send data to any server and start other
  programs. Only the run time is limited (60 seconds, or up to 300 when the file
  asks). Approve only files you understand.
- A micro-app can read every exported variable of your login shell (such as
  `OPENAI_API_KEY`) and, by service name, generic passwords of your login
  keychain (`${keychain.SERVICE}`), and send them to a server. macOS asks you
  before Ting reads a keychain item the first time. Read the URLs, headers and
  `ai` steps of a file before you approve it. Keep API keys out of micro-app
  files: use the environment or the keychain.
- A micro-app reads the context of its start only when its file lists it in
  `context:`, and the approval panel names it: the active app, the files selected
  in Finder (Automation for Finder), the URL and title of the browser tab
  (Automation for the browser), the selected text and the front window
  (Accessibility). The steps can send these values to a server like any other
  input. To read the selected text where Accessibility gives none, Ting presses
  `⌘C` in that app and puts the clipboard back.
- A micro-app with `keys` or `paste` steps, or `output.to: [app]`, sends key
  presses and text to the app that was in front at its start; the approval panel
  says so. With Accessibility granted to Ting, such a file can do in that app
  what you can do with the keyboard, for example type a command into a terminal.
  Ting sends nothing when that app is no longer in front or when a password field
  holds the keyboard. Accessibility stays granted to Ting for every approved
  micro-app: approve key-sending files as carefully as code.
- A micro-app can call or inherit library files from `micro/libs/`. The approval
  covers the micro-app with every library it uses: the approval panel shows
  their text, and a change of a library asks again for every micro-app that uses
  it.
- Ting stores the SHA-256 of each approved file by micro-app id in
  `~/Library/Application Support/Ting/micro-approvals.json`; any change of the
  file asks again, before any parameter is asked. `config.json` only names a
  micro-app id. Parameters and context values reach shell and Python code only as
  `TING_*` environment variables and the clipboard only as stdin, never as text
  pasted into the code. `${…}` variables are replaced only in the other keys of a step
  (URLs, headers, bodies, prompts, texts).
- Anyone who can write the micro-apps folder can offer a command; the approval
  stands between that file and a run. Anyone who can also write the approvals
  file can run commands as you. **Keep the micro-apps folder, `config.json` and
  `~/Library/Application Support/Ting/` writable only by your user account.**
- A micro-app file may be written by a coding agent such as Claude Code, Codex
  or pi. The agent runs with your rights, so it can write the micro-apps folder
  like any other program of yours; it is told not to change `config.json`, and
  its file still needs your approval in the approval panel before the first run.
  Read the file before you approve it, as for a file you wrote yourself.
- The bundled console tool `ting-micro run FILE.yaml` is a separate, explicit
  authorization to execute that file; it bypasses the GUI approval store and
  never changes that store. It uses the terminal environment and current
  directory, does not read or write the clipboard, and sends the result to
  stdout. It reads no context (only values given with `--context`) and never
  sends keys or text to an app. `open` and `notify` require `--allow-effects`,
  but this is not a sandbox: code and HTTP/AI calls still have your full rights. Run only trusted
  files. `ting-micro check` is read-only, like `Ting --check`.
- The check command `Ting --check <file.yaml>` only reads the given files and
  prints their problems. It never runs a micro-app step, opens no window,
  does not read `config.json` and writes no file: no log, no approvals and no
  values. A file that passes the check is not approved by it.
- **Copy Agent Prompt** and `Ting --agent-prompt` only build a text from the
  paths of this Mac (Ting.app, the micro-apps folder) and the GitHub link of the
  running version. They put it on the clipboard or print it; they send nothing,
  start no agent and write no file. The text tells the agent not to change
  `config.json`; the person still approves the file and binds its key.
- The steps get the environment of your login shell, PATH included, so whoever
  can change your shell start-up files can change which programs a micro-app
  runs and which values it reads.
- The parameter values of the last started run of each micro-app are stored as
  plain text in `~/Library/Application Support/Ting/micro-values.json`, unless
  the file says `remember: false`. Esc in the parameter panel saves nothing.
- Ting has no accounts, analytics or project servers. Apart from what your
  approved micro-apps do, its only network access is Sparkle's update
  check against the public feed `https://bobuk.io/apps/ting/appcast.xml`
  (Ting 0.6.1 and older:
  `https://github.com/bobuk-io/ting/releases/latest/download/appcast.xml`) and
  the download of a newer release from GitHub. The feed only names the release;
  the archive is accepted only with the signature below. A copy that Homebrew
  installed does neither; it reaches the network only through the Homebrew
  update described below, which you start yourself.
- Sparkle accepts an update only if the archive's EdDSA signature matches the
  public key built into the app and the new app passes macOS code signature
  checks. Development builds contain no feed and never update.
- **Ting runs `brew` in one case only.** When the running Ting.app is the copy
  that a Homebrew Caskroom record of the cask `ting` points to, Sparkle is not
  started. Choosing **Update Ting via Homebrew…** runs
  `<prefix>/bin/brew upgrade --cask --greedy bobuk-io/tap/ting`, with the `brew`
  of the prefix that owns that record, as your user and without a terminal (a
  password prompt fails instead of waiting). It never upgrades other packages.
  A small helper script in Ting's per-user temporary folder runs the command,
  writes its output there and, after a successful update or when Ting quit
  while brew ran, starts the installed Ting again to show the result.
  The downloaded archive is checked by Homebrew against the SHA-256 of the cask
  in the official tap `bobuk-io/homebrew-tap`, and the app keeps its Developer
  ID signature and notarization; whoever can change your Homebrew installation
  or tap can change what this command installs. Ting reads no configuration for
  it and does not touch `~/.config/ting` or micro-app data.
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
