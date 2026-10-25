# Liquid Swift

A dependency-free Liquid template engine for **Swift 6.0 or later**, using Swift 6 language mode. Supports macOS and Linux through Swift Package Manager.

## Installation

Add the repository to your package dependencies (use a release tag when available):

```swift
.package(url: "https://github.com/yourtion/liquid-swift.git", branch: "master")
```

Then add `.product(name: "Liquid", package: "liquid-swift")` to your target dependencies.

## Usage

```swift
import Liquid

let template = try Template("""
Hello {{ user.name | default: 'guest' | escape }}!
{% for product in products %}
{{ forloop.index }}. {{ product.name }}: {{ product.price | times: 2 }}
{% else %}
No products.
{% endfor %}
""")

let output = try template.render([
    "user": ["name": "Ada"],
    "products": [["name": "Tea", "price": 3]]
])
```

Templates are parsed once. Each `render(_:)` call starts with fresh variables, counters and loop state. Pass `render(context:)` to retain assignments in a public, mutable `Context`. Use separate contexts for concurrent work. `Template` is not `Sendable`; custom filters can capture mutable state.

Variables accept strings, numbers, booleans, arrays, dictionaries and `NSNull`. Missing variables render as an empty string. Dot and bracket lookups work, including dynamic keys: `{{ users[index]['full name'] }}`. Arrays expose `first`, `last`, `size`, and positive or negative indices. Dictionaries expose their keys (including a literal `size` key) and otherwise support `size`.

`self` provides a live view of the current variables: `{{ self[key] }}`. Strict2 parsing requires `self[key]` instead of a bare `[key]` lookup. Literal ranges render as `1..3` and can be assigned, iterated, or passed through collection filters. Bracket access reads actual keys/indices; dot access also provides supported properties such as `first` and `size`.

Output is **not automatically HTML escaped**; use `escape` when producing HTML from untrusted values.

## Features

- [x] `comment` and `raw`, including uninterpreted Liquid markup in their bodies
- [x] Liquid truthiness: only `nil` and `false` are falsy; `0`, empty strings and arrays are truthy
- [x] Whitespace control: `{{-`, `-}}`, `{%-`, `-%}`
- [x] Chained filters, quoted arguments and custom filters
- [x] `assign`, `capture`, `increment`, `decrement` (counters are independent of assigned variables)
- [x] `==`, `!=`, `>`, `<`, `>=`, `<=`, `contains`, `and`, `or`
- [x] `if`, `unless`, `elsif`, `else`, `case` / `when` (comma or `or` alternatives)
- [x] Nested `for`, `break`, `continue`, loop `else`
- [x] `limit`, `offset`, `offset: continue`, numeric ranges and `reversed`
- [x] `forloop.index`, `index0`, `rindex`, `rindex0`, `first`, `last`, `length`, `parentloop`
- [x] Built-in filters, including `default` and `allow_false: true`
- [x] `echo`, multiline `liquid`, inline `#` comments and `doc`
- [x] `cycle` (named groups, literal sharing and independent variable cycles), `ifchanged`
- [x] `tablerow`, `cols`, `limit`, `offset` and `tablerowloop` metadata
- [x] `include` and isolated `render`, with preloaded partials, parameters, `with`, `for` and `as`

Logical operators evaluate **right to left**, as in Liquid; grouping parentheses are not supported. Parentheses are used only for inclusive ranges such as `(1..count)`. Conditions do not coerce strings into numbers: ordering comparisons between numbers and strings throw; comparisons involving non-orderable values yield false. `empty` and `blank` comparisons are supported.

`case` renders every matching `when` value in order, including duplicate matches; it does not stop after the first match. Whitespace-only control-flow bodies suppress their literal whitespace while still executing assignments and other side effects. Raw content retains its internal whitespace.

Dictionary loops yield `[key, value]` pairs in sorted key order for deterministic rendering. Loop variables and `forloop` are restored after a loop; other assignments persist in the current context.

