#!/usr/bin/env bash
# What launchd runs every hour. Sends the brief once a day, at the first run at
# or after BRIEF_HOUR:00 in BRIEF_TZ; every other run exits at once. Output goes
# to a log, and a failure sends a Telegram alert with the last lines (the macOS
# stand-in for systemd's OnFailure=). A failed day is not retried by the next
# hourly run, so a broken setup alerts once, not every hour.
#
#   run-brief.sh            # what launchd runs
#   run-brief.sh --now      # send now, whatever the time (marks today as done)
set -uo pipefail
KIT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
BRIEF_TZ="${BRIEF_TZ:-Europe/Kyiv}"
BRIEF_HOUR="${BRIEF_HOUR:-8}"
export DIGEST_TZ="${DIGEST_TZ:-$BRIEF_TZ}"
LOGDIR="$HOME/Library/Logs/agent-tracking"
LOG="$LOGDIR/brief.log"
STAMP="${AGENT_TRACKING_STATE:-$HOME/.local/state/agent-tracking/brief}/launchd-last-day"
mkdir -p "$LOGDIR" "$(dirname "$STAMP")"

today=$(TZ="$BRIEF_TZ" date +%F)
hour=$(TZ="$BRIEF_TZ" date +%H)
if [[ "${1:-}" != --now ]]; then
  (( 10#$hour >= BRIEF_HOUR )) || exit 0
  [[ "$(cat "$STAMP" 2>/dev/null)" != "$today" ]] || exit 0
fi
echo "$today" >"$STAMP"

echo "=== $(TZ="$BRIEF_TZ" date '+%F %H:%M %Z') brief start" >>"$LOG"
run_log="$(mktemp)"
node "$KIT/brief/brief.mjs" --send >"$run_log" 2>&1
code=$?
cat "$run_log" >>"$LOG"
echo "=== exit $code" >>"$LOG"
if [[ $code -ne 0 ]]; then
  AGENT_TRACKING_FAILURE_LOG="$run_log" \
  AGENT_TRACKING_FAILURE_HINT="Check: tail -50 $LOG
Retry: $KIT/scheduler/macos/run-brief.sh --now" \
    "$KIT/scheduler/notify-failure.sh" >>"$LOG" 2>&1
fi
rm -f "$run_log"
exit $code
