const std = @import("std");

pub const jetzig = @import("jetzig");
pub const routes = @import("routes").routes;

pub const jetzig_options = struct {
    pub const middleware: []const type = &.{
        // htmx middleware skips layouts when `HX-Target` header is present and issues
        // `HX-Redirect` instead of a regular HTTP redirect when `request.redirect` is called.
        jetzig.middleware.HtmxMiddleware,
        @import("app/middleware/DemoMiddleware.zig"),
    };
};

pub fn main() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer std.debug.assert(gpa.deinit() == .ok);
    const allocator = gpa.allocator();

    const app = try jetzig.init(allocator);
    defer app.deinit();

    try app.start(comptime jetzig.route(routes));
}
