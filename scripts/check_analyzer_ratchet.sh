#!/usr/bin/env bash

set -euo pipefail

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
baseline_file="${ANALYZER_BASELINE_FILE:-$repo_root/.github/analyzer-baseline.txt}"
baseline_version="analyzer-baseline-v1"
input_file=""
update_baseline=false
analyzer_status=0

case "${1:-}" in
  "")
    ;;
  --input)
    if [[ $# -ne 2 ]]; then
      echo "usage: $0 [--input analyzer-machine-output | --update]" >&2
      exit 2
    fi
    input_file="$2"
    ;;
  --update)
    if [[ $# -ne 1 ]]; then
      echo "usage: $0 [--input analyzer-machine-output | --update]" >&2
      exit 2
    fi
    update_baseline=true
    ;;
  *)
    echo "usage: $0 [--input analyzer-machine-output | --update]" >&2
    exit 2
    ;;
esac

work_dir="$(mktemp -d "${TMPDIR:-/tmp}/hiddify-analyzer-ratchet.XXXXXX")"
trap 'rm -rf "$work_dir"' EXIT
normalized_file="$work_dir/current-signatures.txt"

if [[ -z "$input_file" ]]; then
  if ! command -v dart >/dev/null 2>&1; then
    echo "dart is required to run the analyzer ratchet" >&2
    exit 2
  fi

  input_file="$work_dir/analyzer-machine-output.txt"
  set +e
  dart analyze --format=machine > "$input_file" 2>&1
  analyzer_status=$?
  set -e
elif [[ ! -f "$input_file" ]]; then
  echo "analyzer output not found: $input_file" >&2
  exit 2
fi

awk -F '|' -v repo_prefix="$repo_root/" '
  $1 ~ /^(INFO|WARNING|ERROR)$/ {
    path = $4
    if (index(path, repo_prefix) == 1) {
      path = substr(path, length(repo_prefix) + 1)
    } else if (substr(path, 1, 1) == "/") {
      printf "analyzer diagnostic is outside the repository: %s\n", path > "/dev/stderr"
      invalid_path = 1
      next
    }
    print $1 "|" $2 "|" $3 "|" path
  }
  END { exit invalid_path }
' "$input_file" | LC_ALL=C sort > "$normalized_file"

diagnostic_count="$(wc -l < "$normalized_file" | tr -d '[:space:]')"
error_count="$(awk -F '|' '$1 == "ERROR" { count++ } END { print count + 0 }' "$normalized_file")"

if (( error_count > 0 )); then
  echo "analyzer ratchet failed: found $error_count error diagnostic(s)" >&2
  exit 1
fi

if [[ $analyzer_status -ne 0 && $analyzer_status -ne 2 ]]; then
  echo "dart analyze failed with exit code $analyzer_status" >&2
  exit "$analyzer_status"
fi

if [[ $analyzer_status -eq 2 && $diagnostic_count -eq 0 ]]; then
  echo "dart analyze returned warnings without machine-readable diagnostics" >&2
  exit 2
fi

if [[ "$update_baseline" == true ]]; then
  baseline_tmp="$work_dir/baseline.txt"
  {
    echo "$baseline_version"
    cat "$normalized_file"
  } > "$baseline_tmp"
  mv "$baseline_tmp" "$baseline_file"
  echo "analyzer baseline updated: $diagnostic_count normalized diagnostic signature(s)"
  exit 0
fi

if [[ ! -f "$baseline_file" ]]; then
  echo "analyzer baseline not found: $baseline_file" >&2
  echo "run 'bash scripts/check_analyzer_ratchet.sh --update' to create it" >&2
  exit 2
fi

if [[ "$(head -n 1 "$baseline_file")" != "$baseline_version" ]]; then
  echo "unsupported analyzer baseline format: $baseline_file" >&2
  echo "run 'bash scripts/check_analyzer_ratchet.sh --update' to regenerate it" >&2
  exit 2
fi

baseline_signatures="$work_dir/baseline-signatures.txt"
tail -n +2 "$baseline_file" > "$baseline_signatures"
if ! cmp -s "$baseline_signatures" "$normalized_file"; then
  echo "analyzer ratchet failed: normalized diagnostics differ from the versioned baseline" >&2
  diff -u "$baseline_signatures" "$normalized_file" || true
  echo "after reviewing every change, run 'bash scripts/check_analyzer_ratchet.sh --update'" >&2
  exit 1
fi

echo "analyzer ratchet passed: $diagnostic_count normalized diagnostic signature(s) match the baseline"