## Built-in filters

| Group | Filters |
| --- | --- |
| Math | `abs`, `at_least`, `at_most`, `ceil`, `divided_by`, `floor`, `minus`, `modulo`, `plus`, `round`, `times` |
| String | `append`, `capitalize`, `downcase`, `upcase`, `prepend`, `remove`, `remove_first`, `remove_last`, `replace`, `replace_first`, `replace_last`, `lstrip`, `rstrip`, `strip`, `squish`, `strip_newlines`, `newline_to_br`, `split`, `slice`, `truncate`, `truncatewords` |
| HTML / URL / Encoding | `escape`, `escape_once`, `h`, `strip_html`, `url_encode`, `url_decode`, `base64_encode`, `base64_decode`, `base64_url_safe_encode`, `base64_url_safe_decode` |
| Collection | `size`, `concat`, `compact`, `first`, `last`, `join`, `map`, `reverse`, `sort`, `sort_natural`, `uniq`, `where`, `reject`, `has`, `find`, `find_index`, `sum` |
| Other | `default`, `date` |

`divided_by` uses integer division when both operands are integers; either decimal operand selects floating-point division (`5 | divided_by: 2` → `2`; `5.0 | divided_by: 2` → `2.5`). Numbers use `Double` values, with decimal intermediates for some arithmetic/aggregation; this is not an arbitrary-precision engine.

`date` accepts Unix timestamps (including numeric strings), ISO 8601 and common date strings, `now`, and `today`. It uses English names and UTC by default, preserving an explicit input timezone offset. Common strftime directives, ISO week/year, and padding/case modifiers are supported; unknown directives pass through. Pass `render(variables, currentTime: date)` to freeze `now` / `today` without changing the process clock.

Collection filters wrap scalars and flatten nested arrays as the reference engine does. Arrays render by concatenating elements, while string filters stringify collections with Ruby-style inspection. Optional forms include `default`, `uniq: 'property'`, and omitted replacement strings for `replace` / `replace_first`. Unknown filters pass through unchanged; opt into errors with `Template(source, strictFilters: true)`.

```swift
let template = try Template("{{ name | greet: '!' }}", filters: [
    "greet": { value, arguments in
        "Hello \(value as? String ?? "")\(arguments.first as? String ?? "")"
    }
])
let output = try template.render(["name": "Ada"]) // Hello Ada!
```

Filters are registered per template and can override built-ins. Arguments are positional; a named argument is delivered as a single `[String: Any]` argument.

## Partials

```swift
let template = try Template(
    "{% render 'card', title: name %}",
    partials: ["card": "<h2>{{ title | escape }}</h2>"]
)
let html = try template.render(["name": "Ada"])
```

Partials are an explicit, case-sensitive dictionary; the engine never reads the filesystem. They are parsed lazily and cached within each render. `render` isolates assignments and counters, shares initial input globals, and accepts explicit parameters. `include` shares assignments/counters with its caller, while its parameters/binding are local. `with` / `as` bind an object; `render ... for ...` also provides `forloop` metadata. Includes are disabled inside rendered partials. Absolute names and `..` path components are rejected.

## Errors and limits

Invalid delimiters, expressions, tags or nesting throw `TemplateSyntaxError` during initialization, including errors inside unselected branches. Invalid argument counts, strict unknown filters, division by zero and exceeded limits throw `TemplateRenderError` during rendering. Partials are parsed on first use, so their syntax errors surface during rendering. Custom filter errors propagate to the caller.

The default limit is 100,000 total loop iterations per render and 100,000 entries per range. Configure it with `try Template(source, iterationLimit: 10_000)`. The iteration budget is shared across all partials, including isolated renders. Template nesting is limited to 128 parse levels and partial nesting to 64 calls. These are safeguards, not a complete sandbox or an output size limit.

### Liquid compatibility

