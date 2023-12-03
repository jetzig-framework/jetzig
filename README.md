# :airplane::lizard: Jetzig

_Jetzig_ is a web framework written in [Zig](https://ziglang.org) :lizard:.

The framework is under active development and is currently in an alpha state.

_Jetzig_ is an ambitious and opinionated web framework. It aims to provide a rich set of user-friendly tools for building modern web applications quickly. See the checklist below.

If you are interested in _Jetzig_ you will probably find these tools interesting too:

* [Zap](https://github.com/zigzap/zap)
* [http.zig](https://github.com/karlseguin/http.zig)

## Checklist

* :white_check_mark: File system-based routing with [slug] matching.
* :white_check_mark: _HTML_ and _JSON_ response (inferred from extension and/or `Accept` header).
* :white_check_mark: _JSON_-compatible response data builder.
* :white_check_mark: _HTML_ templating (see [Zmpl](https://github.com/bobf/zmpl).
* :white_check_mark: Per-request arena allocator.
* :x: Sessions.
* :x: Cookies.
* :x: Headers.
* :x: Development-mode responses for debugging.
* :x: Middleware extensions (for e.g. authentication).
* :x: Email delivery.
* :x: Custom/dynamic routes.
* :x: General-purpose cache.
* :x: Background jobs.
* :x: Database integration.
* :x: Email receipt (via SendGrid/AWS SES/etc.)

## LICENSE

[MIT](LICENSE)
