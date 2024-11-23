const std = @import("std");
const jetzig = @import("jetzig");

pub fn index(request: *jetzig.Request) !jetzig.View {
    return request.renderTemplate("basic/index", .ok);
}

test "index" {
    var app = try jetzig.testing.app(std.testing.allocator, @import("routes"));
    defer app.deinit();

    const response = try app.request(.GET, "/render_template", .{});
    try response.expectStatus(.ok);
    try response.expectBodyContains("Hello");
}
