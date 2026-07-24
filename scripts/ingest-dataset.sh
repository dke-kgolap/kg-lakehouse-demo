#!/usr/bin/env bash
# Upload every document in ./dataset to the running lakehouse, routing each
# format to its schema:
#   */aixm/*.xml   -> schema atm    (content type application/xml+aixm)
#   */iwxxm/*.xml  -> schema meteo  (content type application/xml+iwxxm)
#   */fixm/*.xml   -> schema fixm   (content type application/xml+fixm)
#
# Afterwards, polls the per-schema statistics until context extraction has
# finished and prints the final counts.
#
# Environment overrides: SURFACE_URL, USER_AUTH, DATASET, CONCURRENCY.
set -euo pipefail
cd "$(dirname "$0")/.."

SURFACE_URL="${SURFACE_URL:-http://localhost:8080}"
USER_AUTH="${USER_AUTH:-admin:admin}"
DATASET="${DATASET:-$PWD/dataset}"
CONCURRENCY="${CONCURRENCY:-8}"

[[ -d "$DATASET" ]] || { echo "Dataset not found: $DATASET (run scripts/generate-dataset.sh first)" >&2; exit 1; }

post_one() {
  local rel="$1" schema ctype
  case "$rel" in
    */aixm/*.xml)  schema=atm;   ctype=application/xml+aixm ;;
    */iwxxm/*.xml) schema=meteo; ctype=application/xml+iwxxm ;;
    */fixm/*.xml)  schema=fixm;  ctype=application/xml+fixm ;;
    *) return 0 ;;
  esac
  local http
  http=$(curl -sS -o /dev/null -w '%{http_code}' -u "$USER_AUTH" \
      -F "file=@${DATASET}/${rel};type=${ctype}" \
      "$SURFACE_URL/api/schemas/$schema/ingest" || echo 000)
  [[ "$http" =~ ^2 ]] && echo "OK $rel" || echo "FAIL $http $rel" >&2
}
export -f post_one
export SURFACE_URL USER_AUTH DATASET

echo "==> Uploading $(cd "$DATASET" && find . -name '*.xml' | wc -l) documents to $SURFACE_URL"
start=$(date +%s)
(cd "$DATASET" && find . -type f -name '*.xml' | sort) \
  | xargs -P "$CONCURRENCY" -I '{}' bash -c 'post_one "$@"' _ '{}' \
  | { ok=0; fail=0; while read -r line; do
        case "$line" in OK*) ok=$((ok+1));; *) fail=$((fail+1));; esac
        (( (ok+fail) % 200 == 0 )) && echo "  ...$((ok+fail)) uploaded"
      done; echo "==> Uploaded: $ok ok, $fail failed, $(( $(date +%s) - start ))s"; }

echo "==> Waiting for context extraction to finish"
prev=""
while true; do
  cur=$(for s in atm meteo fixm; do
    curl -fsS -u "$USER_AUTH" "$SURFACE_URL/api/schemas/$s/stats" \
      | python3 -c 'import json,sys; d=json.load(sys.stdin); print(d["schemaId"], d["totalContexts"], "contexts,", d["totalFiles"], "documents")'
  done)
  [[ -n "$cur" && "$cur" == "$prev" ]] && break
  prev="$cur"; sleep 5
done
echo "$cur"
echo "==> Ready. Open the console: http://localhost:3001 (user admin, password admin)"
