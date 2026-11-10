#!/usr/bin/env bash
# Install (or update) the daily brief on macOS as a launchd user agent: the
# systemd timer in ../install.sh, for a Mac.
#
#   scheduler/macos/install.sh                          # 08:00 Kyiv, as on the devbox
#   BRIEF_TZ=Europe/Moscow BRIEF_HOUR=17 scheduler/macos/install.sh
#
# The time is kept in BRIEF_TZ itself, not converted to local time, so it holds
# when the local zone and BRIEF_TZ switch to summer time on different dates (or
# one of them never does). See run-brief.sh for how a day's single run is chosen.
# Needs: node, claude and gh installed for this user;
# ~/.config/agent-tracking/telegram.env (TELEGRAM_BOT_TOKEN=…, TELEGRAM_CHAT_ID=…).
set -euo pipefail

KIT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
CONF="$HOME/.config/agent-tracking"
REPOS="${AGENT_TRACKING_REPOS:-$CONF/repos}"
LABEL=com.agent-tracking.brief
PLIST="$HOME/Library/LaunchAgents/$LABEL.plist"
LOGDIR="$HOME/Library/Logs/agent-tracking"
BRIEF_TZ="${BRIEF_TZ:-Europe/Kyiv}"
BRIEF_HOUR="${BRIEF_HOUR:-8}"

[[ -e "/usr/share/zoneinfo/$BRIEF_TZ" ]] || { echo "unknown time zone: $BRIEF_TZ" >&2; exit 1; }
[[ "$BRIEF_HOUR" =~ ^([0-9]|1[0-9]|2[0-3])$ ]] || { echo "BRIEF_HOUR must be 0–23" >&2; exit 1; }
NODE="$(command -v node || true)"
CLAUDE="$(command -v claude || true)"
GH="$(command -v gh || true)"
[[ -n "$NODE" ]] || { echo "node not found on PATH" >&2; exit 1; }
[[ -n "$CLAUDE" ]] || { echo "claude not found on PATH" >&2; exit 1; }
[[ -n "$GH" ]] || { echo "gh not found on PATH" >&2; exit 1; }
# claude's own directory, not the versioned binary it links to, which moves on update.
RUN_PATH="$(dirname "$NODE"):$(dirname "$CLAUDE"):$(dirname "$GH"):/opt/homebrew/bin:/usr/local/bin:/usr/bin:/bin:/usr/sbin:/sbin"

mkdir -p "$(dirname "$PLIST")" "$LOGDIR" "$(dirname "$REPOS")"
chmod +x "$KIT/scheduler/macos/run-brief.sh" "$KIT/scheduler/notify-failure.sh"
sed -e "s#%KIT%#$KIT#g" -e "s#%PATH%#$RUN_PATH#g" -e "s#%HOME%#$HOME#g" -e "s#%LOGDIR%#$LOGDIR#g" \
    -e "s#%BRIEF_TZ%#$BRIEF_TZ#g" -e "s#%BRIEF_HOUR%#$BRIEF_HOUR#g" \
  "$KIT/scheduler/macos/$LABEL.plist" >"$PLIST"
plutil -lint "$PLIST" >/dev/null

if [[ ! -e "$REPOS" ]]; then
  printf '# Repos the brief covers: owner/name [checkout] [title], one per line.\n' >"$REPOS"
  echo "created $REPOS — add owner/name lines to it"
fi
[[ -r "$CONF/telegram.env" ]] || echo "warning: no $CONF/telegram.env, so the brief cannot be sent and a failure sends no alert"

launchctl bootout "gui/$(id -u)/$LABEL" 2>/dev/null || true
launchctl bootstrap "gui/$(id -u)" "$PLIST"
echo "installed $PLIST: once a day from $(printf '%02d' "$BRIEF_HOUR"):00 $BRIEF_TZ (now $(TZ="$BRIEF_TZ" date '+%H:%M') there)"
echo "Test it the way launchd runs it (this runs the agents and sends the brief):"
echo "  $KIT/scheduler/macos/run-brief.sh --now; tail -30 $LOGDIR/brief.log"
