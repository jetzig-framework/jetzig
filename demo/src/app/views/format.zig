const std = @import("std");
const jetzig = @import("jetzig");

// Define `pub const formats` to apply constraints to specific view functions. By default, all
// view functions respond to `json` and `html` requests. Use this feature to override those
// defaults.
pub const formats: jetzig.Route.Formats = .{
    .index = &.{ .json, .html },
    .get = &.{.html},
};

pub fn index(request: *jetzig.Request, data: *jetzig.Data) !jetzig.View {
    _ = data;
    return request.render(.ok);
}

pub fn get(id: []const u8, request: *jetzig.Request, data: *jetzig.Data) !jetzig.View {
    _ = data;
    _ = id;
    return request.render(.ok);
}

test "index (json)" {
    var app = try jetzig.testing.app(std.testing.allocator, @import("routes"));
    defer app.deinit();

    const response = try app.request(.GET, "/format.json", .{});
    try response.expectStatus(.ok);
}

test "index (html)" {
    var app = try jetzig.testing.app(std.testing.allocator, @import("routes"));
    defer app.deinit();

    const response = try app.request(.GET, "/format.html", .{});
    try response.expectStatus(.ok);
}

test "get (html)" {
    var app = try jetzig.testing.app(std.testing.allocator, @import("routes"));
    defer app.deinit();

    const response = try app.request(.GET, "/format/example-id.html", .{});
    try response.expectStatus(.ok);
}

test "get (json)" {
    var app = try jetzig.testing.app(std.testing.allocator, @import("routes"));
    defer app.deinit();

    const response = try app.request(.GET, "/format/example-id.json", .{});
    try response.expectStatus(.not_found);
}
