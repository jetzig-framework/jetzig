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
///      --data-bin '{"foo":"hello", "bar":"goodbye"}' \
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
        .{ .id = "1", .params = .{ .foo = "hi", .bar = "bye" } },
        .{ .id = "2", .params = .{ .foo = "hello", .bar = "goodbye" } },
    },
};

pub fn index(request: *jetzig.StaticRequest, data: *jetzig.Data) !jetzig.View {
    var root = try data.object();

    const params = try request.params();

    if (params.get("foo")) |foo| try root.put("foo", foo);

    return request.render(.ok);
}

pub fn get(id: []const u8, request: *jetzig.StaticRequest, data: *jetzig.Data) !jetzig.View {
    var root = try data.object();

    const params = try request.params();

    if (std.mem.eql(u8, id, "1")) {
        try root.put("id", data.string("id is '1'"));
    }

    if (params.get("foo")) |foo| try root.put("foo", foo);
    if (params.get("bar")) |bar| try root.put("bar", bar);

    return request.render(.created);
}
