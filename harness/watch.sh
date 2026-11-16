#!/usr/bin/env bash
# Follow an unattended run in readable form.
#
#   bash harness/watch.sh            follow the latest run until it finishes (Ctrl-C to leave)
#   bash harness/watch.sh --once     print its status and timeline so far, then exit
#   bash harness/watch.sh [--once] .harness/logs/run-<branch>.jsonl
#
# Reads the stream-json log written by run-unattended.sh. Shows task progress and
# commits in the run's worktree, then one line per step: what the agent said (say),
# commands it ran (run), files it edited (edit), subagents (sub), failed tool calls
# (fail), and the final result with turns and cost (DONE). Watching never affects the run.
set -u

HERE="$(cd "$(dirname "$0")" && pwd)"
# shellcheck source=harness/lib.sh
. "$HERE/lib.sh"
require_cmd jq "Install jq." || exit 1

FOLLOW=1
LOG=""
while [ $# -gt 0 ]; do
  case "$1" in
    --once) FOLLOW=0; shift ;;
    -h|--help) sed -n '2,11p' "$0"; exit 0 ;;
    *) LOG="$1"; shift ;;
  esac
done

ROOT="$(git rev-parse --show-toplevel 2>/dev/null || pwd)"
STATE="$ROOT/.harness"
if [ -z "$LOG" ]; then
  # shellcheck disable=SC2012  # names are ours: run-<branch>.jsonl
  LOG="$(ls -t "$STATE"/logs/run-*.jsonl 2>/dev/null | head -1)"
fi
[ -n "$LOG" ] && [ -f "$LOG" ] || { echo "watch: no run log under $STATE/logs (start one with run-unattended.sh)" >&2; exit 1; }

name="$(basename "$LOG" .jsonl)"
WT="$STATE/worktrees/${name#run-}"

status() {
  echo "log:      ${LOG#"$ROOT"/}"
  if [ -d "$WT" ]; then
    local branch tasks
    branch="$(git -C "$WT" rev-parse --abbrev-ref HEAD 2>/dev/null)"
    echo "worktree: ${WT#"$ROOT"/} ($branch)"
    if [ -f "$WT/spec/tasks.json" ]; then
      tasks="$(jq -r '"\([.tasks[] | select(.passes)] | length)/\(.tasks | length) passing" + ([.tasks[] | select(.passes | not) | .id] | if length > 0 then "  open: " + join(" ") else "" end)' "$WT/spec/tasks.json" 2>/dev/null)"
      echo "tasks:    $tasks"
    fi
    echo "commits:"
    git -C "$WT" log --oneline "$(base_branch)..HEAD" 2>/dev/null | sed 's/^/  /'
  fi
  echo "-----"
}

# One readable line per interesting event; everything else (thinking, token counts) is dropped.
FMT='
def line: tostring | gsub("\\s+"; " ") | .[0:160];
fromjson? |
if .type == "assistant" then
  .message.content[]? |
  if .type == "text" then "say  " + (.text | line)
  elif .type == "tool_use" then
    if .name == "Bash" then "run  " + ((.input.description // .input.command) | line)
    elif (.name | test("^(Edit|Write|MultiEdit|NotebookEdit)$")) then "edit " + (.input.file_path // .input.notebook_path // "")
    elif .name == "Agent" or .name == "Task" then "sub  " + (.input.subagent_type // "agent") + ": " + ((.input.description // "") | line)
    else "tool " + .name end
  else empty end
elif .type == "user" then
  .message.content[]? | select(type == "object" and .type == "tool_result" and .is_error == true)
  | "fail " + (.content | line)
elif .type == "result" then
  "DONE " + (.subtype // "") + "  turns " + (.num_turns | tostring)
  + "  cost $" + (((.total_cost_usd // 0) * 100 | round) / 100 | tostring)
  + "  " + ((.duration_ms // 0) / 60000 | floor | tostring) + " min"
else empty end'

finish() {
  echo "-----"
  status
  if [ -f "$STATE/launch.log" ]; then
    echo "launch.log (last lines):"
    tail -n 5 "$STATE/launch.log" | sed 's/^/  /'
  fi
}

status
seen=0
idle=0
while :; do
  total="$(wc -l <"$LOG" | tr -d ' ')"
  if [ "$total" -gt "$seen" ]; then
    sed -n "$((seen + 1)),${total}p" "$LOG" | jq -Rr "$FMT"
    seen="$total"
    idle=0
  fi
  if grep -q '"type":"result"' "$LOG"; then  # unescaped only at the top level
    [ "$FOLLOW" -eq 1 ] && sleep 3  # give run-unattended.sh a moment for the final gate
    finish
    exit 0
  fi
  [ "$FOLLOW" -eq 1 ] || exit 0
  sleep 2
  idle=$((idle + 2))
  if [ $((idle % 600)) -eq 0 ]; then
    echo "(no new events for $((idle / 60)) min; the agent may be in a long command, or the run stopped: see .harness/launch.log)"
  fi
done
