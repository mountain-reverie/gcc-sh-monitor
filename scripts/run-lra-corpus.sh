#!/usr/bin/env bash
# LRA differential watchdog.
#
# For each (case, opt-level) in lra-corpus/manifest.json:
#   - Compile case with current GCC (/tmp/gcc-install) at -<opt>
#   - Compile case with reference GCC (/usr/bin/sh4-linux-gnu-gcc) at -<opt>
#   - If expected == compiles_and_runs and both compiled:
#       link both as static, run both under qemu-sh4-static, hash stdout,
#       compare exits
#   - Categorise outcome:
#       BOTH_OK | DIVERGED | CURRENT_ICE | REF_ICE | BOTH_ICE
#
# Emits:
#   /tmp/metrics/lra.json     — aggregate counts for benchmark-action
#   /tmp/lra-results.json     — per-case detail for the dashboard
#
# Environment:
#   GCC_PREFIX     install dir of the candidate GCC (default: /tmp/gcc-install)
#   REF_GCC        reference compiler (default: /usr/bin/sh4-linux-gnu-gcc)
#   CORPUS_DIR     vendored corpus (default: $PWD/lra-corpus)
#   COMMIT         upstream sha (default: jq -r .commit state/last-tested.json)
#   METRICS_FILE   aggregate JSON (default: /tmp/metrics/lra.json)
#   RESULTS_FILE   per-case JSON (default: /tmp/lra-results.json)

set -euo pipefail

GCC_PREFIX="${GCC_PREFIX:-/tmp/gcc-install}"
REF_GCC="${REF_GCC:-/usr/bin/sh4-linux-gnu-gcc}"
CORPUS_DIR="${CORPUS_DIR:-$PWD/lra-corpus}"
COMMIT="${COMMIT:-$(jq -r .commit state/last-tested.json)}"
METRICS_FILE="${METRICS_FILE:-/tmp/metrics/lra.json}"
RESULTS_FILE="${RESULTS_FILE:-/tmp/lra-results.json}"

CUR="$GCC_PREFIX/bin/sh4-linux-gnu-gcc"
SYSROOT="/usr/sh4-linux-gnu"
QEMU="qemu-sh4-static"

[ -x "$CUR" ] || { echo "run-lra: missing $CUR" >&2; exit 1; }
[ -x "$REF_GCC" ] || { echo "run-lra: missing $REF_GCC" >&2; exit 1; }
command -v "$QEMU" >/dev/null || { echo "run-lra: missing $QEMU" >&2; exit 1; }
command -v jq >/dev/null       || { echo "run-lra: missing jq" >&2; exit 1; }
command -v sha256sum >/dev/null || { echo "run-lra: missing sha256sum" >&2; exit 1; }

[ -f "$CORPUS_DIR/manifest.json" ] || {
  echo "run-lra: missing $CORPUS_DIR/manifest.json" >&2
  exit 1
}

mkdir -p "$(dirname "$METRICS_FILE")" "$(dirname "$RESULTS_FILE")"

declare -A counts=(
  [BOTH_OK]=0 [DIVERGED]=0 [CURRENT_ICE]=0 [REF_ICE]=0 [BOTH_ICE]=0 [SKIPPED]=0
)
total=0
case_jsons=()

compile_one() {
  local compiler="$1" src="$2" opt="$3" out="$4" mode="$5"
  local flags
  if [ "$mode" = "compiles_and_runs" ]; then
    flags="-B/usr/bin/sh4-linux-gnu- --sysroot=$SYSROOT -$opt -w -static"
  else
    flags="-c -B/usr/bin/sh4-linux-gnu- --sysroot=$SYSROOT -$opt -w"
  fi
  "$compiler" $flags "$src" -o "$out" >/dev/null 2>&1
}

