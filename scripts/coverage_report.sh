#!/usr/bin/env bash
set -euo pipefail

# Coverage report + gate for the Suniye app target.
#
# Usage: coverage_report.sh [--xcresult PATH] [--threshold PCT]
#
# Reads the xcresult bundle produced by `xcodebuild test -enableCodeCoverage YES`,
# prints per-file line coverage for the app target, and fails if coverage of
# non-excluded files is below the threshold (default 80).
#
# Files listed in scripts/coverage_exclusions.txt (repo-relative paths, one per
# line, '#' comments allowed) are excluded from the gate but still reported.

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
XCRESULT="${ROOT_DIR}/.derivedData/coverage.xcresult"
THRESHOLD="80"

while [[ $# -gt 0 ]]; do
  case "$1" in
    --xcresult) XCRESULT="$2"; shift 2 ;;
    --threshold) THRESHOLD="$2"; shift 2 ;;
    *) echo "Unknown argument: $1" >&2; exit 2 ;;
  esac
done

if [[ ! -d "${XCRESULT}" ]]; then
  echo "No xcresult bundle at ${XCRESULT}; run tests with -enableCodeCoverage YES -resultBundlePath first." >&2
  exit 2
fi

JSON_FILE="$(mktemp)"
trap 'rm -f "${JSON_FILE}"' EXIT
xcrun xccov view --report --json "${XCRESULT}" > "${JSON_FILE}"

EXCLUSIONS_FILE="${ROOT_DIR}/scripts/coverage_exclusions.txt"

python3 - "$THRESHOLD" "$EXCLUSIONS_FILE" "$ROOT_DIR" "$JSON_FILE" <<'PY'
import json, sys

threshold = float(sys.argv[1])
exclusions_file, root = sys.argv[2], sys.argv[3]

exclusions = set()
try:
    with open(exclusions_file) as fh:
        for line in fh:
            line = line.split("#", 1)[0].strip()
            if line:
                exclusions.add(line)
except FileNotFoundError:
    pass

with open(sys.argv[4]) as fh:
    report = json.load(fh)
app_targets = [t for t in report["targets"] if t["name"].endswith(".app")]
if not app_targets:
    sys.exit("No .app target found in coverage report")

rows, gated_covered, gated_executable, unused_exclusions = [], 0, 0, set(exclusions)
for target in app_targets:
    for f in target["files"]:
        path = f["path"]
        prefix = root + "/"
        rel = path[len(prefix):] if path.startswith(prefix) else path
        excluded = rel in exclusions
        if excluded:
            unused_exclusions.discard(rel)
        else:
            gated_covered += f["coveredLines"]
            gated_executable += f["executableLines"]
        rows.append((f["lineCoverage"], rel, f["coveredLines"], f["executableLines"], excluded))

rows.sort()
print(f"{'COVER':>7}  {'LINES':>11}  FILE")
for cov, rel, covered, executable, excluded in rows:
    tag = "  [excluded]" if excluded else ""
    print(f"{cov * 100:6.1f}%  {covered:>5}/{executable:<5}  {rel}{tag}")

if unused_exclusions:
    print("\nStale exclusions (no matching file in coverage report):")
    for rel in sorted(unused_exclusions):
        print(f"  {rel}")
    sys.exit(1)

total = gated_covered / gated_executable * 100 if gated_executable else 100.0
print(f"\nGated coverage (excl. {len(exclusions)} excluded files): "
      f"{total:.2f}% ({gated_covered}/{gated_executable} lines), threshold {threshold:g}%")

if total + 1e-9 < threshold:
    failing = [(c, r) for c, r, _, _, ex in rows if not ex and c < 1.0]
    print(f"\nFAIL: below threshold. {len(failing)} non-excluded files under 100%.")
    sys.exit(1)
print("PASS")
PY
