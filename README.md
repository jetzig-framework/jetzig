# :airplane::lizard: Jetzig

_Jetzig_ is a web framework written in [Zig](https://ziglang.org) :lizard:.

The framework is under active development and is currently in an alpha state.

_Jetzig_ aims to provide a rich set of user-friendly tools for building modern web applications quickly. See the checklist below.

If you are interested in _Jetzig_ you will probably find these tools interesting too:

* [Zap](https://github.com/zigzap/zap)
* [http.zig](https://github.com/karlseguin/http.zig)

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
* :x: Headers (available but not yet wrapped).
* :x: Param/JSON payload parsing/abstracting.
* :x: Development-mode responses for debugging.
* :x: Environment configurations (develompent/production/etc.)
* :x: Middleware extensions (for e.g. authentication).
* :x: Email delivery.
* :x: Custom/dynamic routes.
* :x: General-purpose cache.
* :x: Background jobs.
* :x: Testing helpers for testing HTTP requests/responses.
* :x: Development server auto-reload.
* :x: Database integration.
* :x: Email receipt (via SendGrid/AWS SES/etc.)

## LICENSE

[MIT](LICENSE)
