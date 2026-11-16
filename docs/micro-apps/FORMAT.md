# Micro-app format (`ting.microapp/2`)

A micro-app is a small tool that Ting runs from a key: it runs **one shell
command**, can ask for a few parameters, can read the clipboard and shows or
copies the result. Each micro-app is one YAML file. Files are written by the
person or by a coding agent such as Claude Code, Codex or pi, so the format is
strict and easy to check: every mistake is reported with the file name and the
line.

This document is complete on its own: it describes every key and rule and holds
the full text of five working micro-apps (see [Examples](#examples)). The same
text ships inside the app as `Ting.app/Contents/Resources/FORMAT.md`.

## Writing a micro-app: step by step

These steps are for whoever writes the file, a person or a coding agent.

1. Read this document to the end, including the examples.
2. Choose the micro-app id: kebab-case, such as `sort-lines` (see [File](#file)).
3. Write the micro-app as one file named `<id>.yaml` in a new temporary folder,
   for example one made with `mktemp -d`. Use the final file name already: the
   id comes from it when the file has no `id` key. Do not write an unfinished
   file into the micro-apps folder: Ting loads it at once and reports it as
   broken.
4. Check the file with the check command (see [How to check a file](#how-to-check-a-file)):

   ```sh
   /Applications/Ting.app/Contents/MacOS/Ting --check "$dir/sort-lines.yaml"
   ```

   Use the path of the Ting executable of this Mac when Ting is installed
   elsewhere.
5. Fix every reported problem and run the check command again, until it prints
   `<file>: ok` and exits with 0.
6. Optionally try the command the way Ting runs it (see
   [Trying the command](#trying-the-command)).
7. Move the good file into the micro-apps folder `~/.config/ting/micro/` (create
   the folder when it is missing; with `TING_CONFIG` set, use the folder next to
   that file, see [Folder](#folder)). Do not replace a file that is already
   there unless the person asked to change that micro-app. Then read the
   micro-app error log `~/.config/ting/micro-errors.log`: a line that starts with
   the file name means a problem the check command could not see, such as an id
   that another file of the folder already uses.
8. **Do not change `config.json`**, and do not write the approvals and values in
   `~/Library/Application Support/Ting/`. The person approves the new file in the
   approval panel at its first start and binds a key to it themselves (in
   **Settings › Bindings**, **+ › Micro-app**), or starts it by name from
   launcha. Tell the person the id and the file name.

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

## All keys at a glance

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
  target other than `clipboard` or `panel`, or an `as` outside the four styles;
- a file larger than 256 KB, or a file that is not UTF-8 text.

## How to check a file

There are two ways, both with the same messages: the check command, before the
file goes into the micro-apps folder, and the micro-app error log, after.

### The check command

The Ting executable checks micro-app files when it is started with `--check`:

```sh
/Applications/Ting.app/Contents/MacOS/Ting --check <file.yaml> [more files]
```

It checks the given files and exits. It does not start Ting: it opens no window
and no menu-bar icon, does not read `config.json`, writes no file (no log, no
approvals, no values) and works while Ting is running.

On standard output it prints one line per problem, `file:line: message`, with
the same message as the micro-app error log, sorted by file and line. The file is
written as it was given. A good file gives one line `<file>: ok`:

```text
$ Ting --check sort-lines.yaml
sort-lines.yaml:5: param `order` is never used: the command must read `$TING_ORDER`
sort-lines.yaml:7: params[0]: an optional param needs a `default`
sort-lines.yaml:10: command: `$TING_ORDR` is not a declared param
sort-lines.yaml:12: `output.to` is `clip`; it must be one of: clipboard, panel
$ Ting --check sort-lines.yaml
sort-lines.yaml: ok
```

Exit codes:

| Code | Meaning |
|---|---|
| `0` | Every given file is good. |
| `1` | At least one file has a problem: fix the file. |
| `2` | A wrong call: no file given, a file that cannot be read, or a name that does not end in `.yaml`. The message and the usage line go to standard error; fix the call. |

With several files, the id rules of the folder apply to the given files: of two
files with one id, the later one by path gets the `duplicate id` problem. The
check command does not look at the files that are already in the micro-apps
folder; a duplicate with one of them shows only in the micro-app error log
after the file is saved there.

### The micro-app error log

A broken file in the micro-apps folder is not used. Ting marks it in the
menu-bar menu, lists every error with file and line in **Settings › Advanced**,
shows a short message when a change breaks a file, and writes the **micro-app
error log** `micro-errors.log` next to the config file:
`~/.config/ting/micro-errors.log` (with `TING_CONFIG` set, see
[Folder](#folder)). Ting writes the log again on each load of the folder. It has
one line per problem, `file:line: message`, sorted by file and line, and it is
empty when all files are good:

```text
dns-lookup.yaml:14: `params[1].type` is `number`; it must be one of: text, choice
dns-lookup.yaml:27: command: `$TING_RECORD_TYPE` is not a declared param
```

Lines that start with the file name are the errors of that file; no such line
means the file is good.

### Trying the command

A good file is not run by Ting by itself: the person approves it at its first
start. To try the command without Ting, run it as Ting does, with the clipboard
text on stdin, each parameter as a `TING_` variable and `LANG` and `LC_*` unset,
for example:

```sh
printf '%s' 'some text' | env -u LANG -u LC_ALL -u LC_CTYPE TING_MODE=upper /bin/sh -c "$(cat command.sh)"
```

For tests and experiments with Ting itself, use a temporary config with
`TING_CONFIG`, so the person's own folder, log and approvals are not touched.

## Approval, bindings and state

Before the first run, and after any change to the file, Ting shows the approval
panel with the name, the file and the full command; `⌘Return` approves and runs,
`Esc` refuses. The approval is the SHA-256 of the whole file content, stored by
micro-app id; it is not part of the file. A binding in `config.json` names the
id: `{"key": "j", "micro": "format-json"}`. The person adds it, in
**Settings › Bindings** or in `config.json`; a coding agent does not. Every
micro-app that is not `hidden: true` can also be started by name from launcha.

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

## Examples

Five complete, working micro-apps for macOS 14 and later. Each passes the check
command as it is. Ting does not install them: to use one, save its text under
the file name of its heading in the micro-apps folder. The same files are in
`docs/micro-apps/examples/` of the Ting repository.

### Format JSON: `format-json.yaml`

Pretty-prints the JSON of the clipboard with sorted keys, puts it back on the clipboard and shows it as code. No parameters.

```yaml
format: ting.microapp/2
name: Format JSON
description: Pretty-print the JSON from the clipboard, with sorted keys, and put it back.
tools: [perl]

input: clipboard
# jq ships only with macOS 15 and later; JSON::PP is part of the system Perl.
command: |
  perl -MJSON::PP -0777 -ne 'my $j = JSON::PP->new->utf8->pretty->indent_length(2)->canonical->allow_nonref; print $j->encode($j->decode($_))'
output:
  to: [clipboard, panel]
  as: code
```

### Change case: `change-case.yaml`

Changes the case of the clipboard text, also of non-Latin letters. One optional choice parameter, so it opens as a list.

```yaml
format: ting.microapp/2
name: Change case
description: Change the case of the clipboard text to upper, lower or title case.
tools: [perl]

params:
  - name: mode
    type: choice
    required: false
    default: upper
    choices: [upper, lower, title]
    prompt: Case

input: clipboard
# perl -CS reads and writes UTF-8, so non-Latin letters change case too.
command: |
  case "$TING_MODE" in
    upper) perl -CS -pe '$_ = uc' ;;
    lower) perl -CS -pe '$_ = lc' ;;
    title) perl -CS -pe 's/(\w)(\w*)/\u$1\L$2/g' ;;
  esac
output:
  to: [clipboard, panel]
  as: text
```

### Encode / decode: `encode-decode.yaml`

Base64 or URL encoding of the clipboard text in both directions. One required choice parameter.

```yaml
format: ting.microapp/2
name: Encode / decode
description: Encode or decode the clipboard text as Base64 or URL encoding.
tools: [base64, perl]

params:
  - name: mode
    type: choice
    required: true
    choices: [base64-encode, base64-decode, url-encode, url-decode]
    prompt: Mode

input: clipboard
command: |
  case "$TING_MODE" in
    base64-encode) base64 ;;
    base64-decode) base64 -D ;;
    url-encode) perl -0777 -pe 'chomp; s/([^A-Za-z0-9._~-])/sprintf("%%%02X", ord $1)/ge' ;;
    url-decode) perl -0777 -pe 's/\+/ /g; s/%([0-9A-Fa-f]{2})/chr hex $1/ge' ;;
  esac
output:
  to: [clipboard, panel]
  as: text
```

### Count words: `count-text.yaml`

Counts the words, characters and lines of the clipboard text and shows them as a markdown table in the panel only; the clipboard is left alone.

```yaml
format: ting.microapp/2
name: Count words
description: Count the words, characters and lines of the clipboard text.
tools: [wc, awk]

input: clipboard
# Ting starts commands without a locale; wc counts characters, not bytes, only with UTF-8 set.
command: |
  LC_ALL=en_US.UTF-8 wc -lwm | awk '{ printf "| | |\n|---|---:|\n| Words | %d |\n| Characters | %d |\n| Lines | %d |\n", $2, $3, $1 }'
output:
  to: [panel]
```

### DNS lookup: `dns-lookup.yaml`

Looks up a domain with `dig` or `whois`. A required text parameter and two optional choices, no clipboard input, console output.

```yaml
format: ting.microapp/2
id: dns-lookup
name: DNS lookup
description: Look up DNS records of a domain with dig, or its owner with whois.
tools: [dig, whois]

params:
  - name: domain
    type: text
    required: true
    prompt: Domain
  - name: tool
    type: choice
    required: false
    default: dig
    choices: [dig, whois]
    prompt: Tool
  - name: record
    type: choice
    required: false
    default: A
    choices: [A, AAAA, MX, TXT, NS, CNAME]
    prompt: Record type (dig only)

input: none
# dig has no `--`, so a domain that starts with `-` is refused before it can become an option.
command: |
  case "$TING_DOMAIN" in
    -*) echo "Not a domain: $TING_DOMAIN" >&2; exit 2 ;;
  esac
  if [ "$TING_TOOL" = whois ]; then
    whois -- "$TING_DOMAIN"
  else
    dig +noall +answer "$TING_DOMAIN" "$TING_RECORD"
  fi
output:
  to: [panel]
  as: console
```
