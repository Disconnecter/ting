# Glossary

The terms used for Ting in code, documents and the interface.

## Menus

- **leader:** the global key, alone or with modifiers, that opens selecta. A
  modifier key on its own is never a leader.
- **selecta:** the leader menu: one key or a short sequence opens an app, a URL
  or a micro-app.
- **launcha:** the search panel: type part of the name of an app, a micro-app or
  a file and press `Return`.
- **binding:** an item of `config.json` with a key and exactly one of `items`
  (a group), `app`, `url` or `micro`.

## Micro-apps

- **micro-app:** a small tool that Ting runs: one YAML file in the micro-apps
  folder (`~/.config/ting/micro/`) that declares its parameters and exactly one
  shell command. The format is described in `docs/micro-apps/FORMAT.md`.
- **parameter:** a value the micro-app asks for, declared under `params`, of type
  `text` or `choice`, required or optional. The command reads it as the
  environment variable `TING_` + the upper-case name.
- **command:** the one shell command of a micro-app, run with `/bin/sh -c` as the
  user, with the clipboard on stdin when `input: clipboard`.
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
  command of a new or changed micro-app; `⌘Return` approves and runs, `Esc`
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
