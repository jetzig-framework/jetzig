/// This example demonstrates static site generation (SSG).
///
/// Any view function that receives `*jetzig.StaticRequest` is considered as a SSG view, which
/// will be invoked at build time and its content (both JSON and HTML) rendered to `static/` in
/// the root project directory.
///
/// Define `pub const static_params` as a struct with fields named after each view function, with
/// the value for each field being an array of structs with fields `params` and, where
/// applicable (i.e. `get`, `put`, `patch`, and `delete`), `id`.
///
/// For each item in the provided array, a separate JSON and HTML output will be generated. At
/// run time, requests are matched to the relevant content by comparing the request params and
/// resource ID to locate the relevant content.
///
/// Launch the demo app and try the following requests:
///
/// ```console
/// curl -H "Accept: application/json" \
///      --data-binary '{"foo":"hello", "bar":"goodbye"}' \
///      --request GET \
///      'http://localhost:8080/static'
/// ```
///
/// ```console
/// curl 'http://localhost:8080/static.html?foo=hi&bar=bye'
/// ```
///
/// ```console
/// curl 'http://localhost:8080/static/123.html?foo=hi&bar=bye'
/// ```
const std = @import("std");
const jetzig = @import("jetzig");

pub const static_params = .{
    .index = .{
        .{ .params = .{ .foo = "hi", .bar = "bye" } },
        .{ .params = .{ .foo = "hello", .bar = "goodbye" } },
    },
    .get = .{
        .{ .id = "123", .params = .{ .foo = "hi", .bar = "bye" } },
        .{ .id = "456", .params = .{ .foo = "hello", .bar = "goodbye" } },
    },
};

pub fn index(request: *jetzig.StaticRequest, data: *jetzig.Data) !jetzig.View {
    var root = try data.root(.object);

    const params = try request.params();

    try root.put("foo", params.get("foo"));
    try root.put("bar", params.get("bar"));

    return request.render(.ok);
}

pub fn get(id: []const u8, request: *jetzig.StaticRequest, data: *jetzig.Data) !jetzig.View {
    var root = try data.root(.object);

    const params = try request.params();

    if (std.mem.eql(u8, id, "123")) {
        try root.put("message", "id is '123'");
    } else {
        try root.put("message", "id is not '123'");
    }

    if (params.get("foo")) |foo| try root.put("foo", foo);
    if (params.get("bar")) |bar| try root.put("bar", bar);

    return request.render(.created);
}

test "index json" {
    var app = try jetzig.testing.app(std.testing.allocator, @import("routes"));
    defer app.deinit();

    const response = try app.request(
        .GET,
        "/static.json",
        .{ .json = .{ .foo = "hello", .bar = "goodbye" } },
    );

    try response.expectStatus(.ok);
    try response.expectJson(".foo", "hello");
    try response.expectJson(".bar", "goodbye");
}

test "get json" {
    var app = try jetzig.testing.app(std.testing.allocator, @import("routes"));
    defer app.deinit();

    const response = try app.request(
        .GET,
        "/static/123.json",
        .{ .json = .{ .foo = "hi", .bar = "bye" } },
    );

    try response.expectStatus(.ok);
    try response.expectJson(".message", "id is '123'");
}

test "index html" {
    var app = try jetzig.testing.app(std.testing.allocator, @import("routes"));
    defer app.deinit();

    const response = try app.request(
        .GET,
        "/static.html",
        .{ .params = .{ .foo = "hello", .bar = "goodbye" } },
    );

    try response.expectStatus(.ok);
    try response.expectBodyContains("foo: hello");
    try response.expectBodyContains("bar: goodbye");
}

test "get html" {
    var app = try jetzig.testing.app(std.testing.allocator, @import("routes"));
    defer app.deinit();

    const response = try app.request(
        .GET,
        "/static/123.html",
        .{ .params = .{ .foo = "hi", .bar = "bye" } },
    );

    try response.expectStatus(.ok);
}
