const std = @import("std");
const jetzig = @import("jetzig");

const importedFunction = @import("../lib/example.zig").exampleFunction;

pub const layout = "application";

pub fn index(request: *jetzig.Request) !jetzig.View {
    var root = try request.data(.object);
    try root.put("message", "Welcome to Jetzig!");
    try root.put("custom_number", customFunction(100, 200, 300));
    try root.put("imported_number", importedFunction(100, 200, 300));

    try request.response.headers.append("x-example-header", "example header value");

    return request.render(.ok);
}

pub fn edit(id: []const u8, request: *jetzig.Request) !jetzig.View {
    var root = try request.data(.object);
    try root.put("id", id);
    return request.render(.ok);
}

fn customFunction(a: i32, b: i32, c: i32) i32 {
    return a + b + c;
}

test "404 Not Found" {
    var app = try jetzig.testing.app(std.testing.allocator, @import("routes"));
    defer app.deinit();

    const response = try app.request(.GET, "/foobar", .{});
    try response.expectStatus(.not_found);
}

test "200 OK" {
    var app = try jetzig.testing.app(std.testing.allocator, @import("routes"));
    defer app.deinit();

    const response = try app.request(.GET, "/", .{});
    try response.expectStatus(.ok);
}

test "response body" {
    var app = try jetzig.testing.app(std.testing.allocator, @import("routes"));
    defer app.deinit();

    const response = try app.request(.GET, "/", .{});
    try response.expectBodyContains("Welcome to Jetzig!");
}

test "header" {
    var app = try jetzig.testing.app(std.testing.allocator, @import("routes"));
    defer app.deinit();

    const response = try app.request(.GET, "/", .{});
    try response.expectHeader("content-type", "text/html");
}

test "json" {
    var app = try jetzig.testing.app(std.testing.allocator, @import("routes"));
    defer app.deinit();

    const response = try app.request(.GET, "/.json", .{});
    try response.expectJson(".message", "Welcome to Jetzig!");
    try response.expectJson(".custom_number", 600);
}

test "json from header" {
    var app = try jetzig.testing.app(std.testing.allocator, @import("routes"));
    defer app.deinit();

    const response = try app.request(
        .GET,
        "/",
        .{ .headers = .{ .accept = "application/json" } },
    );
    try response.expectJson(".message", "Welcome to Jetzig!");
    try response.expectJson(".custom_number", 600);
}

test "public file" {
    var app = try jetzig.testing.app(std.testing.allocator, @import("routes"));
    defer app.deinit();

    const response = try app.request(.GET, "/jetzig.png", .{});
    try response.expectStatus(.ok);
}
