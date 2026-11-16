# Micro-app format (`ting.microapp/2`)

A micro-app is a small tool that Ting runs from a key: it runs **one shell
command**, can ask for a few parameters, can read the clipboard and shows or
copies the result. Each micro-app is one YAML file. Files are mostly written by
an AI assistant such as Claude Code, so the format is strict and easy to check:
every mistake is reported with the file name and the line.

The five files in [`examples/`](examples/) are complete, working micro-apps for
macOS 14 and later. Ting does not install them: copy the ones you want into the
micro-apps folder.

## Folder

Ting loads every `*.yaml` file of the folder `micro/` next to the config file:
`~/.config/ting/micro/`. Subfolders and other files (also `.yml`) are ignored. A
missing folder means no micro-apps. Ting loads the folder again, without a
restart, when a file is added, changed or removed, and reads the user's PATH
again at that moment. **Settings › Advanced › Open Folder in Finder** opens the
folder and creates it when it is missing.

With `TING_CONFIG` set, the folder and the error log sit next to that file with
its name in front: `TING_CONFIG=/tmp/ting-test.json` uses the folder
`/tmp/ting-test.json.micro/` and the log `/tmp/ting-test.json.micro-errors.log`.

## How a micro-app runs

Ting never pastes anything into the command text:

- the command runs with `/bin/sh -c`, as the user, with the user's full rights,
  no sandbox and the home folder as the working folder;
- `PATH` is the PATH of the user's login shell (zsh, bash or fish), read once
  when Ting starts and again on each load of the folder, so Homebrew and npm
  tools are found. If the shell does not answer within 5 seconds, Ting uses its
  own PATH plus `/opt/homebrew/bin` and `/usr/local/bin`;
- before the command starts, every program of `tools` must be on that PATH;
  otherwise nothing runs and Ting shows the error `tool not found: <name>`;
- with `input: clipboard`, the clipboard text goes to the command's **stdin**;
  with `input: none`, stdin is empty;
- each parameter becomes an **environment variable**: `TING_` and the upper-case
  parameter name (`domain` → `$TING_DOMAIN`). A file cannot choose other
  variable names;
- on exit code 0, the command's **stdout**, read as UTF-8 and without the line
  breaks at its end, is the result and goes to `output.to`. An empty result
  copies nothing and shows "No output";
- on a non-zero exit code, the result panel shows an error mark, the exit code,
  stderr and stdout, and **nothing goes to the clipboard**, whatever `output.to`
  says;
- stdout and stderr are each cut at 1 MB; the panel then shows a note that the
  output was cut;
- the command may run at most **60 seconds**. Then Ting stops it and its child
  processes (a polite stop signal first, a hard kill a moment later) and shows
  "stopped after 60 s" with the output that came before. `Esc` stops it earlier,
  silently, and leaves the clipboard as it was. A new micro-app start also
  stops the running one: only one micro-app is open at a time.

All transformation is done by the command itself (`perl`, `awk`, `tr`,
`base64`, …). The format has no templates, filters or expressions. Quote the
variables in the command (`"$TING_DOMAIN"`), as in any shell script.

The command runs without a locale. A command that counts or changes non-ASCII
characters must set one itself, for example `LC_ALL=en_US.UTF-8` or `perl -CS`.
Only use tools that ship with macOS 14, or list the extra ones in `tools`
(`jq`, for example, ships only with macOS 15 and later).

## Example

```yaml
format: ting.microapp/2          # required, exactly this text
id: dns-lookup                   # optional; the file name without .yaml if absent
name: DNS lookup                 # optional; shown in menus, the id if absent
description: Look up a domain.   # required, one line, shown as a hint
tools: [dig, whois]              # optional; commands the script expects on PATH
hidden: false                    # optional; true keeps it out of launcha
remember: true                   # optional; false: do not offer the last values

params:                          # optional; asked in this order
  - name: domain                 # a-z, 0-9 and _ only → $TING_DOMAIN
    type: text                   # text | choice
    required: true               # always written out
    prompt: Domain               # optional; the name if absent
  - name: record
    type: choice
    required: false
    default: A                   # an optional param must have a default
    choices: [A, AAAA, MX, TXT]

input: none                      # required: clipboard | none
command: |                       # required: one string, run with /bin/sh -c
  dig +noall +answer "$TING_DOMAIN" "$TING_RECORD"
output:                          # required
  to: [panel]                    # one or both of: clipboard, panel
  as: console                    # optional: text | markdown | code | console
```

## File

- One file holds one micro-app. The file name ends in `.yaml`.
- The **micro-app id** is the `id` key, or, without it, the file name without
  `.yaml`. It is kebab-case: words of `a-z` and `0-9` joined by single `-`
  (`format-json`, `dns-lookup`). The `id` key does not have to equal the file
  name, so a binding keeps working when the file is renamed.
