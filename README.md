# Ting

A leader-key launcher for macOS. Press your leader key, then one key or a short
sequence to open an app or a link, or to start a small
[micro-app](#micro-apps) — without a search field, the Dock or the mouse.

```text
Home  space      →  WezTerm
Home  t  r       →  raycast://extensions/raycast/ai/to-russian
Home  w  d  s    →  https://developer.apple.com/documentation/swiftui
```

*Ting* is Jamaican patois and London slang for "thing". The menu borrows a little
from grime and sound-system culture: amber keycaps on graphite, `esc pull up`,
`⌫ rewind`.

Requires **macOS 14 or later**. Official releases are universal builds for
**Apple Silicon and Intel**.

[Release notes for Ting 0.7.0](docs/releases/v0.7.0.md): a calculator in
launcha, and update checks at bobuk.io.

[In 0.6](docs/releases/v0.6.0.md), micro-apps learned to read the active app,
the Finder selection, the browser tab and the selected text, and to press keys
and paste their result into the app; [0.6.1](docs/releases/v0.6.1.md) shows how
to give Ting Accessibility.

[In 0.5.0](docs/releases/v0.5.0.md), micro-apps became small scripts of steps
(shell, Python, HTTP, AI) with shared libraries, and a coding agent can set up
your bindings too.

The small gear in the bottom-right corner of selecta and launcha opens Ting's
menu, including Settings and Check for Updates, even when the menu-bar icon is hidden. The launcher
stays open under the menu and takes keys again when the menu closes without a choice.

[Release notes for Ting 0.7.4](docs/releases/v0.7.4.md): a copy installed with
Homebrew updates through Homebrew from Ting's menu instead of Sparkle.

## Install

### Homebrew

```sh
brew install --cask bobuk-io/tap/ting
open /Applications/Ting.app
```

If Homebrew asks you to trust the cask, run
`brew trust --cask bobuk-io/tap/ting`, then repeat the install command.

The [official tap](https://github.com/bobuk-io/homebrew-tap) installs the same
signed, notarized universal app as the ZIP. A copy that Homebrew installed is
updated by Homebrew, see [updates](#updates) below. If Ting is already in
`/Applications`, keep using its built-in updates, or quit Ting and run
`brew install --cask --adopt bobuk-io/tap/ting` to adopt an identical copy.
Homebrew refuses to adopt a different version; do not use `--force` to overwrite it.

### Manual download

1. Download the universal ZIP from [Releases](https://github.com/bobuk-io/ting/releases/latest).
2. Unzip it and move `Ting.app` to `/Applications`.
3. Open Ting. It lives in the menu bar and has no Dock icon.
4. Press the key you want as your leader. There is no default leader.

Official releases are signed with Developer ID, notarized by Apple and include a
stapled notarization ticket. Each release includes a SHA-256 checksum.

### Updates

A downloaded copy updates itself with [Sparkle](https://sparkle-project.org)
from this repository's releases; you can turn automatic checks off in Settings.
To upgrade it, choose **Check for Updates…** in Ting's menu (the menu-bar icon
or the gear of selecta and launcha). You can also quit Ting and replace
`/Applications/Ting.app` with the new copy from the ZIP, then open it again.

A copy that Homebrew installed (a Caskroom record of the cask `ting` points to
the running Ting.app) never runs Sparkle: it does not check for updates on its
own and shows no Sparkle window. Its menu and the Updates section of Settings
offer **Update Ting via Homebrew…** instead. That runs exactly
`brew upgrade --cask --greedy bobuk-io/tap/ting` with the `brew` of the prefix
that installed Ting, and shows the command, the live output of brew and the real
result: updated, already up to date, or the error (for example no network, a
Homebrew lock or a password prompt that cannot be answered). If Ting stops while
brew replaces it, a copy of Ting made before brew started shows the progress
window until the end, even while no Ting.app is installed. After
an update Ting starts again from its installed place (the new Caskroom record)
and shows the result once more. The
`--greedy` flag is needed because the cask declares built-in updates. You can
also run the same command in a terminal yourself.

Updates keep your settings, bindings and micro-apps.

To uninstall a Homebrew copy, turn off launch at login, quit Ting, then run
`brew uninstall --cask bobuk-io/tap/ting`. This keeps your data. Add `--zap` only
to also delete settings, bindings, micro-apps, approvals, remembered values and
usage history.

## Use

- **Leader:** any key that is not a modifier, alone or with modifiers — for
  example `Home`, `F13` or `⌥⇧⌘F`. A modifier on its own (such as Right `⌥`)
  cannot be a leader.
- **Sequences:** letters, digits, `Space`, `Return` and F-keys. Groups can be
  nested as deep as you like. `Esc` closes the menu, `Delete` goes back one level.
- **Menu navigation:** `↑` and `↓` select a row (hold to repeat); `Return` or keypad
  `Enter` opens it. `→` enters the selected group; `←` goes back, or closes at the
  top level. An explicit `Return` binding takes priority over opening the selected row.
- **Actions:** open an app (an app that is already running comes to the front)
  or open a URL with its default handler — web links and app URL schemes such as
  `raycast://` or `hascs://`, or start a [micro-app](#micro-apps). Shell
  commands, HTTP requests and AI calls run only from approved micro-app files,
  never from config.json.
- **Any keyboard layout:** bindings are stored by the Latin letter of the key, so
  they keep working with Russian, Ukrainian or any other layout. The menu shows
  the current layout's letter as a small hint next to the Latin one.
- **Fast typing:** if you type the whole sequence quickly, the menu never appears.
  The delay is 0.25 s by default and can be changed in Settings.

The menu shows the leader as a tuning-fork symbol; its tooltip names your configured key.

The menu appears on the display that contains the pointer, above full-screen
apps and on every Space.

## launcha

The leader menu is called **selecta**. **launcha** is its search companion: type
part of an app or micro-app name and press `Return`.

- **Open it:** press the leader twice at the top level of selecta. The first
  press opens selecta at once, so sequences are never delayed; any key in
  between cancels the double tap. The interval is 0.3 s by default (0.1–1 s).
  You can also set a separate global hotkey (unset by default) or choose
  **Open launcha** in the menu-bar menu.
- **Search:** an empty field lists your apps, most-used first. Matching ignores
  case and accents, understands word starts and initials (`vsc` → Visual Studio
  Code) and text typed with the wrong layout (`ыфафкш` → Safari). The search uses
  a native Mac text field for paste, editing and input methods.
- **Keys:** `↑` `↓` choose, `Return` opens, `⌘Return` shows the item in Finder,
  `Esc` closes. launcha also closes when you click elsewhere or switch Spaces.
- **Apps:** from `/Applications`, `/System/Applications` and `~/Applications`.
  launcha opens the exact app bundle it found; a running app comes to the front.
  Ting scans these folders at startup and each time launcha opens. While the
  panel stays open, it checks every 15 seconds whether a refresh is due; these
  background scans run at most once per minute.
- **Micro-apps:** every loaded micro-app is listed, with or without a binding,
  except files with `hidden: true` (they still start by their binding). The name
  is the binding label, else the micro-app's `name`, else the id. `Return` starts
  the same flow as its binding: approval, parameters, result; `⌘Return` shows
  its file in Finder. A broken file is listed as not working with its first
  error (by its `name` when that key is valid, and left out when it has a valid
  `hidden: true`), and starting it shows the errors of that file.
- **Files:** only when no app or micro-app matches, launcha asks Spotlight for files in your
  home folder (not `~/Library`, hidden folders or app bundles) and opens a file
  with its usual app.
- **Calculator:** a query of digits and an operator, such as `2*(3+4)`,
  `1,5 × 4`, `200 + 15%`, `2^10` or `sqrt(2)`, shows its value first, above any
  app or file; `Return` (or `⌘Return`) copies it. Both `.` and `,` are decimal
  points; `+ - * / ^`, `× ÷`, parentheses, `mod`, percent, `pi`, `e` and the
  functions `sqrt`, `abs`, `round`, `floor`, `ceil`, `ln`, `log`, `exp`, `sin`,
  `cos`, `tan` (radians) work. Results keep up to 12 digits after the point.
  Turn it off with **Calculate in launcha** in Settings › General
  (`"calculator": false` under `launcha` in the config file).
- **Desktop, Documents and Downloads** are not searched until you allow it, in
  launcha or in Settings. macOS may then ask you to allow Ting to access each
  folder. Desktop apps are listed after that. Until then launcha says that these
  folders were skipped.
- **Ranking:** Ting counts successful opens through selecta and launcha over the
  last 7 days. Matches rank by that count, then most recent launch, match quality
  and name. Failed opens and Finder reveals do not count. Ting does not watch
  apps you open in other ways.

The usage history and the folder choice are stored apart from the config file,
in `~/Library/Application Support/Ting/` (`launcha-history.json`,
`launcha-consent.json`). With `TING_CONFIG` set, both sit next to that file
instead, with the config file name in front: `TING_CONFIG=/tmp/ting-test.json`
uses `/tmp/ting-test.json.launcha-history.json` and
`/tmp/ting-test.json.launcha-consent.json`.

## Micro-apps

A micro-app is a small tool: it can ask for a few parameters, read the
clipboard and what you were working on (the active app, the files selected in
Finder, the browser tab, the selected text), show or copy the result, paste it
into the app or press keys there. Its work is one shell command or a short
script of **steps**: shell or Python code, HTTP requests, questions to OpenAI,
Anthropic or a compatible server (Ollama, LM Studio, OpenRouter), text templates,
JSON fields, opening a URL, notifications, key presses and pasted text. The
output of each step is the input of the next one, as in a shell pipe. Each
micro-app is one YAML file in a strict, checked format, described in
[docs/micro-apps/FORMAT.md](docs/micro-apps/FORMAT.md), which holds the full
text of fifteen working [examples](docs/micro-apps/examples/): Format JSON,
Change case, Encode / decode, Count words, DNS lookup, Wikipedia summary, Search
the web, Translate, Translate to Ukrainian, Ask Claude, About the active app,
Checksum of Finder files, Copy page link, Sort selected lines and Search in a
new tab. Shared steps live once in
a **library**, `micro/libs/NAME.yaml`: a micro-app runs it as a step
(`- call: translate` with `params:`) or inherits it and changes single keys
(`inherit: translate`, then `steps: - id: translate` with new `params`), so
"Translate to Ukrainian" and "Translate to English" share one prompt. The files are meant to be written by you or by a
coding agent such as Claude Code, Codex or pi; Ting has no editor for them and
installs none by itself, so the folder starts empty. The format document also
ships inside the app, as `/Applications/Ting.app/Contents/Resources/FORMAT.md`,
so an agent can read the version that matches the installed Ting.

```yaml
format: ting.microapp/2
name: Change case
description: Change the case of the clipboard text.
params:
  - name: mode
    type: choice
    required: false
    default: upper
    choices: [upper, lower]
input: clipboard
steps:
  - python: |
      import os, sys
      text = sys.stdin.read()
      sys.stdout.write(text.upper() if os.environ["TING_MODE"] == "upper" else text.lower())
output:
  to: [clipboard]
```

```yaml
  - ai: ${input}
    provider: anthropic
    model: claude-haiku-5-5
    key: ${keychain.anthropic}
    system: Fix the grammar. Answer with the fixed text only.
```

Every step runs as you, with your full rights, in your home folder and with the
environment of your login shell, so Homebrew tools and variables such as
`OPENAI_API_KEY` are found. Shell and Python code reads its input on stdin and
each parameter as an environment variable (`mode` → `$TING_MODE`); Ting never
pastes a value into code. The other keys of a step can use variables:
`${input}`, `${params.mode}`, the output of an earlier step `${steps.page}`, an
environment variable `${OPENAI_API_KEY}` or a keychain item
`${keychain.anthropic}`, with filters such as `${input|trim|url}`. Keep keys out
of the files: export them in your shell start-up file or add them to the
keychain. While a micro-app runs, the panel shows which step runs and the output
of the last step while it comes, such as an AI answer word by word.

### Context and sending to the app

A micro-app lists in `context:` what Ting reads when it starts, and Ting reads
only that: `app` (name, bundle id, path), `finder` (the selected files and the
folder of the front Finder window), `browser` (URL and title of the front tab in
Safari, Chrome, Arc, Brave, Edge or Vivaldi), `selection` (the selected text) and
`window` (the title and document of the front window). Steps read them as
`${context.finder.selection}` or `$TING_CONTEXT_FINDER_SELECTION`. A `keys` step
presses keys in the app that was in front (`keys: [cmd+a, return]`), a `paste`
step pastes text there, and `output.to: [app]` pastes the result, for example in
place of the selected text. Ting puts the clipboard back after it pastes.

```yaml
context: [selection]
input: none
steps:
  - command: LC_ALL=en_US.UTF-8 sort
    stdin: ${context.selection.text}
output:
  to: [app]
```

Ting asks macOS for a permission only when a micro-app needs it: **Automation**
for Finder or the browser (macOS asks once per app), and **Accessibility** for
the selected text, the window, key presses and pasted text (turn on Ting in
System Settings › Privacy & Security › Accessibility). Without Accessibility, Ting
opens a window with the steps and its icon to drag into that list, and closes
it by itself once access is on; **Settings › Advanced** shows whether Ting has
it and opens the same window. The selected text comes
from Accessibility; when an app does not give it, Ting presses `⌘C` there and
puts the clipboard back.

Ting loads every `*.yaml` file of the `micro/` folder next to the config file
(`~/.config/ting/micro/`) and loads it again when a file is added, changed or removed. A missing folder simply
means no micro-apps. When two files have the same id, the first by file name
works and the second is reported as a duplicate. A file with a mistake is not
used: the menu-bar menu shows a warning, **Settings › Advanced** lists every
error with file and line, a short message appears when a change breaks a file,
and `micro-errors.log` next to the config file holds one `file:line: message`
line per problem (it is empty when all files are good). With `TING_CONFIG` set,
both get the config file name in front, like the launcha files:
`TING_CONFIG=/tmp/ting-test.json` uses the folder `/tmp/ting-test.json.micro/` and
the log `/tmp/ting-test.json.micro-errors.log`.

### Running a micro-app from Terminal

The app bundles a native Swift CLI that uses the same execution engine:

```sh
MICRO=/Applications/Ting.app/Contents/MacOS/ting-micro
"$MICRO" check script.yaml
printf '%s' 'Hello' | "$MICRO" run script.yaml --param mode=lower --verbose
"$MICRO" run script.yaml --input 'Hello' --timeout 120
```

From source: `swift run ting-micro run script.yaml`. Input comes from stdin or
`--input`, the result goes to stdout, and errors go to stderr. It never opens
Ting's panels, touches the clipboard or reads/writes config, approvals or
remembered values. `run` explicitly authorizes execution of the named file;
only run trusted scripts. It uses the terminal environment and current folder.
`open` and `notify` require `--allow-effects`; shell/Python and HTTP/AI still
have full rights. It reads no context: `--context app.name=Safari` gives a
value, the others are empty. `keys` and `paste` steps never send anything there;
they print a note on stderr. `Ctrl-C` stops the run and its child processes. See
[console usage](docs/micro-apps/FORMAT.md#checking-and-running).

### Checking a micro-app file

The check command checks micro-app files before they go into the folder, without
a running Ting:

```sh
/Applications/Ting.app/Contents/MacOS/Ting --check sort-lines.yaml [more files]
```

It opens no window and no menu-bar icon, does not read `config.json`, writes no
file and works while Ting is running. It prints one `file:line: message` line per
problem, with the same text as `micro-errors.log`, or `<file>: ok` for a good
file. The exit code is 0 when every file is good, 1 when a file has a problem and
2 for a wrong call (no file, an unreadable file or a name without `.yaml`), with
the message on standard error. Given several files, it reports a duplicate id
among them; a duplicate with a file already in the folder shows only in
`micro-errors.log`.

A coding agent writes a micro-app this way: it reads FORMAT.md, writes `<id>.yaml`
in a temporary folder, runs the check command and fixes the file until it is
good, then moves it into the micro-apps folder. It does not change `config.json`:
you approve the new file at its first start and bind a key to it yourself.

### Setting up Ting with a coding agent

A coding agent such as Claude Code, Codex or pi can change Ting for you: write
micro-apps and libraries, and add key bindings and settings to `config.json`.
Its guide is [docs/CONFIGURING.md](docs/CONFIGURING.md), shipped as
`Ting.app/Contents/Resources/CONFIGURING.md`; it points to FORMAT.md for
micro-apps. Ask in plain words, for example "write a new micro-app: Leader t a
should translate the clipboard into German".

**Copy Agent Prompt**, in the menu-bar menu next to **Open Config File** and in
**Settings › Advanced** next to **Open Folder in Finder**, puts a ready text on
the clipboard. Paste it into the agent and add your task after its last line,
"My task:". The text names the paths of this Mac: the guide and the format
document inside Ting.app (with the GitHub links of the running version as the
fallback), `ting-micro` and the micro-apps folder (the one of `TING_CONFIG` when
it is set). It tells the agent to write and check micro-apps in a temporary
folder, to move them into the folder only when `ting-micro check` reports no
problem, to change `config.json` only as you asked and check it with
`ting-micro check-config`, and never to write keys into files or touch the
approvals. You still approve each new micro-app at its first start.

`Ting --agent-prompt` prints the same text and exits, for scripts:

```sh
/Applications/Ting.app/Contents/MacOS/Ting --agent-prompt
```

It opens no window, does not read `config.json` and writes no file.

### Starting a micro-app

Bind a key to a micro-app in **Settings › Bindings**, or by its id in `config.json`:
`{"key": "j", "label": "JSON", "micro": "format-json"}`. An item has exactly one
of `items`, `app`, `url` and `micro`. selecta shows the label, else the
micro-app's `name`, else the id. A binding to an id that is not loaded keeps the
config valid; selecta shows it as not working, and its key shows the error
instead of starting anything. Every micro-app can also be started by name from
[launcha](#launcha), with or without a binding, unless its file says
`hidden: true`.

- **Approval:** before the first run, and again after any change of the file,
  the approval panel shows the name, the file, what it reads of the context,
  whether it sends keys or text to the app, and the full command. `⌘Return`
  approves and runs, `Esc` refuses; `Return` alone does nothing. Ting stores the
  SHA-256 of the approved file content by micro-app id in
  `~/Library/Application Support/Ting/micro-approvals.json` (with `TING_CONFIG`
  set: next to that file, e.g. `/tmp/ting-test.json.micro-approvals.json`), not
  in the micro-apps folder and not in `config.json`.
- **Parameters:** a micro-app with parameters shows the parameter panel next
  (after the approval, if one is needed): one field per parameter, in file order,
  with its `prompt` as label. Required fields are always visible; optional ones
  are behind `⌘O` and the options icon, filled with their default, and open at
  once when every parameter is optional or a remembered optional value differs
  from its default. `Tab` moves between the visible fields, `Return` runs from
  any field, `Esc` closes without running or saving anything. An empty required
  text field stops `Return` and is marked. A choice field lists its options under
  the field: the arrows move the mark, letters filter, the marked option is the
  value; letters that match no option stop `Return` until an option is chosen.
  A form taller than the panel scrolls, and the focused field stays in view. A micro-app with one choice parameter opens as a list: choose and press
  `Return`. A micro-app without parameters shows no parameter panel.
- **Remembered values:** when the run starts, Ting saves the shown values by
  micro-app id as plain text in
  `~/Library/Application Support/Ting/micro-values.json` (with `TING_CONFIG` set:
  next to that file, e.g. `/tmp/ting-test.json.micro-values.json`) and shows them
  at the next start, a required text fully selected. A value that is no longer
  one of the choices, or of a removed parameter, is dropped. `remember: false`
  gives a clean form every time and saves nothing. Do not type secrets into a
  remembered micro-app.
- **Running:** after `Return` the same panel shows that the command runs. `Esc` stops it silently and
  leaves the clipboard as it was. After 60 seconds Ting stops the command and
  shows "stopped after 60 s" with the output that came before.
- **Context:** a micro-app with `context:` reads it before the parameter panel,
  from the app that was in front when you pressed the key. When Automation is
  missing, the panel says what to allow; without Accessibility, Ting opens its
  Accessibility window. Nothing runs then.
- **Result:** `output.to: [panel]` shows stdout in the result panel;
  `[clipboard]` copies it and shows "Copied"; both do both, with a "Copied" note
  in the panel. `[app]` pastes it into the app that was in front and puts the
  clipboard back; `[clipboard, app]` pastes it and leaves it on the clipboard.
  When Ting cannot paste, the result stays on the clipboard and the panel says why. An empty result copies nothing and shows "No output". A failing command always opens
  the result panel with an error mark, the exit code, stderr and stdout, and
  copies nothing. Output longer than 1 MB is cut, with a note. In the result
  panel you can scroll and select text; `⌘C` copies the selection, `Return`
  copies everything and closes, `Esc` closes. `output.as` sets the style:
  `markdown` (the default: headings, lists, bold, italic, code and tables as
  aligned columns), `console` (monospaced, with ANSI colours), `text` or `code`
  (monospaced). An error is always shown as console text.
- Only one micro-app is open at a time: a new start closes the open panel and
  stops its command.

## Settings

Choose **Settings…** in the menu-bar menu, or open Ting again from Finder or
Spotlight.

- **General:** light or dark theme (dark by default), the leader key, the menu
  delay, what an unknown key does, launch at login, the menu-bar icon, the quiet
  "ting" when Ting opens an app, link or file (on by default, `playSound` in the
  config file), and update checks. Under the "ting" toggle, the **Sound** picker
  chooses one of the macOS system sounds in `/System/Library/Sounds` (`sound`,
  default `Tink`) and the **Volume** slider sets its volume from 0 to 1
  (`soundVolume`, default 0.5); choosing a sound or releasing the slider plays it
  once. Both are disabled while the toggle is off. “Show panel title” controls the `Ting · selecta`
  and `Ting · launcha` title rows (on by default); hiding them keeps the leader
  symbol, sequence and search input visible. With the title hidden, selecta uses
  the same compact gap below the amber top rule as launcha.
  The launcha section sets its hotkey, the leader double tap and its
  interval, and access to Desktop, Documents and Downloads.
- **Bindings:** one table of key sequences. Click the record button, type the
  keys and press **Done** (`Space` and `Return` are recorded as keys). Missing
  groups are created and empty groups are removed automatically. If a shorter
  sequence already opens something, Ting offers to turn it into a group.
  **+ › Micro-app** binds a key to one of the found micro-apps (name and id) and
  writes it as `"micro": "<id>"`; the picker follows the folder live. A binding to
  an id that is not loaded is marked and can be changed or deleted.
- **Advanced:** the config file location, reveal, open, reload, import and export,
  and the micro-apps folder: the list of found micro-apps (name, id, file, good
  or broken), the list of micro-app errors, whether Ting has Accessibility (with
  **Allow…**, which opens the Accessibility window), **Open Folder in Finder**,
  which creates the folder when it is missing, and **Copy Agent Prompt** (see
  [Setting up Ting with a coding agent](#setting-up-ting-with-a-coding-agent)).

## Configuration file

Settings and bindings live in `~/.config/ting/config.json`. Ting creates a
sample on first launch, reloads the file when it changes and keeps the last good
settings if the file has an error; the error appears in the menu-bar menu. Keep
the file in your dotfiles if you like.

```json
{
  "version": 1,
  "leader": "home",
  "showDelay": 0.25,
  "items": [
    { "key": "space", "label": "WezTerm", "app": "com.github.wez.wezterm" },
    { "key": "w", "label": "Web", "items": [
      { "key": "g", "label": "GitHub", "url": "https://github.com" }
    ]}
  ]
}
```

- Each item has a `key`, an optional `label` and exactly one of `items` (a
  group), `app` (a bundle identifier), `url` or `micro` (a micro-app id).
- `key` is a lower-case Latin letter or digit, `space`, `return` or `f1`…`f20`.
- `leader` is a key name such as `home`, `f13` or `space`, optionally with
  modifiers: `option+shift+cmd+f`, `ctrl+space`.
- Other settings: `unknownKey` (`shake` or `close`), `appearance` (`dark` or
  `light`), `launchAtLogin`, `showMenuBarIcon`, `showPanelHeader`, `playSound`,
  `sound` (a system sound name without extension, default `Tink`; an unknown
  name plays `Tink`), `soundVolume` (0–1, default 0.5).
- `launcha`: `{"hotkey": null, "doubleTap": true,
  "doubleTapWindow": 0.3}`. `hotkey` uses the leader format and must differ
  from the leader.

## Privacy and permissions

Ting registers its leader (and the optional launcha hotkey) with the standard
macOS hotkey API. It does not ask for Accessibility or Input Monitoring
permission and does not read keystrokes outside its own panels. launcha reads
the app folders at startup and each time it opens. While it stays open,
background scans run at most once per minute; this limit does not apply to
startup or panel-opening scans. It asks Spotlight for file names only for what
you type, and only when no app matches. It keeps its launch counts on your Mac.

Ting has no accounts, analytics or servers. It opens the apps and URLs you
configure and runs the commands of the micro-app files you approved; what such a
command does, including network access, is up to the command. Sparkle checks
the update feed at `https://bobuk.io/apps/ting/appcast.xml` (Ting 0.6.1 and older:
this repository's release feed) and downloads updates from GitHub. In a copy
that Homebrew installed, Sparkle is off and Ting runs `brew` only when you choose
**Update Ting via Homebrew…**. See [SECURITY.md](SECURITY.md) for the security
model and private vulnerability reporting.

## Develop

Use Xcode or Command Line Tools with **Swift 6.2 or later** on macOS:

```sh
swift build
swift test
./Scripts/run.sh
```

`run.sh` builds a development copy in `build/` and starts it. Development builds
are ad-hoc signed, not notarized, and never check for updates. Set
`TING_CONFIG=/tmp/ting-test.json` to keep your real configuration untouched; the
micro-apps folder, the error log and the micro-app state then live next to it
(`/tmp/ting-test.json.micro/` and so on).

The SwiftUI interface and AppKit panel, hotkey and menu-bar wiring live in
`Sources/Ting`. The config format, key names, the binding tree and the leader
state machine live in `Sources/TingCore` and are covered by the tests in
`Tests/TingCoreTests`.

The app icon master is `Assets/AppIcon.png` (1024×1024, transparent). Packaging
runs `Scripts/build_icon.sh`, which generates every standard and Retina size with
`sips` and `iconutil`.

## Release

Releases are built on a trusted maintainer workstation with a Developer ID
Application identity, a saved `notarytool` Keychain profile and the Sparkle
EdDSA key in the login Keychain (account `io.bobuk.ting`). Unpack the verified
Sparkle 2.10.1 release tools to `.build/sparkle-tools` or set `SPARKLE_BIN` to
their `bin` directory.

### Next patch release in one command

`Scripts/release_next.sh` does the whole next patch release (for example
0.7.4 → 0.7.5) with no arguments. Prepare:

- the release notes `docs/releases/v<next version>.md` (the script never writes them);
- the Ting pages of the landing site, when the release needs it, committed in
  `../landing` (or `LANDING`), which must be on `main` with a clean tree;
- `main` of this checkout not behind `origin/main`, and no other changed files;
- `APP_IDENTITY` and `NOTARY_PROFILE`, as for `release.sh`.

Then run:

```sh
APP_IDENTITY='Developer ID Application: Your Name (TEAMID)' \
NOTARY_PROFILE=ting \
./Scripts/release_next.sh
```

It checks everything before it changes a file, raises the last number of
`MARKETING_VERSION` and `BUILD_NUMBER` in `version.env` and the version in
`Sources/TingCore/TingVersion.swift`, runs `release.sh`, commits the release as
`Release Ting <version>`, pushes `main` (with all local commits), runs
`publish.sh`, then in the landing checkout runs `npm run sync:github`,
`npm run build`, `npm test`, commits, pushes, runs `npm run deploy` and waits
until `https://bobuk.io/apps/ting/appcast.xml` has the new build. It ends with
`RELEASE_DONE: Ting <version> (build <n>)`.

If a run fails, fix the cause and run the same command again. The script
chooses what to do from GitHub and the live feed, not from a state file: while
there is no GitHub release of the version in `version.env`, it builds that
version again without raising it; when the release is published but the live
feed lacks its build, it only copies the appcast to the landing site, updates
the Homebrew cask and deploys the site. It never rolls anything back.

### Release by hand

1. Increase `MARKETING_VERSION` and `BUILD_NUMBER` in `version.env` and add
   `docs/releases/v<version>.md`.
2. Build, notarize, sign the appcast and install:

   ```sh
   APP_IDENTITY='Developer ID Application: Your Name (TEAMID)' \
   NOTARY_PROFILE=ting \
   ./Scripts/release.sh
   ```

   The script runs the tests, builds a universal app, removes debug-map paths,
   checks the bundle and local-path leakage, signs and notarizes the app, staples
   the ticket, writes the ZIP, `SHA256SUMS.txt` and the signed `appcast.xml` to
   `dist/`, then **installs the release at `/Applications/Ting.app` and restarts
   it**. The previous installation is kept until the new one starts.
3. Commit, push `main`, then publish:

   ```sh
   ./Scripts/publish.sh
   ```

   The release is created as a draft, all assets are uploaded, and then it is
   published, so the feed never points at an incomplete release. The script then
   copies `appcast.xml` into the landing site checkout (`../landing`, or
   `LANDING`) as `public/apps/ting/appcast.xml`. It then updates the cask in
   `bobuk-io/homebrew-tap` with the archive version and SHA-256. The GitHub CLI
   account must have write access to that repository. If the tap update fails,
   the release remains published: retry `bash Scripts/update_homebrew.sh --publish`
   without rerunning `publish.sh`. To preview the cask without publishing, run
   `bash Scripts/update_homebrew.sh`.
4. Publish the landing site (see its `docs/updating.md`): the feed of installed
   copies is `https://bobuk.io/apps/ting/appcast.xml`. The GitHub release keeps
   its `appcast.xml` for Ting 0.6.1 and older, which still read
   `releases/latest/download/appcast.xml`.

Back up the Sparkle private key securely offline: without it, installed copies
cannot verify future updates. Never commit or publish it.

## License

Original Ting code is licensed under [0BSD](LICENSE). Adapted build and release
scripts keep their upstream MIT license; see
[THIRD_PARTY_NOTICES.md](THIRD_PARTY_NOTICES.md). Sparkle is distributed under
its own license, included in the notices.
