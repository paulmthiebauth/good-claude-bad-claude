#!/usr/bin/env bash
#
# submit_example.sh - POST one good/bad code example to a Google Form.
# Pure curl; no external dependencies. All form-specific values are passed in as
# flags by the caller (the plugin skill reads them from config.json).
#
# Required: --form-url, the five --field-* IDs, and the five value flags
# (--repo --stack --context --good --bad). --email is optional. --dry-run prints
# the curl invocation and sends nothing.
#
set -euo pipefail

form_url="" email=""
field_repo="" field_stack="" field_context="" field_good="" field_bad=""
val_repo="" val_stack="" val_context="" val_good="" val_bad=""
dry_run=false

usage() { grep '^#' "$0" | sed 's/^# \{0,1\}//'; exit "${1:-0}"; }

while [[ $# -gt 0 ]]; do
  case "$1" in
    --form-url)      form_url="$2"; shift 2;;
    --email)         email="$2"; shift 2;;
    --field-repo)    field_repo="$2"; shift 2;;
    --field-stack)   field_stack="$2"; shift 2;;
    --field-context) field_context="$2"; shift 2;;
    --field-good)    field_good="$2"; shift 2;;
    --field-bad)     field_bad="$2"; shift 2;;
    --repo)          val_repo="$2"; shift 2;;
    --stack)         val_stack="$2"; shift 2;;
    --context)       val_context="$2"; shift 2;;
    --good)          val_good="$2"; shift 2;;
    --bad)           val_bad="$2"; shift 2;;
    --dry-run)       dry_run=true; shift;;
    -h|--help)       usage 0;;
    *) echo "Unknown argument: $1" >&2; usage 1;;
  esac
done

missing=""
for pair in "form_url:--form-url" \
            "field_repo:--field-repo" "field_stack:--field-stack" \
            "field_context:--field-context" "field_good:--field-good" \
            "field_bad:--field-bad" \
            "val_repo:--repo" "val_stack:--stack" "val_context:--context" \
            "val_good:--good" "val_bad:--bad"; do
  var="${pair%%:*}"; flag="${pair##*:}"
  if [[ -z "${!var}" ]]; then missing="$missing $flag"; fi
done
if [[ -n "$missing" ]]; then
  echo "Missing required:$missing" >&2
  exit 1
fi

args=( --data-urlencode "${field_repo}=${val_repo}"
       --data-urlencode "${field_stack}=${val_stack}"
       --data-urlencode "${field_context}=${val_context}"
       --data-urlencode "${field_good}=${val_good}"
       --data-urlencode "${field_bad}=${val_bad}" )
if [[ -n "$email" ]]; then
  args+=( --data-urlencode "emailAddress=${email}" )
fi

if $dry_run; then
  out="curl -s -X POST $form_url"
  i=0
  while [[ $i -lt ${#args[@]} ]]; do
    out="$out ${args[i]} '${args[i+1]}'"
    i=$((i+2))
  done
  echo "$out"
  exit 0
fi

status=$(curl -s -o /dev/null -w '%{http_code}' -X POST "$form_url" "${args[@]}")
if [[ "$status" == "200" ]]; then
  echo "OK Submitted (HTTP $status)"
else
  echo "FAILED (HTTP $status)" >&2
  exit 1
fi
