[![CI](https://github.com/jetzig-framework/jetzig/actions/workflows/CI.yml/badge.svg)](https://github.com/jetzig-framework/jetzig/actions/workflows/CI.yml)

![Jetzig Logo](demo/public/jetzig.png)

_Jetzig_ is a web framework written in 100% pure [Zig](https://ziglang.org) :lizard: for _Linux_, _OS X_, _Windows_, and any _OS_ that can compile _Zig_ code.

Official website: [jetzig.dev](https://www.jetzig.dev/)

Please note that _Jetzig_'s `main` branch aims to be compatible with the latest [Zig nightly master build](https://ziglang.org/download/) and older versions of _Zig_ are not supported.

_Jetzig_ aims to provide a rich set of user-friendly tools for building modern web applications quickly. See the checklist below.

Join us on Discord ! [https://discord.gg/eufqssz7X6](https://discord.gg/eufqssz7X6).

If you are interested in _Jetzig_ you will probably find these tools interesting too:

* [Zap](https://github.com/zigzap/zap)
* [http.zig](https://github.com/karlseguin/http.zig) (_Jetzig_'s backend)
* [tokamak](https://github.com/cztomsik/tokamak)
* [zig-router](https://github.com/Cloudef/zig-router)
* [zig-webui](https://github.com/webui-dev/zig-webui/)
* [ZTS](https://github.com/zigster64/zts)
* [Zine](https://github.com/kristoff-it/zine)
* [Zinc](https://github.com/zon-dev/zinc/)
* [zUI](https://github.com/thienpow/zui)

## Checklist

* :white_check_mark: File system-based routing with [slug] matching.
* :white_check_mark: _HTML_ and _JSON_ response (inferred from extension and/or `Accept` header).
* :white_check_mark: _JSON_-compatible response data builder.
* :white_check_mark: _HTML_ templating (see [Zmpl](https://github.com/jetzig-framework/zmpl)).
* :white_check_mark: Per-request arena allocator.
* :white_check_mark: Sessions.
* :white_check_mark: Cookies.
* :white_check_mark: Error handling.
* :white_check_mark: Static content from /public directory.
* :white_check_mark: Request/response headers.
* :white_check_mark: Stack trace output on error.
* :white_check_mark: Static content generation.
* :white_check_mark: Param/JSON payload parsing/abstracting.
* :white_check_mark: Static content parameter definitions.
* :white_check_mark: Middleware interface.
* :white_check_mark: MIME type inference.
* :white_check_mark: Email delivery.
* :white_check_mark: Background jobs.
* :white_check_mark: General-purpose cache.
* :white_check_mark: Development server auto-reload.
* :white_check_mark: Testing helpers for testing HTTP requests/responses.
* :white_check_mark: Custom/non-conventional routes.
* :white_check_mark: Database integration.
* :x: Environment configurations (development/production/etc.)
* :x: Email receipt (via SendGrid/AWS SES/etc.)

## LICENSE

[MIT](LICENSE)

## Contributors

* [Zackary Housend](https://github.com/z1fire)
* [Andreas Stührk](https://github.com/Trundle)
* [Karl Seguin](https://github.com/karlseguin)
* [Bob Farrell](https://github.com/bobf)
