const std = @import("std");
const jetzig = @import("../../jetzig.zig");

const Self = @This();

/// Initialize htmx middleware.
pub fn init(request: *jetzig.http.Request) !*Self {
    const middleware = try request.allocator.create(Self);
    return middleware;
}

/// Detects the `HX-Request` header and, if present, disables the default layout for the current
/// request. This allows a view to specify a layout that will render the full page when the
/// request doesn't come via htmx and, when the request does come from htmx, only return the
/// content rendered directly by the view function.
pub fn afterRequest(self: *Self, request: *jetzig.http.Request) !void {
    _ = self;
    if (request.getHeader("HX-Target")) |target| {
        request.server.logger.debug(
            "[middleware-htmx] htmx request detected, disabling layout. (#{s})",
            .{target},
        );
        request.setLayout(null);
    }
}

/// If a redirect was issued during request processing, reset any response data, set response
/// status to `200 OK` and replace the `Location` header with a `HX-Redirect` header.
pub fn beforeResponse(self: *Self, request: *jetzig.http.Request, response: *jetzig.http.Response) !void {
    _ = self;
    if (response.status_code != .moved_permanently and response.status_code != .found) return;
    if (request.headers.getFirstValue("HX-Request") == null) return;

    if (response.headers.getFirstValue("Location")) |location| {
        response.headers.remove("Location");
        response.status_code = .ok;
        request.response_data.reset();
        try response.headers.append("HX-Redirect", location);
    }
}

/// Clean up the allocated htmx middleware.
pub fn deinit(self: *Self, request: *jetzig.http.Request) void {
    request.allocator.destroy(self);
}
