#!/usr/bin/env bash
set -euo pipefail

repo_dir="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$repo_dir"
export BUNDLE_GEMFILE="$repo_dir/Compatibility/Gemfile"
export RUBYOPT="${RUBYOPT:+$RUBYOPT }-EUTF-8:UTF-8"

if [[ -z "${LIQUID_SWIFT_ADAPTER:-}" ]]; then
  swift build --product LiquidSpecAdapter
  LIQUID_SWIFT_ADAPTER="$(swift build --show-bin-path)/LiquidSpecAdapter"
fi
export LIQUID_SWIFT_ADAPTER
bundle check

default_report_dir="$repo_dir/.build/compatibility"
if [[ "${1:-}" == "--explore" ]]; then default_report_dir="$repo_dir/.build/compatibility-explore"; fi
report_dir="${LIQUID_SPEC_REPORT_DIR:-$default_report_dir}"
mkdir -p "$report_dir"
arguments=(--no-max-failures --json --list-passed)
if [[ "${1:-}" != "--explore" ]]; then
  arguments+=("--known-failures=$repo_dir/Compatibility/known-failures.txt")
fi
status=0
bundle exec liquid-spec run "$repo_dir/Compatibility/adapter.rb" \
  "${arguments[@]}" > "$report_dir/results.json" || status=$?
ruby -rjson -e '
  report = JSON.parse(File.read(ARGV.fetch(0)))
  puts JSON.pretty_generate(report.fetch("totals"))
  puts "Complexity level cleared: #{report.fetch("max_complexity_reached")} / #{report.fetch("max_possible_complexity")}"
  %w[failures known_fixed].each do |key|
    report.fetch(key).first(20).each { |entry| puts "#{key}: #{entry.fetch("name")} #{entry["error"] || entry["actual"]}" }
  end
' "$report_dir/results.json"
echo "Full official results: $report_dir/results.json"
if [[ "${1:-}" != "--explore" ]]; then
  ruby Compatibility/check_report.rb "$report_dir/results.json" || status=1
fi
exit "$status"
