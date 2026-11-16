#!/usr/bin/env bash
# Trial of the agent prompt with coding agents: Scripts/agent_trial.sh claude codex pi
#
# Packages Ting once (ad-hoc signed) into a temporary folder, so the format document is inside
# the app. Then, for each named agent, it makes a fresh temporary TING_CONFIG, gives the agent
# only the text of `Ting --agent-prompt` and one fixed task, and runs the agent without a dialog.
# An agent passes when exactly one .yaml file is in its temporary micro-apps folder and
# `Ting --check` exits with 0 for it.
#
# Never touches ~/.config/ting/ or ~/Library/Application Support/Ting/, and sends no key presses.
# Prints one result line per agent; exits with 0 only when every named agent passes.
# Set AGENT_TRIAL_KEEP=1 to keep the temporary folder after a full pass.
set -euo pipefail

ROOT=$(cd "$(dirname "$0")/.." && pwd)
TASK='a micro-app that sorts the lines of the clipboard text, with a choice parameter for ascending or descending order, and shows the result'
AGENTS=(claude codex pi)

usage() {
  echo "usage: $0 <agent>... (agents: ${AGENTS[*]})" >&2
  exit 2
}

[[ $# -gt 0 ]] || usage
seen=" "
for agent in "$@"; do
  case "$agent" in
    claude|codex|pi) ;;
    *) echo "unknown agent: $agent" >&2; usage ;;
  esac
  # Each agent gets its own folder; a second run of the same agent would find the first one's file.
  [[ $seen != *" $agent "* ]] || { echo "agent named twice: $agent" >&2; usage; }
  seen+="$agent "
  command -v "$agent" >/dev/null || { echo "$agent is not installed (not in PATH)" >&2; exit 2; }
done

# A snapshot of the person's Ting folders: one line with the content hash of each file.
# launcha-history.json is left out: the person's own running Ting rewrites it whenever they
# open something through launcha, and the trial has no part in it. Config, micro-apps,
# approvals and values all stay in the snapshot.
snapshot() {
  local dir
  for dir in "$HOME/.config/ting" "$HOME/Library/Application Support/Ting"; do
    if [[ -d "$dir" ]]; then
      find "$dir" -type f ! -name launcha-history.json -exec shasum -a 256 {} + 2>/dev/null
    else
      echo "absent $dir"
    fi
  done | LC_ALL=C sort -k2
}
BEFORE=$(snapshot)

WORK=$(mktemp -d "${TMPDIR:-/tmp}/ting-agent-trial.XXXXXX")
WORK=$(cd "$WORK" && pwd -P)
echo "Trial folder: $WORK"

echo "Packaging Ting…"
if ! SIGNING_MODE=adhoc APP_OUTPUT_DIR="$WORK/app" "$ROOT/Scripts/package_app.sh" debug >"$WORK/package.log" 2>&1; then
  echo "Packaging failed; see $WORK/package.log" >&2
  exit 1
fi
APP="$WORK/app/Ting.app"
TING="$APP/Contents/MacOS/Ting"
[[ -f "$APP/Contents/Resources/FORMAT.md" ]] || { echo "FORMAT.md is missing in $APP" >&2; exit 1; }

# Runs one agent with the prompt in its empty working folder, with the rights it needs to write
# the file: claude may edit files and run shell commands in its folders without asking; codex
# writes only inside its sandbox (the working folder and the agent folder); pi has no
# permission prompts at all.
run_agent() {
  local agent="$1" dir="$2" prompt="$3"
  case "$agent" in
    claude)
      # The prompt comes right after -p: --allowedTools and --add-dir take several values.
      (cd "$dir/work" && claude -p "$prompt" --no-session-persistence \
        --permission-mode acceptEdits \
        --allowedTools 'Read,Write,Edit,Glob,Grep,Bash' \
        --add-dir "$dir" "$APP")
      ;;
    codex)
      codex exec --skip-git-repo-check --ephemeral --color never \
        --sandbox workspace-write -C "$dir/work" --add-dir "$dir" \
        "$prompt"
      ;;
    pi)
      (cd "$dir/work" && pi -p --no-session "$prompt")
      ;;
  esac
}

FAILED=0
RESULTS=()
for agent in "$@"; do
  dir="$WORK/$agent"
  mkdir -p "$dir/work"
  config="$dir/config.json"
  printf '{\n  "version": 1,\n  "items": []\n}\n' >"$config"
  config_sum=$(shasum -a 256 "$config")
  micro="$config.micro"

  echo "Running ${agent}…"
  status=0
  if ! base=$(TING_CONFIG="$config" "$TING" --agent-prompt 2>"$dir/agent-prompt.log"); then
    result="FAIL $agent: Ting --agent-prompt failed (see $dir/agent-prompt.log)"
    FAILED=1
    RESULTS+=("$result")
    echo "$result"
    continue
  fi
  prompt="$base$TASK"
  printf '%s\n' "$prompt" >"$dir/prompt.txt"
  TING_CONFIG="$config" run_agent "$agent" "$dir" "$prompt" </dev/null >"$dir/agent.log" 2>&1 || status=$?

  result=""
  shopt -s nullglob
  files=("$micro"/*.yaml)
  shopt -u nullglob
  if [[ $status -ne 0 ]]; then
    result="FAIL $agent: the agent exited with $status (log: $dir/agent.log)"
  elif [[ ${#files[@]} -ne 1 ]]; then
    result="FAIL $agent: ${#files[@]} .yaml files in $micro, expected 1 (log: $dir/agent.log)"
  elif [[ "$(shasum -a 256 "$config")" != "$config_sum" ]]; then
    result="FAIL $agent: the agent changed $config"
  elif ! "$TING" --check "${files[0]}" >"$dir/check.log" 2>&1; then
    result="FAIL $agent: the check command rejected $(basename "${files[0]}") (see $dir/check.log)"
  else
    result="PASS $agent: $(basename "${files[0]}")"
  fi
  [[ $result == PASS* ]] || FAILED=1
  RESULTS+=("$result")
  echo "$result"
done

AFTER=$(snapshot)
if [[ "$AFTER" != "$BEFORE" ]]; then
  echo "FAIL: ~/.config/ting/ or ~/Library/Application Support/Ting/ changed during the trial:" >&2
  diff <(printf '%s\n' "$BEFORE") <(printf '%s\n' "$AFTER") >&2 || true
  FAILED=1
fi

echo
printf '%s\n' "${RESULTS[@]}"
if [[ $FAILED -eq 0 && "${AGENT_TRIAL_KEEP:-0}" != 1 ]]; then
  rm -rf "$WORK"
else
  echo "Trial files kept in $WORK"
fi
exit $FAILED
