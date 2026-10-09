#!/usr/bin/env bash
# Tests for bin/lib.sh: state-write validation, credential handling, the
# config round trip and the event icon mapping.
#
# Everything runs against a throwaway $HOME, so the suite never reads or writes
# the real plugin config or state.
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
mkdir -p "$sandbox/home" "$sandbox/shim"

# lib.sh derives every path from $HOME, so point it at the sandbox first.
export HOME="$sandbox/home"
# shellcheck source=../bin/lib.sh
source "$REPO/bin/lib.sh"

echo "-- ft_write_state: a failed upstream jq must not clobber the state"
ft_write_state '{"_bookkeeping":{"1494774":{"day":true}}}' 2>/dev/null
chk "writes a valid object" '{"_bookkeeping":{"1494774":{"day":true}}}' "$(cat "$STATE_FILE")"
good="$(cat "$STATE_FILE")"
for bad in "" "   " "garbage" "null" "1 2" "[1,2]"; do
  ft_write_state "$bad" >/dev/null 2>&1 && rc=0 || rc=$?
  chk "rejects [$bad]" "1" "$rc"
  chk "keeps the previous state for [$bad]" "$good" "$(cat "$STATE_FILE")"
done
ft_write_state "" 2>"$sandbox/guard.log"
chk "logs the refusal" "1" "$(grep -c 'refusing to write' "$sandbox/guard.log")"

echo "-- credentials never reach a command line"
chk "curl config escapes quotes and backslashes" \
  'header = "x-apisports-key: KEY\"with\\quotes"' \
  "$(ft_curl_config 'KEY"with\quotes')"
cat > "$sandbox/shim/curl" <<'SH'
#!/usr/bin/env bash
printf '%s\n' "$*" >> "$CURL_ARGV_LOG"
exit 22
SH
chmod +x "$sandbox/shim/curl"
printf 'SANDBOXKEY' > "$API_KEY_FILE"
chmod 600 "$API_KEY_FILE"
PATH="$sandbox/shim:$PATH" CURL_ARGV_LOG="$sandbox/argv.log" \
  bash -c "source '$REPO/bin/lib.sh'; ft_api status" >/dev/null 2>&1
chk "curl gets its config on stdin" "1" "$(grep -c -- '-K -' "$sandbox/argv.log")"
chk "curl argv carries no credential" "0" "$(grep -c 'SANDBOXKEY' "$sandbox/argv.log")"

echo "-- save-settings.sh reads the key from stdin"
printf 'STDINKEY\n' | bash "$REPO/bin/save-settings.sh" --api-key-stdin >/dev/null 2>&1
chk "key written from stdin" "STDINKEY" "$(cat "$API_KEY_FILE")"
chk "key file is mode 600" "600" "$(stat -c '%a' "$API_KEY_FILE")"
printf '\n' | bash "$REPO/bin/save-settings.sh" --api-key-stdin >/dev/null 2>&1
chk "an empty line keeps the stored key" "STDINKEY" "$(cat "$API_KEY_FILE")"
bash "$REPO/bin/save-settings.sh" --api-key ARGVKEY >/dev/null 2>&1
chk "the removed --api-key flag writes nothing" "STDINKEY" "$(cat "$API_KEY_FILE")"

echo "-- config round trip"
ft_write_config '[{"id":319,"name":"Brann","country":"Norway"}]' 180
chk "teams survive" "Brann" "$(ft_read_config | jq -r '.teams[0].name')"
chk "has_api_key follows the key file" "true" "$(ft_read_config | jq -r '.has_api_key')"
chk "poll interval survives" "180" "$(ft_read_config | jq -r '.poll_interval_live_seconds')"

echo "-- event icons"
chk "own goal" "own-goal.svg" "$(ft_icon_for_event Goal 'Own Goal')"
chk "missed penalty" "penalty-miss.svg" "$(ft_icon_for_event Goal 'Missed Penalty')"
chk "red card" "card-red.svg" "$(ft_icon_for_event Card 'Red Card')"
chk "yellow card" "card-yellow.svg" "$(ft_icon_for_event Card 'Yellow Card')"
chk "substitution" "substitution.svg" "$(ft_icon_for_event subst '')"
chk "unknown event" "whistle.svg" "$(ft_icon_for_event Var '')"

printf '\n%s: %d passed, %d failed\n' "$(basename "$0")" "$pass" "$fail"
[[ "$fail" -eq 0 ]]
