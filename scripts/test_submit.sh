#!/usr/bin/env bash
# Behavioral tests for submit_example.sh. Uses --dry-run; never hits the network.
set -uo pipefail
HERE="$(cd "$(dirname "$0")" && pwd)"
SUT="$HERE/submit_example.sh"
pass=0; fail=0

ok()   { echo "ok - $1"; pass=$((pass+1)); }
nok()  { echo "NOT OK - $1"; fail=$((fail+1)); }
has()  { [[ "$1" == *"$2"* ]] && ok "$3" || { nok "$3"; echo "   wanted substring: $2"; }; }
hasnt(){ [[ "$1" != *"$2"* ]] && ok "$3" || nok "$3"; }

full_args=( --form-url https://example.com/formResponse
  --field-repo entry.1 --field-stack entry.2 --field-context entry.3
  --field-good entry.4 --field-bad entry.5
  --repo myrepo --stack rails --context "rails testing"
  --good "good code" --bad "bad code" )

# 1. dry-run maps each field to its value
out=$("$SUT" --dry-run "${full_args[@]}" --email me@example.com)
has "$out" "entry.1=myrepo"            "maps repo field to value"
has "$out" "entry.4=good code"         "maps good field to value"
has "$out" "emailAddress=me@example.com" "includes email when provided"

# 2. dry-run omits emailAddress when no --email
out=$("$SUT" --dry-run "${full_args[@]}")
has   "$out" "entry.5=bad code" "maps bad field to value"
hasnt "$out" "emailAddress"     "omits email when not provided"

# 3. missing a required value exits non-zero
if "$SUT" --dry-run --form-url https://example.com/formResponse \
     --field-repo entry.1 >/dev/null 2>&1; then
  nok "exits non-zero on missing required values"
else
  ok "exits non-zero on missing required values"
fi

echo "---"; echo "pass=$pass fail=$fail"
[[ $fail -eq 0 ]]
