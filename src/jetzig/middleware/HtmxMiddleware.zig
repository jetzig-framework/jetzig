const std = @import("std");
const jetzig = @import("../../jetzig.zig");

const HtmxMiddleware = @This();

/// Detects the `HX-Request` header and, if present, disables the default layout for the current
/// request. This allows a view to specify a layout that will render the full page when the
/// request doesn't come via htmx and, when the request does come from htmx, only return the
/// content rendered directly by the view function.
pub fn afterRequest(request: *jetzig.http.Request) !void {
    if (request.headers.get("HX-Request")) |_| {
        try request.server.logger.DEBUG(
            "[middleware-htmx] HX-Request header, disabling layout.",
            .{},
        );
        request.setLayout(null);
    }
}

/// If a redirect was issued during request processing, reset any response data, set response
/// status to `200 OK` and replace the `Location` header with a `HX-Redirect` header.
pub fn beforeResponse(request: *jetzig.http.Request, response: *jetzig.http.Response) !void {
    switch (response.status_code) {
        .moved_permanently, .found => {},
        else => return,
    }

    if (request.headers.get("HX-Request") == null) return;

    if (response.headers.get("Location")) |location| {
        response.status_code = .ok;
        request.response_data.reset();
        try response.headers.append("HX-Redirect", location);
    }
}
