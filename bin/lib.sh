#!/usr/bin/env bash
# Shared helpers for the football-tracker plugin backend scripts.
# Sourced by poll.sh and setup.sh — not meant to be run directly.

set -uo pipefail

PLUGIN_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
ICON_DIR="$PLUGIN_DIR/icons"

CONFIG_DIR="$HOME/.config/omarchy-football-tracker"
STATE_DIR="$HOME/.local/state/omarchy-football-tracker"
CONFIG_FILE="$CONFIG_DIR/config.json"
API_KEY_FILE="$CONFIG_DIR/api_key"
STATE_FILE="$STATE_DIR/state.json"
FIXTURES_CACHE="$STATE_DIR/fixtures_cache.json"

API_BASE="https://v3.football.api-sports.io"

mkdir -p "$CONFIG_DIR" "$STATE_DIR"

ft_log() {
  echo "[football-tracker] $*" >&2
}

ft_api_key() {
  if [[ -f "$API_KEY_FILE" ]]; then
    cat "$API_KEY_FILE"
  fi
}

# ft_curl_config <api-key>
# Writes a curl config carrying the API key header to stdout; callers pipe it
# into `curl -K -`. Passing the key as `-H "x-apisports-key: <key>"` would put
# it in curl's command line, which every local user can read through
# /proc/<pid>/cmdline on default procfs mounts — the mode-600 key file does not
# cover that copy.
ft_curl_config() {
  local escaped="${1//\\/\\\\}"
  escaped="${escaped//\"/\\\"}"
  printf 'header = "x-apisports-key: %s"\n' "$escaped"
}

# ft_api <path-with-query>  e.g. ft_api "fixtures?live=all"
ft_api() {
  local path="$1"
  local key
  key="$(ft_api_key)"
  if [[ -z "$key" ]]; then
    ft_log "no API key configured (run setup.sh)"
    return 1
  fi
  local attempt body code
  for attempt in 1 2 3; do
    body="$(ft_curl_config "$key" | curl -sS --max-time 15 -w '\n%{http_code}' \
      -K - \
      "$API_BASE/$path")"
    code="${body##*$'\n'}"
    body="${body%$'\n'*}"
    if [[ "$code" == "429" ]]; then
      ft_log "rate limited (attempt $attempt), backing off"
      sleep $((attempt * 8))
      continue
    fi
    printf '%s' "$body"
    return 0
  done
  ft_log "gave up after repeated rate limiting: $path"
  return 1
}

# ft_notify <headline> <body> <icon-file> [urgency] [glyph]
ft_notify() {
  local headline="$1" body="$2" icon_file="$3" urgency="${4:-normal}"
  local icon_path="$ICON_DIR/$icon_file"
  omarchy notification send \
    --app-name "Football Tracker" \
    -u "$urgency" \
    -i "$icon_path" \
    "$headline" "$body"
}

# ft_icon_for_event <event-type> <detail>
# event-type: Goal | Card | subst | Var
ft_icon_for_event() {
  local type="$1" detail="${2:-}"
  case "$type" in
    Goal)
      case "$detail" in
        *Own*) echo "own-goal.svg" ;;
        *Missed*) echo "penalty-miss.svg" ;;
        *) echo "goal.svg" ;;
      esac
      ;;
    Card)
      case "$detail" in
        *Red*) echo "card-red.svg" ;;
        *) echo "card-yellow.svg" ;;
      esac
      ;;
    subst) echo "substitution.svg" ;;
    *) echo "whistle.svg" ;;
  esac
}

ft_read_config() {
  if [[ -f "$CONFIG_FILE" ]]; then
    cat "$CONFIG_FILE"
  else
    echo '{"poll_interval_live_seconds":180,"teams":[],"has_api_key":false}'
  fi
}

# ft_write_config <teams-json-array> <poll-interval-seconds>
ft_write_config() {
  local teams="$1" interval="$2" has_key="false"
  [[ -s "$API_KEY_FILE" ]] && has_key="true"
  jq -n --argjson teams "$teams" --argjson interval "$interval" --argjson has_api_key "$has_key" \
    '{teams:$teams, poll_interval_live_seconds:$interval, has_api_key:$has_api_key}' > "$CONFIG_FILE"
}

ft_write_state() {
  # ft_write_state <json>
  # A failed upstream `jq` call leaves this empty (`jq: invalid JSON text passed
  # to --argjson` then no output), and writing that over state.json also drops
  # `_bookkeeping` — which is what stops the "play today" notification from
  # re-firing on every later poll, arguably forever. Keep the last good file and
  # say so instead; the caller's own state stays in memory regardless.
  # `jq empty` is not enough on its own: it treats a blank string as valid.
  if [[ -z "${1//[[:space:]]/}" ]] || ! jq -e 'type == "object"' >/dev/null 2>&1 <<<"$1"; then
    ft_log "ft_write_state: refusing to write empty/invalid state, keeping the previous state.json"
    return 1
  fi
  local tmp="$STATE_FILE.tmp.$$"
  echo "$1" > "$tmp" && mv "$tmp" "$STATE_FILE"
}
