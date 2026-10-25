# Official Liquid compatibility

This directory runs **Shopify's original `liquid-spec` tool and fixtures**, not a hand-picked Swift rewrite of its tests. Bundler downloads the suite at commit [`84bf25e0edbca5f7e530574788b0f875ab331f50`](https://github.com/Shopify/liquid-spec/tree/84bf25e0edbca5f7e530574788b0f875ab331f50); `Gemfile.lock` fixes its Ruby dependencies. The upstream project is MIT licensed; see [its license](https://github.com/Shopify/liquid-spec/blob/84bf25e0edbca5f7e530574788b0f875ab331f50/LICENSE.txt).

`LiquidSpecAdapter` implements the upstream newline-delimited JSON-RPC protocol (`initialize`, `compile`, `render`, `quit`). Every template is compiled/rendered by **this Swift library**. Ruby Liquid is loaded only because the official harness requires host-side fixture classes; it never substitutes reference output for the Swift result. Parse errors and raised render errors cross the bridge as errors, not empty strings. The harness's frozen clock and partial maps are forwarded to the Swift renderer.

## Current results

Measured with Swift 6.4.1 on Linux x86_64, using the same suite revision/profile for both engines:

| Engine | Passing executions | Failing/error executions |
| --- | ---: | ---: |
| Merged Swift 6 prototype, `9f9fe7b` | 1,532 | 2,772 |
| This implementation | 2,391 | 1,913 |

**859 newly passing checks; zero previously passing names regressed.** The selected upstream profile expands to 4,304 executions with 4,297 distinct names; the seven duplicate-name executions are retained, not deduplicated out of the results.

| Category | Passing | Known failures |
| --- | ---: | ---: |
| Other selected rendering/behavior checks | 2,379 | 20 |
| Explicit strict parser-error suite | 12 | 1,893 |

Most parser-error discrepancies involve diagnostic wording/location. **46 error-suite checks still parse successfully when the reference expects rejection**; these are real grammar gaps, not merely presentation differences. Other remaining differences include dictionary insertion order, host ranges, mock filesystem callbacks/case normalization, and a few malformed-tag behaviors. The exact list is in [known-failures.txt](known-failures.txt); machine-readable counts/profile are in [summary.json](summary.json).

These numbers apply to the declared profile, **not the entire upstream repository or all Shopify Liquid behavior**.

## Profile and regression gate

The adapter explicitly requests `basics`, `liquid_ruby`, `partials` (correctness, not timing), and `parser_errors`, using strict2 parsing and raised render errors. Unsupported capabilities are declared in [adapter.rb](adapter.rb): arbitrary Drops/Ruby types, binary strings, template factories, lax/legacy strict parsing, inline render errors, Shopify storefront extensions, reference score-based resource accounting, and randomized fixtures. Feature-tagged tests requiring those capabilities are excluded by the official harness. Ordinary standard tags/filters are not opted out of individually.

The checked-in failure file contains **exact spec names**, grouped by upstream source. There are no wildcard allowances. The official runner returns failure if a new spec fails or an allowed failure starts passing (a stale allowance must be removed). An additional inventory check verifies both the execution count and a SHA-256 of the complete passing-name list, including duplicates. Silently skipping tests or replacing one passing set with another cannot turn the gate green.

**A green gate means the measured baseline did not regress; it does not turn 1,913 known failures into passing tests.** CI uploads the original JSON with separate `passed`, `known_failures`, `failures`, and `known_fixed` fields on Linux and macOS.

## Run

Requires Swift 6+, Ruby 3.3+, and Bundler 2.6.7. On Linux, Ruby development headers and a C compiler/make are needed for the harness's native gem dependencies. The Swift library itself remains dependency-free.

From the repository root:

```sh
BUNDLE_GEMFILE=Compatibility/Gemfile BUNDLE_PATH=.build/compatibility-gems bundle install
BUNDLE_PATH=.build/compatibility-gems bash Compatibility/run.sh
```

The report is `.build/compatibility/results.json`. `LIQUID_SWIFT_ADAPTER` can override the executable path; otherwise the script builds it. The adapter path is shell-escaped. Ruby transport encoding is forced to UTF-8 without modifying process-global locale/timezone settings in the engine.

To see real failures without allowances:

```sh
BUNDLE_PATH=.build/compatibility-gems bash Compatibility/run.sh --explore
```

This writes `.build/compatibility-explore/results.json` and **exits nonzero while any official check fails**. Do not treat that exit as a harness failure; inspect the JSON first. Transport/setup failures and malformed reports also fail the run.

To reproduce the old-engine comparison, make sure commit `9f9fe7b` is available locally (fetch history if using a shallow clone):

```sh
BUNDLE_PATH=.build/compatibility-gems bash Compatibility/baseline.sh
```

It archives the old engine to a temporary directory and adds the same JSON-RPC bridge with `LIQUID_SWIFT_BASELINE` compilation enabled. That flag only accommodates the old initializer/render signatures: it does not change the engine or its expected output. The same official fixtures, feature profile, JSON error handling and Ruby dependency lock are used. Results go to `.build/compatibility-baseline/results.json`; expected old failures make it exit nonzero.

## Updating coverage

After implementing a fix, run `--explore`, review the changed cases against the reference, then explicitly run:

```sh
python3 Compatibility/refresh.py
BUNDLE_PATH=.build/compatibility-gems bash Compatibility/run.sh
```

The refresh script refuses newly failing names and changed execution counts. It updates the exact known failures and passing digest; it is never run automatically in CI. To regenerate the original comparison, supply `--before .build/compatibility-baseline/results.json`. Keep new failures out of the allowance file and test new public API/budget behavior with native Swift regressions as well.
