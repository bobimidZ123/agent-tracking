#!/usr/bin/env bash
# Install (or update) the morning brief on macOS as a launchd user agent: the
# systemd timer in ../install.sh, for a Mac.
#
#   scheduler/macos/install.sh
#
# Runs every day at the local hour that is 08:00 in Kyiv, computed now. Kyiv and
# the rest of the EU switch to summer time on the same dates, so the hour holds
# all year in an EU time zone; re-run this after moving to another zone.
# A Mac asleep at that hour runs it on waking; a Mac that is shut down skips it.
# Needs: node, claude and gh installed for this user;
# ~/.config/agent-tracking/telegram.env (TELEGRAM_BOT_TOKEN=…, TELEGRAM_CHAT_ID=…).
set -euo pipefail

KIT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
CONF="$HOME/.config/agent-tracking"
REPOS="${AGENT_TRACKING_REPOS:-$CONF/repos}"
LABEL=com.agent-tracking.brief
PLIST="$HOME/Library/LaunchAgents/$LABEL.plist"
LOGDIR="$HOME/Library/Logs/agent-tracking"

NODE="$(command -v node || true)"
CLAUDE="$(command -v claude || true)"
GH="$(command -v gh || true)"
[[ -n "$NODE" ]] || { echo "node not found on PATH" >&2; exit 1; }
[[ -n "$CLAUDE" ]] || { echo "claude not found on PATH" >&2; exit 1; }
[[ -n "$GH" ]] || { echo "gh not found on PATH" >&2; exit 1; }
# claude's own directory, not the versioned binary it links to, which moves on update.
RUN_PATH="$(dirname "$NODE"):$(dirname "$CLAUDE"):$(dirname "$GH"):/opt/homebrew/bin:/usr/local/bin:/usr/bin:/bin:/usr/sbin:/sbin"

# The local hour at which it is 08:00 in Kyiv today.
offset_min() { local z; z=$(TZ="$1" date +%z); echo $(( (10#${z:1:2} * 60 + 10#${z:3:2}) * (${z:0:1}1) )); }
diff=$(( $(offset_min Europe/Kyiv) - $(offset_min "$(readlink /etc/localtime | sed 's#.*/zoneinfo/##')") ))
(( diff % 60 == 0 )) || { echo "local time zone is not a whole number of hours from Kyiv" >&2; exit 1; }
HOUR=$(( ((8 * 60 - diff) / 60 % 24 + 24) % 24 ))

mkdir -p "$(dirname "$PLIST")" "$LOGDIR" "$(dirname "$REPOS")"
chmod +x "$KIT/scheduler/macos/run-brief.sh" "$KIT/scheduler/notify-failure.sh"
sed -e "s#%KIT%#$KIT#g" -e "s#%PATH%#$RUN_PATH#g" -e "s#%HOME%#$HOME#g" -e "s#%HOUR%#$HOUR#g" -e "s#%LOGDIR%#$LOGDIR#g" \
  "$KIT/scheduler/macos/$LABEL.plist" >"$PLIST"
plutil -lint "$PLIST" >/dev/null

if [[ ! -e "$REPOS" ]]; then
  printf '# Repos the morning brief covers: owner/name [checkout] [title], one per line.\n' >"$REPOS"
  echo "created $REPOS — add owner/name lines to it"
fi
[[ -r "$CONF/telegram.env" ]] || echo "warning: no $CONF/telegram.env, so the brief cannot be sent and a failure sends no alert"

launchctl bootout "gui/$(id -u)/$LABEL" 2>/dev/null || true
launchctl bootstrap "gui/$(id -u)" "$PLIST"
echo "installed $PLIST: every day at $(printf '%02d' "$HOUR"):00 local (08:00 Kyiv)"
echo "Test it the way launchd runs it (this runs the agents and sends the brief):"
echo "  launchctl kickstart gui/$(id -u)/$LABEL; sleep 5; tail -f $LOGDIR/brief.log"