**This is a partial Liquid implementation, not a fully conformant replacement for Shopify's reference engine.** The pinned official [Shopify/liquid-spec](https://github.com/Shopify/liquid-spec) suites are now exercised directly through a Swift JSON-RPC adapter, with exact known failures and a passing-inventory regression gate.

The current measured profile executes **4,304 checks: 2,391 pass and 1,913 remain known failures**, up from 1,532 passing checks with no previously passing spec regressed. These counts include seven duplicate-name executions in the upstream profile. See [Compatibility](Compatibility/README.md) for the pinned revision, exclusions, category breakdown and reproducible commands. A green regression gate does **not** mean all official checks pass.

| Area | Current coverage / remaining gaps |
| --- | --- |
| Output, variables, conditions, loops | Features listed above are implemented and tested, including nested blocks. |
| Standard tags and filters | Features and built-ins listed above are implemented and tested; malformed-input and edge-case parity is still incomplete. |
| Strict parser | Error messages/locations differ from the reference; the pinned error suite also identifies invalid syntax still accepted. Each discrepancy is tracked. |
| Values and ordering | Numeric storage uses `Double`. Hash rendering, `first`, and iteration use sorted keys rather than Ruby insertion order; typed host ranges and some host-object semantics differ. |
| Host integration | Partials support explicit strings, not filesystem callbacks/template factories. Names are case-sensitive and traversal paths are rejected, unlike some upstream mock filesystem fixtures. Arbitrary Drops/Swift reflection and Shopify commerce extensions are unsupported. |

Reference: [official Liquid tags](https://github.com/Shopify/liquid/tree/main/lib/liquid/tags) and [standard filters](https://github.com/Shopify/liquid/blob/main/lib/liquid/standardfilters.rb). `strip_html` removes tags; it is not an HTML sanitizer.

## Server-rendered example

[Examples/ServerRender](Examples/ServerRender) is an independent Hummingbird HTTP application with a bundled Liquid template. It demonstrates query parameters, filtered product lists, empty states, conditions, HTML escaping and request isolation. The core Liquid package remains dependency-free.

The example requires **Swift 6.4+** and **Linux or macOS 14+**, using Hummingbird 2.28.0 with locked dependencies. The core library still requires only Swift 6.0+.

```sh
swift run --package-path Examples/ServerRender LiquidServer
# Open http://127.0.0.1:8080/
# Try /?name=Ada&category=tea or /?empty=1
```

Override `HOST` / `PORT` if needed. See the [example README](Examples/ServerRender/README.md) for architecture and HTTP smoke checks.

## Migrating from the Swift 4 prototype

Use `try Template(source)` and `try template.render(variables)` as the main API. `Context(dictionary:)` is now public. Low-level `TokenParser.parse`, `parse(_:)` and `compileFilter` now require `try`; missing variables no longer crash. Unexpected tags and malformed delimiters now throw instead of being silently discarded. SwiftPM discovers tests automatically; the old manual Linux test aggregator is removed.

Compared with the initial Swift 6 prototype, reference compatibility changes unknown filters to pass-through by default (`strictFilters: true` restores errors), preserves raw-block whitespace and explicit date offsets, supports blank output expressions/trailing filter commas, reads counter variables, and uses floating-point division if either operand is decimal.

## Development

```sh
swift test --parallel
swift build -c release -Xswiftc -warnings-as-errors
```

CI tests the core library on Linux with Swift 6.0 and the latest stable official Swift image, plus macOS 26 with the official Swift 6.4.1 toolchain. It also builds the standalone HTTP example and runs its real HTTP smoke checks on Linux (latest Swift) and macOS.

The official compatibility regression gate runs on Linux and macOS and uploads the full JSON reports. Ruby/Bundler dependencies are isolated in `Compatibility/`; they are not dependencies of the Swift library.

## Liquid documentation

- [English](https://shopify.github.io/liquid/)
- [Chinese](https://liquid.bootcss.com/)
