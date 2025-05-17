const std = @import("std");
const jetzig = @import("jetzig");

pub fn index(request: *jetzig.Request) !jetzig.View {
    var root = try request.data(.object);
    try root.put("message", try request.cache.get("message"));

    return request.render(.ok);
}

pub fn post(request: *jetzig.Request) !jetzig.View {
    var root = try request.data(.object);

    const params = try request.params();

    if (params.get("message")) |message| {
        try request.cache.put("message", message);
        try root.put("message", message);
    } else {
        try root.put("message", "[no message param detected]");
    }

    return request.render(.ok);
}

test "index" {
    var app = try jetzig.testing.app(std.testing.allocator, @import("routes"));
    defer app.deinit();

    _ = try app.request(.POST, "/cache", .{ .params = .{ .message = "test message" } });

    const response = try app.request(.GET, "/cache", .{});
    try response.expectBodyContains(
        \\  <span>Cached value: test message</span>
    );
}
