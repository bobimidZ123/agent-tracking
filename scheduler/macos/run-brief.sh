#!/usr/bin/env bash
# What launchd runs at 08:00 Kyiv: the brief with --send, its output in a log,
# and a Telegram alert with the last lines if it fails (the macOS stand-in for
# systemd's OnFailure=).
set -uo pipefail
KIT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
LOGDIR="$HOME/Library/Logs/agent-tracking"
LOG="$LOGDIR/brief.log"
mkdir -p "$LOGDIR"

{ echo "=== $(date '+%Y-%m-%d %H:%M:%S %Z') brief start"; } >>"$LOG"
run_log="$(mktemp)"
node "$KIT/brief/brief.mjs" --send >"$run_log" 2>&1
code=$?
cat "$run_log" >>"$LOG"
echo "=== exit $code" >>"$LOG"
if [[ $code -ne 0 ]]; then
  AGENT_TRACKING_FAILURE_LOG="$run_log" \
  AGENT_TRACKING_FAILURE_HINT="Check: tail -50 $LOG
Retry: launchctl kickstart gui/$(id -u)/com.agent-tracking.brief" \
    "$KIT/scheduler/notify-failure.sh" >>"$LOG" 2>&1
fi
rm -f "$run_log"
exit $code
