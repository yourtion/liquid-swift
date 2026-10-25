#!/usr/bin/env python3
"""Explicitly refresh reviewed known failures after an exploration run; never used by CI."""
import argparse
import collections
import hashlib
import json
from pathlib import Path

root = Path(__file__).resolve().parent
parser = argparse.ArgumentParser()
parser.add_argument("report", nargs="?", default=str(root.parent / ".build/compatibility-explore/results.json"))
parser.add_argument("--before", help="Report for the merged baseline engine, using the same pinned suite/profile")
args = parser.parse_args()
report = json.loads(Path(args.report).read_text())
passed = {entry["name"] for entry in report["passed"]}
failed = {entry["name"] for entry in report["failures"]}
executed_names = [entry["name"] for entry in report["passed"] + report["failures"]]
assert not report["known_failures"] and not report["known_fixed"], "Use an unfiltered --explore report"
assert not (passed & failed)
summary_file = root / "summary.json"
old = json.loads(summary_file.read_text()) if summary_file.exists() else None
known_file = root / "known-failures.txt"
if known_file.exists():
    previous = {line for line in known_file.read_text().splitlines() if line and not line.startswith("#")}
    if failed - previous:
        raise SystemExit("Refusing to approve regressions: " + repr(sorted(failed - previous)))
    if old and not args.before and len(executed_names) != old["tracked_specs"]:
        raise SystemExit("Spec inventory changed; review the upstream revision/profile explicitly")
if args.before:
    before = json.loads(Path(args.before).read_text())
    prior_passed = {entry["name"] for entry in before["passed"]}
    prior_failed = {entry["name"] for entry in before["failures"]}
    assert sorted(entry["name"] for entry in before["passed"] + before["failures"]) == sorted(executed_names), "Different spec execution inventory"
    assert prior_passed | prior_failed == passed | failed, "Different spec inventory"
    assert prior_passed <= passed, "A previously passing spec regressed"
    baseline = {"commit": "9f9fe7b", "passed": len(before["passed"]), "failed_or_error": len(before["failures"])}
else:
    baseline = old["baseline"] if old else None
groups = collections.defaultdict(list)
for entry in report["failures"]:
    source = entry["source_file"].split("/specs/")[-1].removeprefix("specs/")
    groups[source].append(entry["name"])
lines = [
    "# Exact names from pinned Shopify/liquid-spec. No wildcards and no standard-tag skips.",
    "# These are real known failures, not passing compatibility tests.",
    "# CI rejects new failures, newly passing stale entries, and changed passing inventories.",
]
for source, names in sorted(groups.items()):
    lines += ["", "# " + source]
    lines += sorted(names)
known_file.write_text("\n".join(lines) + "\n")
def section(entry):
    return "parser_errors" if "/parser_errors/" in entry["source_file"] else "other_selected_specs"
breakdown = {}
for key, entries in [("passed", report["passed"]), ("known_failures", report["failures"])]:
    for name, count in collections.Counter(section(entry) for entry in entries).items():
        breakdown.setdefault(name, {})[key] = count
summary = {
    "upstream": "https://github.com/Shopify/liquid-spec",
    "revision": (root / "upstream-revision.txt").read_text().strip(),
    "suites": ["basics", "liquid_ruby", "partials", "parser_errors"],
    "toolchain_for_measurement": "Swift 6.4.1 / Linux x86_64",
    "tracked_specs": len(executed_names),
    "unique_spec_names": len(passed | failed),
    "passed": len(report["passed"]),
    "known_failures": len(report["failures"]),
    "passing_ids_sha256": hashlib.sha256(("\n".join(sorted(entry["name"] for entry in report["passed"])) + "\n").encode()).hexdigest(),
    "baseline": baseline,
    "newly_passing_since_baseline": len(report["passed"]) - baseline["passed"] if baseline else None,
    "regressions_since_baseline": 0 if args.before else old.get("regressions_since_baseline") if old else None,
    "breakdown": breakdown,
    "parser_error_specs_accepted_without_error": sum(
        section(entry) == "parser_errors" and "no error" in str(entry.get("actual")) for entry in report["failures"]
    ),
    "complexity_level_cleared": report["max_complexity_reached"],
    "missing_features": report["missing_features"],
}
summary_file.write_text(json.dumps(summary, indent=2, ensure_ascii=False) + "\n")
print(json.dumps(summary, indent=2))
