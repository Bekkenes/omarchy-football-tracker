#!/usr/bin/env bash
# Interactive setup wizard for the football-tracker Omarchy plugin.
# Re-runnable any time to change your API key or favorite teams.

set -uo pipefail
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PLUGIN_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"
# shellcheck source=lib.sh
source "$SCRIPT_DIR/lib.sh"

bold() { printf '\033[1m%s\033[0m\n' "$*"; }

echo
bold "== Football Tracker setup =="
echo "This plugin needs a free API-Football key to fetch fixtures and live"
echo "match events (goals, cards, substitutions)."
echo
echo "  1. Go to: https://dashboard.api-football.com/register"
echo "  2. Sign up (free) and confirm your email."
echo "  3. On your dashboard, copy the 'API-KEY' value shown at the top."
echo "  4. The free plan gives you 100 requests/day — this plugin is"
echo "     designed to comfortably stay within that."
echo

existing_key="$(ft_api_key)"
if [[ -n "$existing_key" ]]; then
  read -rp "An API key is already configured. Replace it? [y/N] " replace
  if [[ ! "$replace" =~ ^[Yy]$ ]]; then
    api_key="$existing_key"
  fi
fi

if [[ -z "${api_key:-}" ]]; then
  while true; do
    read -rp "Paste your API-Football key: " api_key
    if [[ -z "$api_key" ]]; then
      echo "Key cannot be empty."
      continue
    fi
    echo "Validating..."
    status_resp="$(curl -fsS --max-time 15 -H "x-apisports-key: $api_key" "$API_BASE/status" 2>/dev/null)"
    if [[ -z "$status_resp" ]]; then
      echo "Couldn't reach the API. Check your internet connection and try again."
      continue
    fi
    remaining="$(jq -r '.response.requests.limit_day - .response.requests.current // empty' <<<"$status_resp" 2>/dev/null)"
    if [[ -z "$remaining" ]]; then
      echo "That key didn't validate. Double-check you copied it correctly."
      continue
    fi
    echo "Key looks good — $remaining requests left today."
    break
  done
fi

umask 077
printf '%s' "$api_key" > "$API_KEY_FILE"
chmod 600 "$API_KEY_FILE"

# --- team selection ---
existing_teams="$(jq -c '.teams // []' <<<"$(ft_read_config)" 2>/dev/null || echo '[]')"
teams="$existing_teams"

echo
bold "== Favorite teams =="
if [[ "$(jq 'length' <<<"$teams")" -gt 0 ]]; then
  echo "Currently tracking:"
  jq -r '.[] | "  - " + .name' <<<"$teams"
  echo
fi

while true; do
  echo "Add a team:"
  echo "  1) Premier League (England)"
  echo "  2) Eliteserien / Tippeligaen (Norway)"
  echo "  3) Search any team/country"
  echo "  Enter) Done adding teams"
  read -rp "> " choice
  case "$choice" in
    "" ) break ;;
    1) country="England" ;;
    2) country="Norway" ;;
    3) country="" ;;
    *) echo "Not a valid option."; continue ;;
  esac

  read -rp "Team name to search: " term
  [[ -z "$term" ]] && continue

  # API-Football rejects combining `search` with `country` in one request
  # ("The Country field cannot be used with the Search field"), so search by
  # name only and filter to the chosen country client-side — falling back to
  # the unfiltered results if that filter would hide a real match (e.g. the
  # team's recorded country spelling differs from ours).
  resp="$(ft_api "teams?search=$(jq -rn --arg s "$term" '$s|@uri')")"
  count="$(jq '.response | length' <<<"$resp" 2>/dev/null || echo 0)"

  if [[ "$count" -eq 0 ]]; then
    echo "No teams found for '$term'. Try again."
    continue
  fi

  if [[ -n "$country" ]]; then
    filtered="$(jq --arg c "$country" '{response: [.response[] | select(.team.country == $c)]}' <<<"$resp")"
    filtered_count="$(jq '.response | length' <<<"$filtered")"
    [[ "$filtered_count" -gt 0 ]] && resp="$filtered"
  fi

  echo "Results:"
  jq -r '.response | to_entries[] | "  \(.key+1)) \(.value.team.name) (\(.value.team.country))"' <<<"$resp"
  read -rp "Pick a number (or Enter to skip): " pick
  [[ -z "$pick" ]] && continue

  picked="$(jq -c --argjson i "$((pick-1))" '.response[$i].team // empty' <<<"$resp")"
  if [[ -z "$picked" || "$picked" == "null" ]]; then
    echo "Invalid pick."
    continue
  fi

  pid="$(jq -r '.id' <<<"$picked")"
  pname="$(jq -r '.name' <<<"$picked")"
  already="$(jq --argjson id "$pid" 'any(.[]; .id == $id)' <<<"$teams")"
  if [[ "$already" == "true" ]]; then
    echo "$pname is already in your list."
    continue
  fi
  teams="$(jq -c --argjson t "$picked" '. + [{id:$t.id, name:$t.name, country:$t.country}]' <<<"$teams")"
  echo "Added $pname."
done

echo
read -rp "Live-poll interval in seconds during a match (default 180, min 60): " interval
interval="${interval:-180}"
[[ "$interval" -lt 60 ]] 2>/dev/null && interval=60

ft_write_config "$teams" "$interval"

echo
bold "== Finishing up =="
omarchy pkg add jq curl >/dev/null 2>&1 || true

SYSTEMD_DIR="$HOME/.config/systemd/user"
mkdir -p "$SYSTEMD_DIR"
cat > "$SYSTEMD_DIR/omarchy-football-tracker.service" <<EOF
[Unit]
Description=Football Tracker plugin poll (Omarchy)

[Service]
Type=oneshot
ExecStart=$PLUGIN_DIR/bin/poll.sh
EOF

cat > "$SYSTEMD_DIR/omarchy-football-tracker.timer" <<'EOF'
[Unit]
Description=Run Football Tracker poll periodically

[Timer]
OnBootSec=30
OnUnitActiveSec=60
AccuracySec=10

[Install]
WantedBy=timers.target
EOF

systemctl --user daemon-reload
systemctl --user enable --now omarchy-football-tracker.timer

if command -v omarchy-shell >/dev/null 2>&1; then
  omarchy-shell shell rescanPlugins >/dev/null 2>&1 || true
fi
omarchy plugin enable football-tracker >/dev/null 2>&1 || true

echo
bold "Done! Tracking $(jq 'length' <<<"$teams") team(s)."
echo "The bar widget will pick up your next fixture within a minute."
echo "Test icons/notifications right now with:"
echo "  $SCRIPT_DIR/poll.sh --simulate"
echo "Re-run this setup anytime to change your key or teams:"
echo "  $SCRIPT_DIR/setup.sh"
