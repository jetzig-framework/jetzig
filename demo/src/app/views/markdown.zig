const std = @import("std");
const jetzig = @import("jetzig");

pub const layout = "application";

pub fn index(request: *jetzig.Request) !jetzig.View {
    return request.render(.ok);
}

test "index" {
    var app = try jetzig.testing.app(std.testing.allocator, @import("routes"));
    defer app.deinit();
    const response = try app.request(.GET, "/markdown", .{});
    try response.expectBodyContains("You can still use <i>Zmpl</i> references, modes, and partials.");
}
