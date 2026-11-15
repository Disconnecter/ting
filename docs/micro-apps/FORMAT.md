# Micro-app format (`ting.microapp/2`)

A micro-app is a small tool that Ting runs from a key: it runs **one shell
command**, can ask for a few parameters, can read the clipboard and shows or
copies the result. Each micro-app is one YAML file. Files are mostly written by
an AI assistant such as Claude Code, so the format is strict and easy to check:
every mistake is reported with the file name and the line.

The five files in [`examples/`](examples/) are complete, working micro-apps for
macOS 14 and later.

## How a micro-app runs

Ting never pastes anything into the command text:

- the command runs with `/bin/sh -c`;
- with `input: clipboard`, the clipboard text goes to the command's **stdin**;
  with `input: none`, stdin is empty;
- each parameter becomes an **environment variable**: `TING_` and the upper-case
  parameter name (`domain` → `$TING_DOMAIN`). A file cannot choose other
  variable names;
- on exit code 0, the command's **stdout** is the result and goes to `output.to`;
- on a non-zero exit code, the result panel shows an error mark, the exit code,
  stderr and stdout, and **nothing goes to the clipboard**, whatever `output.to`
  says.

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
id: dns-lookup                   # optional; must equal the file name
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
- The file name without `.yaml` is the micro-app's **id**. It is kebab-case:
  words of `a-z` and `0-9` joined by single `-` (`format-json`, `dns-lookup`).

## Keys

### Top level

| Key | Required | Value |
|---|---|---|
| `format` | yes | Exactly `ting.microapp/2`. |
| `id` | no | Kebab-case text equal to the file name without `.yaml`. If absent, the id comes from the file name. |
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

### `output`

| Key | Required | Value |
|---|---|---|
| `to` | yes | A non-empty list of `clipboard`, `panel` or both, each at most once. `clipboard` replaces the clipboard with stdout; `panel` shows stdout in the result panel. |
| `as` | no | How the panel shows stdout: `text`, `markdown`, `code` (monospaced, as a code block) or `console` (monospaced terminal output). Default `markdown`. |

## Rules of the checker

Ting checks a file before it offers the micro-app. A file with any error is not
loaded; every error is reported as `file:line: message`. The checker reports:

- YAML outside the subset below;
- an unknown key at the top level, in a parameter or in `output`;
- a missing required key;
- `format` other than `ting.microapp/2`;
- an `id` that is not kebab-case or differs from the file name; without `id`, a
  file name that is not kebab-case; a file name that does not end in `.yaml`;
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

Before the first run, and after any change to the file, Ting shows the file and
asks the person to confirm it. This is not part of the file.

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
