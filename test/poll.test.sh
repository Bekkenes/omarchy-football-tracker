#!/usr/bin/env bash
# Runs bin/poll.sh in a sandbox with stub `curl` and `omarchy` commands, and
# checks the two things that broke in the field: a poll must not spend the API
# quota when the fixture cache is fresh, and a failed state write must not wipe
# _bookkeeping (which is what made the "play today" notification repeat).
#
# Time-dependent parts are skipped rather than failed when the clock makes them
# impossible to exercise (see the day-notification block below).
set -uo pipefail

cd "$(dirname "${BASH_SOURCE[0]}")"
REPO="$(cd .. && pwd)"

pass=0
fail=0
chk() { # chk <description> <expected> <actual>
  if [[ "$2" == "$3" ]]; then
    pass=$((pass + 1)); printf 'PASS  %s\n' "$1"
  else
    fail=$((fail + 1)); printf 'FAIL  %s\n        expected: %s\n        actual:   %s\n' "$1" "$2" "$3"
  fi
}

sandbox="$(mktemp -d)"
trap 'rm -rf "$sandbox"' EXIT
export HOME="$sandbox/home"
mkdir -p "$HOME/.config/omarchy-football-tracker" "$HOME/.local/state/omarchy-football-tracker" "$sandbox/shim"
state="$HOME/.local/state/omarchy-football-tracker/state.json"
cache="$HOME/.local/state/omarchy-football-tracker/fixtures_cache.json"
fixture_id=1494774

# Any API call is recorded and fails: the suite must never reach the real
# API-Football plan. Notifications are recorded instead of shown.
cat > "$sandbox/shim/curl" <<'SH'
#!/usr/bin/env bash
printf 'curl %s\n' "$*" >> "$CURL_LOG"
exit 22
SH
cat > "$sandbox/shim/omarchy" <<'SH'
#!/usr/bin/env bash
printf 'omarchy %s\n' "$*" >> "$NOTIFY_LOG"
exit 0
SH
chmod +x "$sandbox/shim/curl" "$sandbox/shim/omarchy"

printf 'SANDBOXKEY' > "$HOME/.config/omarchy-football-tracker/api_key"
chmod 600 "$HOME/.config/omarchy-football-tracker/api_key"
printf '%s' '{"teams":[{"id":319,"name":"Brann","country":"Norway"}],"poll_interval_live_seconds":180,"has_api_key":true}' \
  > "$HOME/.config/omarchy-football-tracker/config.json"

write_cache() { # write_cache <iso-kickoff>
  jq -n --arg fetched "$(date -u +%Y-%m-%d)" --arg ko "$1" --argjson fid "$fixture_id" \
    '{fetched_date:$fetched, fixtures:[{team:"Brann",team_id:319,fixture_id:$fid,kickoff:$ko,home:true,opponent:"Viking",competition:"Eliteserien"}]}' \
    > "$cache"
}
run_poll() {
  PATH="$sandbox/shim:$PATH" CURL_LOG="$sandbox/curl.log" NOTIFY_LOG="$sandbox/notify.log" \
    bash "$REPO/bin/poll.sh" 2>&1
}
count() { [[ -f "$1" ]] && grep -c . "$1" || echo 0; }

echo "-- a fresh cache means no API traffic"
# Tomorrow noon: never inside the live window and never "today", so the run is
# clock-independent.
write_cache "$(date -u -d '+1 day 12:00' +%Y-%m-%dT%H:%M:%SZ)"
printf '%s' '{"_bookkeeping":{"1494774":{"day":true}}}' > "$state"
run_poll >/dev/null 2>&1
chk "poll exits 0" "0" "$?"
chk "state is still a JSON object" "object" "$(jq -r 'type' "$state")"
chk "next match comes from the cache" "Brann" "$(jq -r '.next_match.team' "$state")"
chk "existing bookkeeping survives the poll" "true" "$(jq -r '._bookkeeping["1494774"].day' "$state")"
chk "no API call was made" "0" "$(count "$sandbox/curl.log")"

echo "-- a failed state write cannot wipe the file"
# The shape the incident left behind: an upstream jq failure that hands
# ft_write_state an empty string.
( source "$REPO/bin/lib.sh"
  ft_write_state "$(jq -n --argjson bad 'not json' '{}' 2>/dev/null)" ) >/dev/null 2>&1 || true
chk "state still parses after the failed write" "object" "$(jq -r 'type' "$state")"
chk "bookkeeping still present after the failed write" "true" "$(jq -r '._bookkeeping["1494774"].day' "$state")"
run_poll >/dev/null 2>&1
chk "the next poll still has the flag" "true" "$(jq -r '._bookkeeping["1494774"].day' "$state")"

echo "-- day notification fires once, then stays quiet"
kickoff="$(date -u -d '+30 minutes' +%Y-%m-%dT%H:%M:%SZ)"
if [[ "$(date -u -d "$kickoff" +%Y-%m-%d)" == "$(date -u +%Y-%m-%d)" ]]; then
  write_cache "$kickoff"
  rm -f "$state" "$sandbox/notify.log"
  run_poll >/dev/null 2>&1
  chk "first poll notifies once" "1" "$(count "$sandbox/notify.log")"
  run_poll >/dev/null 2>&1
  chk "second poll does not repeat" "1" "$(count "$sandbox/notify.log")"
  ( source "$REPO/bin/lib.sh"
    ft_write_state "" ) >/dev/null 2>&1 || true
  run_poll >/dev/null 2>&1
  chk "still does not repeat after a failed write" "1" "$(count "$sandbox/notify.log")"
else
  echo "SKIP  too late in the UTC day for a fixture that has not kicked off yet"
fi

printf '\n%s: %d passed, %d failed\n' "$(basename "$0")" "$pass" "$fail"
[[ "$fail" -eq 0 ]]
