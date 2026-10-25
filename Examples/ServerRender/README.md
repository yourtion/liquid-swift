# Server-side Liquid rendering

A small product catalogue served by [Hummingbird](https://github.com/hummingbird-project/hummingbird). Each HTTP request renders a bundled `.liquid` file into HTML. No JavaScript or browser-side template engine is needed.

Requires **Swift 6.4+**, **Linux or macOS 14+**. This standalone package uses the local Liquid library and Hummingbird 2.28.0 with locked dependencies; it does not add dependencies to the core library.

From the repository root:

```sh
swift run --package-path Examples/ServerRender LiquidServer
```

Open **http://127.0.0.1:8080/**. Use the form to change your name, select a collection or display an empty collection.

| URL | Demonstration |
| --- | --- |
| `/` | Three product cards, loop indices, availability conditions |
| `/?name=Ada&category=tea` | Query parameters, a filtered list, `case` and escaped output |
| `/?empty=1` | The `for` / `else` empty state |
| `/?name=%3Cscript%3Ealert(1)%3C%2Fscript%3E` | User input displayed as escaped text |
| `/health` | Plain-text `ok` health check |

`HOST` defaults to `127.0.0.1`, and `PORT` to `8080`:

```sh
PORT=9090 swift run --package-path Examples/ServerRender LiquidServer
```

For use inside a container, explicitly set `HOST=0.0.0.0` and publish the desired port. This example is a local demonstration, with no authentication or persistence.

## How rendering works

1. At startup, `PageRenderer` reads `Templates/index.liquid` from `Bundle.module` and parses it once.
2. Hummingbird reads query parameters and passes only strings and booleans into the renderer actor.
3. The actor owns the non-Sendable `Template`. Every request builds a fresh variable dictionary and calls `template.render`, so assignments and loop state cannot leak between visitors.
4. The response contains UTF-8 HTML and `Cache-Control: no-store`. User-controlled text is escaped explicitly in the template; URLs use `url_encode`.

This simple actor serializes template rendering. A larger service could use a pool of isolated renderers. Template files are bundled resources; they are not reloaded on each request, and `include` / `render` tags are not required or implemented by this example.

## Verify real HTTP responses

```sh
swift build --package-path Examples/ServerRender
python3 Examples/ServerRender/smoke_test.py
```

The smoke test starts the compiled server on a free loopback port, checks HTML headers, default and filtered lists, empty states, escaping in text/attributes/URLs, request isolation under concurrent requests, and 404 responses, then shuts down the server. Python 3 is needed only for this check. CI runs it on Linux and macOS.

The supported Liquid syntax and known compatibility gaps are documented in the [root README](../../README.md#liquid-compatibility).
