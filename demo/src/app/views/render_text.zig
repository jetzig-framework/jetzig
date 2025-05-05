const std = @import("std");
const jetzig = @import("jetzig");

pub fn index(request: *jetzig.Request) !jetzig.View {
    request.response.content_type = "text/xml";
    return request.renderText("<foo><bar>baz</bar></foo>", .ok);
}

test "index" {
    var app = try jetzig.testing.app(std.testing.allocator, @import("routes"));
    defer app.deinit();

    const response = try app.request(.GET, "/render_text", .{});
    try response.expectStatus(.ok);
    try response.expectBodyContains("<foo><bar>baz</bar></foo>");
    try response.expectHeader("content-type", "text/xml");
}
