# Glossary

The terms used for Ting in code, documents and the interface.

## Menus

- **leader:** either of up to two global keys that open the same selecta menu. Each can be used alone or with modifiers. A
  modifier key on its own is never a leader.
- **selecta:** the leader menu: one key or a short sequence opens an app, a URL
  or a micro-app.
- **launcha:** the search panel: type part of the name of an app, a micro-app or
  a file and press `Return`. A query of digits and an operator, such as
  `2*(3+4)`, shows its value first; `Return` copies it (the launcha calculator).
  So does a conversion, such as `5 yd to m` or `now + 2 days` (the launcha
  converter).
- **clipbawd:** the clipboard history panel: search on top, retained entries on
  the left, a preview with details on the right. `Return` pastes the
  item into the app in front, `⌘Return` copies it. By default, the history lives
  in memory only and is gone when Ting quits; persistent history can be enabled.
- **persistent history:** a Clipbawd option that keeps clipboard history across Ting launches; turning it off forgets the stored history.
- **clipboard entry:** one retained clipboard copy with its supported representations. Copying the same content again updates its entry instead of adding a duplicate.
- **retention limits:** the maximum number, total size and age of clipboard entries. The oldest copies are forgotten until all enabled limits are satisfied; reusing an entry is not a new copy.
- **binding:** an item of `config.json` with a key and exactly one of `items`
  (a group), `app`, `url`, `micro` or `open` (`launcha` or `clipbawd`).

## Micro-apps

- **micro-app:** a small tool that Ting runs: one YAML file in the micro-apps
  folder (`~/.config/ting/micro/`) that declares its parameters and either one
  shell command or a list of steps. The format is described in
  `docs/micro-apps/FORMAT.md`.
- **parameter:** a value the micro-app asks for, declared under `params`, of type
  `text` or `choice`, required or optional. Code reads it as the environment
  variable `TING_` + the upper-case name; the other keys of a step as
  `${params.NAME}`.
- **command:** the one shell command of a micro-app, run with `/bin/sh -c` as the
  user, with the clipboard on stdin when `input: clipboard`; the same as one
  `command` step.
- **step:** one part of a micro-app script, under `steps`: `command`, `python`,
  `url`, `ai`, `text`, `json`, `open`, `notify`, `keys`, `paste` or `call`. The output of a step is the
  input of the next one; the output of the last step is the result.
- **variable:** a `${…}` value in a step key other than code: `${input}`,
  `${params.NAME}`, `${steps.ID}`, `${context.SOURCE.FIELD}`, an environment
  variable `${NAME}` or a keychain item `${keychain.SERVICE}`, with optional
  filters (`|url`, `|json`, `|trim`, `|base64`).
- **context:** what Ting reads at the start of a micro-app that lists it in
  `context:`: `app`, `finder`, `browser`, `selection` and `window`. Steps read it
  as `${context.SOURCE.FIELD}`, code as `$TING_CONTEXT_SOURCE_FIELD`.
- **target app:** the app that was in front when a micro-app started. The
  context is read from it, and `keys`, `paste` and the `app` output go to it.
- **keys step:** a step `keys: cmd+s` or `keys: [cmd+a, delete]` that presses
  keys in the target app.
- **paste step:** a step `paste: TEXT` that pastes text into the target app
  through the clipboard and puts the clipboard back.
- **app output:** `output.to: [app]`: the result is pasted into the target app.
- **library:** a file `libs/NAME.yaml` in the micro-apps folder, format
  `ting.microlib/1`, with steps that several micro-apps share. It is not a
  micro-app of its own.
- **call step:** a step `call: NAME` that runs the steps of a library with its
  `params`.
- **inherit:** the key of a micro-app made of a library with the file's keys over
  it; changes of `steps` name a library step by its `id`.
- **step params:** `params:` of one step: values that step reads as
  `${params.NAME}` and `$TING_NAME`; for a `call` step, the library's params.
- **streaming step:** a `command` or `python` step with `stream: true`; it runs
  together with the step before it and reads its output while it comes.
- **micro-app id:** the kebab-case name a micro-app is known by: the `id` key of
  the file, or, without it, the file name without `.yaml`. Two files with one id:
  the first by file name works, the second is broken.
- **micro-app binding:** a binding with `"micro": "<id>"` that starts a
  micro-app. It holds no code; a binding to an id that is not loaded keeps the
  config valid and shows as not working.
- **micro-app approval:** the person's consent to run one exact file content:
  the SHA-256 of the whole file, stored by micro-app id in
  `micro-approvals.json`. Any change of the file asks again.
- **approval panel:** the panel that shows the name, the file and the full
  command (or, for a steps file, the whole file text) of a new or changed
  micro-app; `⌘Return` approves and runs, `Esc`
  refuses.
- **parameter panel:** the one form that asks for all parameters of a
  micro-app before the run, in file order; it also shows that the command runs.
- **result panel:** the panel that shows the result of a run, or its error with
  the exit code, stderr and stdout.
- **remembered values:** the parameter values of the last started run of a
  micro-app, stored as plain text by micro-app id in `micro-values.json` and
  shown at the next start; `remember: false` turns them off.
- **output format:** how the result panel shows stdout, set by `output.as`:
  `markdown` (default), `console`, `text` or `code`. An error is always shown as
  console text.
- **micro-app error log:** `micro-errors.log` next to the config file
  (`~/.config/ting/micro-errors.log`), written again on each load of the folder,
  with one `file:line: message` line per problem of a micro-app file; empty when
  all files are good.
- **check command:** `Ting --check <file.yaml> [more files]`, a mode of the Ting
  executable (`Ting.app/Contents/MacOS/Ting`) that checks micro-app files without
  starting Ting or writing any file. It prints one `file:line: message` line per
  problem, with the text of the micro-app error log, or `<file>: ok`, and exits
  with 0 (all good), 1 (a file has a problem) or 2 (a wrong call).
- **format document:** `docs/micro-apps/FORMAT.md`, the description of the
  micro-app format with the full text of the five examples. It ships inside the
  app as `Ting.app/Contents/Resources/FORMAT.md`.
- **coding agent:** a program that writes code from the person's request, such
  as Claude Code, Codex or pi. It can write a micro-app from the format
  document, check it with the check command and save it in the micro-apps
  folder; it does not change `config.json`, and the person approves the file
  and binds its key.
- **agent prompt:** the ready English text for a coding agent that **Copy Agent
  Prompt** (menu-bar menu and Settings › Advanced) puts on the clipboard and
  `Ting --agent-prompt` prints. It names the format document inside Ting.app,
  the GitHub link of the running version as the fallback, the check command
  with the real path of the executable and the micro-apps folder, says not to
  change `config.json`, and ends open for the person's task.
