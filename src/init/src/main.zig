const std = @import("std");

pub const jetzig = @import("jetzig");
pub const templates = @import("app/views/zmpl.manifest.zig").templates;
pub const routes = @import("app/views/routes.zig").routes;

pub fn main() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer std.debug.assert(gpa.deinit() == .ok);
    const allocator = gpa.allocator();

    const app = try jetzig.init(allocator);
    defer app.deinit();

    try app.start(
        comptime jetzig.route(routes),
        comptime jetzig.loadTemplates(templates),
    );
}
