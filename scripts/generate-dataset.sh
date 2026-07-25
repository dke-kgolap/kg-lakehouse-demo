#!/usr/bin/env bash
# Generate the demonstration dataset with ATM-GEN (runs in a container; no
# local Java required). Generation is deterministic in structure and size
# (same days, regions, and document counts on every run); flight identifiers
# in the FIXM documents vary between runs.
#
# Output: ./dataset — seven days of synthetic operations (2025-01-01 to
# 2025-01-07): AIXM infrastructure baselines and NOTAMs, IWXXM weather
# reports (METAR, TAF, SIGMET), and FIXM flight plans.
#
# Environment overrides: ATM_GEN_IMAGE, START, END, RANDOM_SEED.
set -euo pipefail
cd "$(dirname "$0")/.."

ATM_GEN_IMAGE="${ATM_GEN_IMAGE:-basharahmad/atm-gen:1.0.0}"
START="${START:-2025-01-01}"
END="${END:-2025-01-07}"
RANDOM_SEED="${RANDOM_SEED:-42}"
WORK="$PWD/dataset-work"
OUT="$PWD/dataset"

mkdir -p "$WORK" "$OUT"
atm_gen() { docker run --rm --platform linux/amd64 -u "$(id -u):$(id -g)" -v "$WORK":/work -v "$OUT":/out "$ATM_GEN_IMAGE" "$@"; }

if [[ ! -f "$WORK/seed.yaml" ]]; then
  echo "==> Extracting the airspace seed from the bundled Donlon 2022 reference"
  atm_gen seed extract --donlon-dir /opt/donlon -o /work/seed.yaml
fi

echo "==> Generating documents ($START to $END, random seed $RANDOM_SEED)"
atm_gen generate aixm --seed /work/seed.yaml -o /out
for fmt in notams metars tafs sigmets flights; do
  atm_gen generate "$fmt" --seed /work/seed.yaml -o /out \
      --start "$START" --end "$END" --random-seed "$RANDOM_SEED"
done

total=$(find "$OUT" -type f -name '*.xml' | wc -l)
echo "==> Done: $total XML documents in ./dataset"
find "$OUT" -type f -name '*.xml' | sed -E 's#.*/([^/]+)/[^/]+$#\1#' | sort | uniq -c
