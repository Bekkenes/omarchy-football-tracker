#!/usr/bin/env bash
# Regression suite for the Football Tracker plugin: `test/run.sh`.
#
# Requires bash, jq (or a compatible implementation) and node >= 18 for the
# Model.js unit tests. Nothing here touches the network, the real plugin
# config, or the running shell.
set -uo pipefail

cd "$(dirname "${BASH_SOURCE[0]}")"

for dep in node jq; do
  command -v "$dep" >/dev/null 2>&1 || { echo "test/run.sh: $dep is required" >&2; exit 1; }
done

status=0

echo "== Model.js unit tests =="
node --test model.test.js || status=1

for suite in lib.test.sh poll.test.sh; do
  printf '\n== %s ==\n' "$suite"
  bash "$suite" || status=1
done

if [[ "$status" -eq 0 ]]; then
  printf '\nAll suites passed.\n'
else
  printf '\nSome suites failed.\n' >&2
fi
exit "$status"