- Two files with the same id: the first by file name works, the second is a
  broken file with a `duplicate id` error.

## Keys

### Top level

| Key | Required | Value |
|---|---|---|
| `format` | yes | Exactly `ting.microapp/2`. |
| `id` | no | Kebab-case text. If absent, the id is the file name without `.yaml`. |
| `name` | no | One line of text shown in selecta and launcha. If absent, the id is shown. |
| `description` | yes | One non-empty line that says what the micro-app does; shown as a hint. |
| `tools` | no | A list of command names the command expects on `PATH`, such as `[dig, whois]`. Names use letters, digits, `.`, `_`, `+` and `-`. |
| `hidden` | no | `true` or `false` (default `false`). A hidden micro-app is not listed in launcha; it still starts from a key binding. |
| `remember` | no | `true` or `false` (default `true`). With `true`, Ting fills each parameter with the value used last time; with `false`, it starts from the defaults every time. |
| `params` | no | A list of parameters, asked in this order. See below. |
| `input` | yes | `clipboard` (the clipboard text goes to stdin) or `none` (empty stdin). |
| `command` | yes | One non-empty string of shell code for `/bin/sh -c`. Use a literal block `command: \|` for several lines. |
| `output` | yes | A map with `to` and, optionally, `as`. See below. |

### Each parameter

| Key | Required | Value |
|---|---|---|
| `name` | yes | `a-z`, `0-9` and `_` only. Unique in the file. The command reads it as `$TING_` + the upper-case name. |
| `type` | yes | `text` (any text the person types) or `choice` (one of `choices`). |
| `required` | yes | `true` or `false`, always written out. |
| `default` | for `required: false`, not allowed for `required: true` | Text. For a `choice`, one of `choices`. |
| `choices` | for `type: choice` | A non-empty list of different values, such as `[A, AAAA, MX]`. Not allowed for `text`. |
| `prompt` | no | One line shown when Ting asks for the value. If absent, the name is shown. |

Ting asks for the parameters in one parameter panel, in file order, with the
`prompt` as label. Required parameters are always shown; optional ones are behind
`⌘O`, filled with their `default`. A required `text` must not be empty; an
optional `text` made empty gives the empty value. A `choice` gives the marked
option. A file with one `choice` parameter and nothing else opens as a list. With
`remember: true` the values of the last started run come back next time; they are
stored as plain text, so do not use a remembered parameter for a secret.

### `output`

| Key | Required | Value |
|---|---|---|
| `to` | yes | A non-empty list of `clipboard`, `panel` or both, each at most once. `clipboard` replaces the clipboard with stdout; `panel` shows stdout in the result panel. |
| `as` | no | How the panel shows stdout: `markdown`, `console`, `text` or `code`. Default `markdown`. |

The output styles of the result panel:

- `markdown` (the default): formatted text. Ting shows `#` headings, `-`, `*` and
  `1.` lists (nested by two spaces), `**bold**`, `*italic*`, `` `inline code` ``,
  fenced code blocks, `>` quotes, `---` rules and tables (`| a | b |` with a
  `|---|--:|` line under the first row) as aligned columns; `:` in that line aligns
  a column right or centre. A table whose first row is empty has no header. Line
  breaks inside a paragraph stay. Everything else is shown as written.
- `console`: monospaced terminal output. ANSI colour and style codes (`ESC[...m`:
  the 16 colours, 256 colours, 24-bit colours, bold, dim, italic, underline,
  inverse, strikethrough) are shown as colours and styles; every other escape code
  and control character is removed.
- `text`: plain text in the system font, shown as written.
- `code`: monospaced plain text, shown as written.

An error (a non-zero exit, a timeout, a micro-app that cannot start) is always
shown as `console` text, whatever `as` says. Enter, ⌘C without a selection and the
`clipboard` target copy the plain result: stdout as it is, and for `console` without
its escape codes. ⌘C with a selection copies the selected text as shown, without
styling.

## Rules of the checker

Ting checks a file before it offers the micro-app. A file with any error is not
loaded; every error is reported as `file:line: message`. The checker reports:

- YAML outside the subset below;
- an unknown key at the top level, in a parameter or in `output`;
- a missing required key;
- `format` other than `ting.microapp/2`;
- an `id` that is not kebab-case; without `id`, a file name that is not
  kebab-case; an id that an earlier file (by file name) already uses;
- an empty or multi-line `name`, `description` or `prompt`;
- `tools` that is not a list of command names;
- `hidden`, `required` or `remember` that is not `true` or `false` (`yes`,
  `no`, `1` and quoted `"true"` are errors);
