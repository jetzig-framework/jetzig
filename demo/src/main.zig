const std = @import("std");

pub const jetzig = @import("jetzig");
pub const routes = @import("routes").routes;

// Override default settings in `jetzig.config` here:
pub const jetzig_options = struct {
    /// Middleware chain. Add any custom middleware here, or use middleware provided in
    /// `jetzig.middleware` (e.g. `jetzig.middleware.HtmxMiddleware`).
    pub const middleware: []const type = &.{
        // htmx middleware skips layouts when `HX-Target` header is present and issues
        // `HX-Redirect` instead of a regular HTTP redirect when `request.redirect` is called.
        jetzig.middleware.HtmxMiddleware,
        // Demo middleware included with new projects. Remove once you are familiar with Jetzig's
        // middleware system.
        @import("app/middleware/DemoMiddleware.zig"),
    };

    // Maximum bytes to allow in request body.
    // pub const max_bytes_request_body: usize = std.math.pow(usize, 2, 16);

    // Maximum filesize for `public/` content.
    // pub const max_bytes_public_content: usize = std.math.pow(usize, 2, 20);

    // Maximum filesize for `static/` content (applies only to apps using `jetzig.http.StaticRequest`).
    // pub const max_bytes_static_content: usize = std.math.pow(usize, 2, 18);

    // Path relative to cwd() to serve public content from. Symlinks are not followed.
    // pub const public_content_path = "public";

    // HTTP buffer. Must be large enough to store all headers. This should typically not be modified.
    // pub const http_buffer_size: usize = std.math.pow(usize, 2, 16);
};

pub fn main() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer std.debug.assert(gpa.deinit() == .ok);
    const allocator = gpa.allocator();

    const app = try jetzig.init(allocator);
    defer app.deinit();

    try app.start(comptime jetzig.route(routes));
}
