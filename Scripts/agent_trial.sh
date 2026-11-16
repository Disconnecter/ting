#!/usr/bin/env bash
# Trial of the agent prompt with coding agents: Scripts/agent_trial.sh claude codex pi
#
# Packages Ting once (ad-hoc signed) into a temporary folder, so the format document is inside
# the app. Then, for each named agent, it makes a fresh temporary TING_CONFIG, gives the agent
# only the text of `Ting --agent-prompt` and one fixed task, and runs the agent without a dialog.
# An agent passes when exactly one .yaml file (hidden ones included) is in its temporary
# micro-apps folder and `Ting --check` exits with 0 for it.
#
# Never touches ~/.config/ting/ or ~/Library/Application Support/Ting/, and sends no key presses.
# It hashes every file in both folders before and after the run and checks that none changed.
#
# Prints one result line per agent. Exit codes: 0 when every named agent passes and the
# folders are unchanged; 1 when an agent fails or a file in the folders changed; 2 for a wrong
# call; 3 (inconclusive) when the agents pass but launcha-history.json changed, which the
# person's own running Ting does when they open something through launcha: run it again.
# Set AGENT_TRIAL_KEEP=1 to keep the temporary folder after a full pass.
# AGENT_TRIAL_WATCH (folders separated by ':') replaces the two folders, for tests of the script.
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

WATCH=${AGENT_TRIAL_WATCH:-"$HOME/.config/ting:$HOME/Library/Application Support/Ting"}
IFS=: read -r -a WATCH_DIRS <<<"$WATCH"

# A snapshot of the person's Ting folders: one line with the content hash of each file.
snapshot() {
  local dir
  for dir in "${WATCH_DIRS[@]}"; do
    if [[ -d "$dir" ]]; then
      find "$dir" -type f -exec shasum -a 256 {} + 2>/dev/null
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
    echo "FAIL $agent: Ting --agent-prompt failed (see $dir/agent-prompt.log)"
    FAILED=1
    continue
  fi
  prompt="$base$TASK"
  printf '%s\n' "$prompt" >"$dir/prompt.txt"
  TING_CONFIG="$config" run_agent "$agent" "$dir" "$prompt" </dev/null >"$dir/agent.log" 2>&1 || status=$?

  result=""
  # dotglob: a hidden draft such as .draft.yaml counts as a second file.
  shopt -s nullglob dotglob
  files=("$micro"/*.yaml)
  shopt -u nullglob dotglob
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
  echo "$result"
done

AFTER=$(snapshot)
if [[ "$AFTER" != "$BEFORE" ]]; then
  changes=$(diff <(printf '%s\n' "$BEFORE") <(printf '%s\n' "$AFTER") | grep '^[<>]' || true)
  echo "The watched folders changed during the trial:" >&2
  printf '%s\n' "$changes" >&2
  # Every changed line names launcha-history.json: the person's own Ting, not the trial, most
  # likely wrote it, but the trial cannot prove that the folders stayed unchanged.
  if [[ $FAILED -eq 0 ]] && ! grep -qv '/launcha-history\.json$' <<<"$changes"; then
    echo "INCONCLUSIVE: only launcha-history.json changed, probably by the running Ting; run the trial again" >&2
    FAILED=3
  else
    echo "FAIL: a file in the watched folders changed" >&2
    FAILED=1
  fi
fi

if [[ $FAILED -eq 0 && "${AGENT_TRIAL_KEEP:-0}" != 1 ]]; then
  rm -rf "$WORK"
else
  echo "Trial files kept in $WORK"
fi
exit $FAILED
