#!/usr/bin/env bash
set -euo pipefail

repo_dir="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$repo_dir"
baseline_ref="${1:-9f9fe7b}"
git cat-file -e "$baseline_ref^{commit}"
baseline_dir="$(mktemp -d "${TMPDIR:-/tmp}/liquid-swift-baseline.XXXXXX")"
trap 'rm -rf -- "$baseline_dir"' EXIT
git archive "$baseline_ref" | tar -x -C "$baseline_dir"
# Only add the bridge/product declarations. All engine sources remain at baseline_ref.
cp Package.swift "$baseline_dir/Package.swift"
mkdir -p "$baseline_dir/Tools/LiquidSpecAdapter"
cp Tools/LiquidSpecAdapter/main.swift "$baseline_dir/Tools/LiquidSpecAdapter/main.swift"
swift build --package-path "$baseline_dir" --product LiquidSpecAdapter -Xswiftc -DLIQUID_SWIFT_BASELINE
baseline_bin="$(swift build --package-path "$baseline_dir" --show-bin-path)"
LIQUID_SWIFT_ADAPTER="$baseline_bin/LiquidSpecAdapter" \
  LIQUID_SPEC_REPORT_DIR="$repo_dir/.build/compatibility-baseline" \
  bash "$repo_dir/Compatibility/run.sh" --explore