run_under_qemu() {
  local bin="$1"
  local stdout
  stdout=$(timeout 10 "$QEMU" -L "$SYSROOT" "$bin" 2>/dev/null) || true
  local exit_code=$?
  local hash
  hash=$(printf '%s' "$stdout" | sha256sum | cut -d' ' -f1)
  echo "$exit_code:$hash"
}

while IFS= read -r case_name; do
  case_path="$CORPUS_DIR/$case_name"
  if [ ! -f "$case_path" ]; then
    echo "run-lra: missing case file $case_path (in manifest)" >&2
    continue
  fi
  expected=$(jq -r --arg n "$case_name" '.[$n].expected' "$CORPUS_DIR/manifest.json")
  mapfile -t opts < <(jq -r --arg n "$case_name" '.[$n].opt_levels[]' "$CORPUS_DIR/manifest.json")

  per_opt_jsons=()

  for opt in "${opts[@]}"; do
    workdir=$(mktemp -d)
    cur_out="$workdir/cur"
    ref_out="$workdir/ref"
    cur_ok=true; ref_ok=true
    detail=""

    compile_one "$CUR"     "$case_path" "$opt" "$cur_out" "$expected" || cur_ok=false
    compile_one "$REF_GCC" "$case_path" "$opt" "$ref_out" "$expected" || ref_ok=false

    if $cur_ok && $ref_ok; then
      if [ "$expected" = "compiles_and_runs" ]; then
        cur_res=$(run_under_qemu "$cur_out")
        ref_res=$(run_under_qemu "$ref_out")
        if [ "$cur_res" = "$ref_res" ]; then
          outcome=BOTH_OK
        else
          outcome=DIVERGED
          detail="cur=$cur_res ref=$ref_res"
        fi
      else
        outcome=BOTH_OK
      fi
    elif $ref_ok && ! $cur_ok; then
      outcome=CURRENT_ICE
    elif $cur_ok && ! $ref_ok; then
      outcome=REF_ICE
    else
      outcome=BOTH_ICE
    fi

    counts[$outcome]=$((counts[$outcome]+1))
    total=$((total+1))

    # Escape detail for JSON (quotes/backslashes).
    detail_json=$(printf '%s' "$detail" | jq -Rs .)
    per_opt_jsons+=("{\"opt\":\"$opt\",\"outcome\":\"$outcome\",\"detail\":$detail_json}")
    rm -rf "$workdir"
  done

  per_opt_csv=$(IFS=,; echo "${per_opt_jsons[*]}")
  case_jsons+=("{\"name\":\"$case_name\",\"expected\":\"$expected\",\"results\":[$per_opt_csv]}")
done < <(jq -r 'keys[]' "$CORPUS_DIR/manifest.json")

diverged=$((counts[DIVERGED] + counts[CURRENT_ICE]))

cat > "$METRICS_FILE" <<EOF
[
  {"name": "lra_diverged_count",     "unit": "tuples", "value": $diverged},
  {"name": "lra_current_ice_count",  "unit": "tuples", "value": ${counts[CURRENT_ICE]}},
  {"name": "lra_total_count",        "unit": "tuples", "value": $total}
]
EOF

cases_csv=$(IFS=,; echo "${case_jsons[*]}")
date_now=$(date -u +%Y-%m-%dT%H:%M:%SZ)
printf '{"commit":"%s","date":"%s","totals":{"diverged":%d,"current_ice":%d,"total":%d},"cases":[%s]}\n' \
  "$COMMIT" "$date_now" "$diverged" "${counts[CURRENT_ICE]}" "$total" "$cases_csv" \
  | jq . > "$RESULTS_FILE"

echo "run-lra: $total tuples — BOTH_OK=${counts[BOTH_OK]} DIVERGED=${counts[DIVERGED]} CURRENT_ICE=${counts[CURRENT_ICE]} REF_ICE=${counts[REF_ICE]} BOTH_ICE=${counts[BOTH_ICE]}"
echo "run-lra: wrote $METRICS_FILE and $RESULTS_FILE"