- a parameter name outside `a-z`, `0-9` and `_`, or used twice;
- a `type` other than `text` or `choice`;
- `required: false` without `default`, or `required: true` with a `default`
  (remembered values already fill in a required parameter);
- a `choice` without `choices`, with an empty list or a repeated value, or with a
  `default` that is not one of the choices; `choices` on a `text` parameter;
- an `input` other than `clipboard` or `none`;
- an empty `command`, or a `command` that is not a single string;
- in `command`: a `{name}` template for a parameter name (use `"$TING_NAME"`);
  a `$TING_…` or `${TING_…}` variable that is not a declared parameter; a
  declared parameter that the command never reads;
- an `output` that is not a map, without `to`, with an empty or repeated `to`, a
  target other than `clipboard` or `panel`, or an `as` outside the four styles.

## Errors and the error log

A broken file is not used. Ting marks it in the menu-bar menu, lists every error
with file and line in **Settings › Advanced**, shows a short message when a change
breaks a file, and writes the **micro-app error log** `micro-errors.log` next to
the config file: `~/.config/ting/micro-errors.log` (with `TING_CONFIG` set, see
[Folder](#folder)). Ting writes the log again on each load of the folder. It has
one line per problem, `file:line: message`, sorted by file and line, and it is
empty when all files are good:

```text
dns-lookup.yaml:14: `params[1].type` is `number`; it must be one of: text, choice
dns-lookup.yaml:27: command: `$TING_RECORD_TYPE` is not a declared param
```

### How to check a file (for Claude Code)

There is no separate check command. To check a file you wrote:

1. Save it as `<id>.yaml` in the micro-apps folder. Ting loads it within a
   moment.
2. Read `micro-errors.log`. Lines that start with your file name are its errors;
   no such line means the file is good. Fix the file and read the log again.
3. A good file is not run by itself: the person approves it at its first start.
   To try the command without Ting, run it like Ting does, for example
   `printf '%s' 'input' | TING_MODE=upper /bin/sh -c "$(cat command.sh)"`, with
   `LANG` and `LC_*` unset.

For tests and experiments, use a temporary config with `TING_CONFIG`, so the
person's own folder, log and approvals are not touched.

## Approval, bindings and state

Before the first run, and after any change to the file, Ting shows the approval
panel with the name, the file and the full command; `⌘Return` approves and runs,
`Esc` refuses. The approval is the SHA-256 of the whole file content, stored by
micro-app id; it is not part of the file. A binding in `config.json` names the
id: `{"key": "j", "micro": "format-json"}`. Every micro-app that is not
`hidden: true` can also be started by name from launcha.

Ting keeps its own state for micro-apps outside the folder and outside
`config.json`, in `~/Library/Application Support/Ting/`:

- `micro-approvals.json`: the approved hash of each micro-app id;
- `micro-values.json`: the remembered values of the last started run of each
  micro-app, as plain text (not for `remember: false`).

With `TING_CONFIG` set, both sit next to that file with its name in front, such
as `/tmp/ting-test.json.micro-approvals.json`.

## YAML subset

Micro-app files use a strict subset of YAML. Anything outside it is an error
with a line number, even when other YAML tools would accept it.

Allowed:

- maps of `key: value` lines; keys are plain words of letters, digits, `_` and
  `-`, each at most once per map;
- lists of `- item` lines, indented under their key or at the same column;
- plain values on one line: `text`, `A`, `true`. A plain value cannot start
  with `@`, `` ` `` or `%` and cannot contain `: `; quote such values;
- quoted values on one line: `'single'` (write `''` for a `'`) and `"double"`
  (escapes `\\`, `\"`, `\/`, `\n`, `\t`, `\r`, `\0`, `\uXXXX`);
- one-line lists of values: `[a, 'b c', "d"]`;
- literal blocks for multi-line text: `|`, `|-` (no final line break) and `|+`
  (keep trailing blank lines). The text is kept exactly as written: quotes, `$`,
  `;;`, `%`, `'`, `#` and blank lines are part of it. Only the common
  indentation is removed;
- `#` comments on their own line or after a value (inside a literal block, `#`
  is text);
- an optional `---` on the first line;
- empty values, `~` and `null` (they mean "no value", so for a key that needs a
  value they are an error).

Refused:

- anchors (`&`), aliases (`*`) and tags (`!`, `!!str`);
- directives (`%YAML`), a second document (`---`) and document end markers
  (`...`);
- folded blocks (`>`, `>-`) and indentation indicators (`|2`);
- flow maps (`{a: 1}`) and nested flow collections (`[a, [b]]`);
- complex keys (`? key`) and quoted keys;
- plain or quoted values that continue on the next line;
- tabs in indentation;
- duplicate keys.
