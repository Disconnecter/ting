# Configuring Ting with a coding agent

This document tells a coding agent such as Claude Code, Codex or pi how to
change Ting for a person: key bindings, settings and micro-apps. It ships inside
the app as `Ting.app/Contents/Resources/CONFIGURING.md`; the micro-app format is
in `FORMAT.md` next to it.

The person asks in plain words, for example:

> Write a new micro-app: Leader `t` `a` should translate the clipboard into German.

> Bind Leader `w` `j` to https://jira.example.com.

> Open Ghostty with Leader `space`.

## Files

| What | Where |
|---|---|
| Settings and bindings | `~/.config/ting/config.json` |
| Micro-apps | `~/.config/ting/micro/*.yaml` |
| Libraries of micro-apps | `~/.config/ting/micro/libs/*.yaml` |
| Problems of micro-app files | `~/.config/ting/micro-errors.log` |
| Console tool | `/Applications/Ting.app/Contents/MacOS/ting-micro` |
| Micro-app format | `/Applications/Ting.app/Contents/Resources/FORMAT.md` |

With `TING_CONFIG=/path/x.json` set, the config is that file, the micro-apps are
in `/path/x.json.micro/` and the log is `/path/x.json.micro-errors.log`.

Ting reloads `config.json` and the micro-apps folder by itself when they change;
nothing needs a restart. **Never** write the approvals and remembered values in
`~/Library/Application Support/Ting/`, and never change `Ting.app`.

## `config.json`

```json
{
  "version": 1,
  "leader": "home",
  "items": [
    { "key": "space", "label": "WezTerm", "app": "com.github.wez.wezterm" },
    { "key": "t", "label": "Translate", "items": [
      { "key": "u", "label": "Translate to Ukrainian", "micro": "translate-ukrainian" }
    ]},
    { "key": "w", "label": "Web", "items": [
      { "key": "g", "label": "GitHub", "url": "https://github.com" }
    ]}
  ]
}
```

- `items` is a tree. A key sequence such as Leader `t` `a` is the item with
  `"key": "a"` inside the group with `"key": "t"`.
- Each item has `key`, an optional `label` (shown in the menu) and exactly one
  action: `items` (a group), `app` (a bundle identifier), `url` (any URL,
  including schemes such as `raycast://`), `micro` (a micro-app id) or `open`
  (a Ting window: `"launcha"` or `"clipbawd"`).
- `key`: a lower-case Latin letter or digit, `space`, `return` or `f1`…`f20`. Keys
  are Latin even when the person types with another layout.
- In one group a key is used once.
- Settings: `leader` (a key name with optional modifiers, such as `home`,
  `f13`, `option+shift+cmd+f`; never a modifier alone), `showDelay` (seconds,
  0–2), `unknownKey` (`shake` or `close`), `appearance` (`dark` or `light`),
  `launchAtLogin`, `showMenuBarIcon`, `showPanelHeader`, `playSound` (booleans),
  `sound` (a system sound name from `/System/Library/Sounds` without extension,
  default `Tink`; an unknown name plays `Tink`), `soundVolume` (0–1, default 0.5),
  `launcha` (`{"hotkey": null, "doubleTap": true, "doubleTapWindow": 0.3, "calculator": true,
  "converter": true}`; `calculator` shows the value of a query such as `2*(3+4)` first in
  launcha, `converter` that of `5 yd to m`, `255 to hex` or `now + 2 days`),
  `clipbawd` (`{"hotkey": null, "enabled": true, "fetchLinks": false, "maxItems": 200,
  "excludedApps": [], "ignoredPrefixes": []}`; `enabled: false` turns clipbawd off: Ting never reads the clipboard,
  the hotkey is free and the window does not open;
  `fetchLinks` loads the title, icon or image of a copied link, `maxItems` is
  20–1000, `excludedApps` lists bundle identifiers whose copies are never kept,
  `ignoredPrefixes` lists case-sensitive starts of text that is never kept). The
  Clipbawd hotkey cannot be the leader or the launcha hotkey. Clipbawd is also searchable by name in launcha while enabled.
- Approved micro-app templates can read `${clipboard[-1]}` (newest history entry), `${clipboard[-2]}`, etc. The snapshot is fixed at run start. Pass history to shell through `env:`; never interpolate it into code. Disabled/unavailable history, images and missing entries fail explicitly. Files yield newline-separated paths. The headless runner has no session history.

### Direct application hotkeys

`appHotkeys` is an optional list, empty by default. In launcha, select an app
and press Command-Shift-K, or open its context menu and choose **Set Global
Shortcut…**. Press the shortcut, then Return or Save. Record Again captures
another key, Remove Global Shortcut clears the assignment, and Esc cancels.
Files, calculations and micro-apps have no direct application shortcut editor.

