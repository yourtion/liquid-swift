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

Logical operators evaluate **right to left**, as in Liquid; grouping parentheses are not supported. Parentheses are used only for inclusive ranges such as `(1..count)`. Conditions compare numbers with numbers or strings with strings; they do not coerce strings into numbers. `empty` and `blank` comparisons are supported.

Dictionary loops yield `[key, value]` pairs in sorted key order for deterministic rendering. Loop variables and `forloop` are restored after a loop; other assignments persist in the current context.

## Built-in filters

| Group | Filters |
| --- | --- |
| Math | `abs`, `at_least`, `at_most`, `ceil`, `divided_by`, `floor`, `minus`, `modulo`, `plus`, `round`, `times` |
| String | `append`, `capitalize`, `downcase`, `upcase`, `prepend`, `remove`, `remove_first`, `remove_last`, `replace`, `replace_first`, `replace_last`, `lstrip`, `rstrip`, `strip`, `strip_newlines`, `newline_to_br`, `split`, `slice`, `truncate`, `truncatewords` |
| HTML / URL | `escape`, `escape_once`, `strip_html`, `url_encode`, `url_decode` |
| Collection | `size`, `concat`, `compact`, `first`, `last`, `join`, `map`, `reverse`, `sort`, `sort_natural`, `uniq`, `where` |
| Other | `default`, `date` |

`divided_by` uses integer division when the divisor is an integer and floating-point division for a decimal divisor (`5 | divided_by: 2` → `2`; `5 | divided_by: 2.0` → `2.5`). Numbers use `Double` internally; this is not an arbitrary-precision decimal or financial calculation engine.

`date` accepts Unix timestamps, ISO 8601 strings, common date strings, `now`, and `today`. Formatting uses English names and UTC. Supported directives: `%Y`, `%y`, `%m`, `%d`, `%e`, `%H`, `%I`, `%M`, `%S`, `%p`, `%B`, `%b`, `%h`, `%A`, `%a`, `%j`, `%z`, `%Z`, `%F`, `%T`, `%R`, `%D`, `%s`, `%%`. Unknown directives pass through unchanged.

```swift
let template = try Template("{{ name | greet: '!' }}", filters: [
    "greet": { value, arguments in
        "Hello \(value as? String ?? "")\(arguments.first as? String ?? "")"
    }
])
let output = try template.render(["name": "Ada"]) // Hello Ada!
```

Filters are registered per template and can override built-ins. Arguments are positional; a named argument is delivered as a single `[String: Any]` argument.

## Errors and limits

Invalid delimiters, expressions, tags or nesting throw `TemplateSyntaxError` during initialization, including errors inside unselected branches. Unknown filters, invalid argument counts, division by zero and exceeded loop limits throw `TemplateRenderError` during rendering. Custom filter errors propagate to the caller.

The default limit is 100,000 total loop iterations per render and 100,000 entries per range. Configure it with `try Template(source, iterationLimit: 10_000)`. Template nesting is limited to 128 parse levels. These limits are safeguards for loops and ranges, not a complete sandbox or an output size limit.

This implements the features above, not every Shopify Liquid extension. File loading (`include`, `render`), inheritance, `cycle`, `tablerow`, Shopify-specific objects/filters, and arbitrary Swift object reflection are not implemented. `strip_html` removes tags; it is not an HTML sanitizer.

## Migrating from the Swift 4 prototype

Use `try Template(source)` and `try template.render(variables)` as the main API. `Context(dictionary:)` is now public. Low-level `TokenParser.parse`, `parse(_:)` and `compileFilter` now require `try`; missing variables no longer crash. Unexpected tags and malformed delimiters now throw instead of being silently discarded. SwiftPM discovers tests automatically; the old manual Linux test aggregator is removed.

## Development

```sh
swift test --parallel
swift build -c release -Xswiftc -warnings-as-errors
```

CI tests Linux with Swift 6.0 and the latest stable official Swift image, plus macOS with the runner's Xcode toolchain.

## Liquid documentation

- [English](https://shopify.github.io/liquid/)
- [Chinese](https://liquid.bootcss.com/)