```json
"appHotkeys": [
  {
    "id": "app:com.apple.safari",
    "name": "Safari",
    "path": "/Applications/Safari.app",
    "hotkey": "cmd+f12"
  }
]
```

This fragment belongs at the top level of `config.json`. `id` is the stable
launcha/history identity, normally `app:` plus the lower-case bundle identifier;
keep the id produced by launcha for apps without a bundle identifier. `path`
is the absolute path of the indexed `.app` bundle, not an executable. Ting opens
that exact copy or brings it forward. `name` is its display name. `hotkey` uses
the same syntax as the leader: a non-modifier key, optionally with modifiers.

Each app has one shortcut and each shortcut belongs to one app. Saving in
launcha replaces both the app's old shortcut and any other app's assignment to
the new shortcut; the editor names the other app before Save. The leader and
`launcha.hotkey` are always reserved, even while recording suspends them. An
OS registration conflict or failed save keeps the old configuration.

In a hand-written file, invalid or duplicate entries produce validation
issues; only the first valid assignment for an app and key is registered.
An app shortcut that conflicts with the leader or launcha is disabled, never
the protected shortcut. Changing a protected key later can therefore disable
an app assignment without deleting it. Pausing Ting or recording a shortcut
suspends application hotkeys too. Holding an app shortcut launches only once
until release. Successful launches count toward launcha's ranking.

Find an app's bundle identifier with
`mdls -name kMDItemCFBundleIdentifier -r /Applications/Ghostty.app`.

## Changing the config

1. Read `config.json` and find where the change goes. Keep every other item,
   setting and the order of the file.
2. Ask the person first when the change would replace or move something:
   - the sequence is already bound;
   - a shorter part of it is an app, URL or micro-app, not a group. For example,
     Leader `t` opens Terminal, and you need Leader `t` `a`.
3. Copy the file to a backup in a temporary folder, then edit it.
4. Check the result:

   ```sh
   /Applications/Ting.app/Contents/MacOS/ting-micro check-config
   ```

   It prints `<file>: ok`, or one line per problem: JSON and format errors,
   duplicate keys, empty targets, bad URLs and `micro` ids that do not load.
   Fix every problem. With a broken file Ting keeps its last good settings and
   shows the error in its menu.
5. Tell the person what changed and the backup path.

## Adding a micro-app with a key

1. Read `FORMAT.md` and follow its workflow: look for a library to reuse, write
   and check the file in a temporary folder, then move it into
   `~/.config/ting/micro/`.
2. Bind it: add `{"key": "…", "label": "…", "micro": "<id>"}` at the sequence the
   person asked for, creating the groups on the way.
3. Run `ting-micro check-config`. It also checks that the micro-app id loads.
4. Tell the person that the first start shows an approval panel and that `⌘↩`
   approves the file. Name any API key or keychain item the micro-app needs.

### Worked example

> Write a new micro-app: Leader `t` `a` should translate the clipboard into German.

1. `~/.config/ting/micro/libs/translate.yaml` exists and its step has
   `id: translate`. Inherit it instead of copying the prompt. Write
   `translate-german.yaml` in a temporary folder:

   ```yaml
   format: ting.microapp/2
   inherit: translate
   id: translate-german
   name: Translate to German
   description: Translate the clipboard text into German with OpenAI.

   steps:
     - id: translate
       params:
         language: German
   ```

   Without that library, write the micro-app with its own `ai` step, or first
   move the shared steps into a new library if other translate micro-apps
   exist.
2. Check the file against the person's libraries:

   ```sh
   MICRO=/Applications/Ting.app/Contents/MacOS/ting-micro
   "$MICRO" check --libs ~/.config/ting/micro/libs "$dir/translate-german.yaml"
   ```

   Then move it into `~/.config/ting/micro/` and read `micro-errors.log`.
3. In `config.json`, the group `t` exists (`"label": "Translate"`). Key `a` is
   free there, so add:

   ```json
   { "key": "a", "label": "Translate to German", "micro": "translate-german" }
   ```

   Without a group `t`, add `{"key": "t", "label": "Translate", "items": [ … ]}`.
   If `t` is bound to something else, ask first.
4. Run `"$MICRO" check-config` until it prints `ok`.
5. Report: "Leader t a runs Translate to German. Approve it with ⌘↩ at the first
   start. It uses OPENAI_API_KEY from your shell."

Do not run the micro-app yourself to test it when it calls a paid API or changes
files; ask first. `ting-micro run` runs it without the panels and the clipboard.

## A prompt for the person

The person can start an agent with this text and add the task at the end:

```text
Change my Ting setup. Read /Applications/Ting.app/Contents/Resources/CONFIGURING.md
and follow it; for micro-apps it points to FORMAT.md. Check every file with
ting-micro before you finish. Never put API keys into files and never touch
~/Library/Application Support/Ting/.

My task:
```

**Copy Agent Prompt** in the Ting menu copies a ready text with the paths of
this Mac.
