const std = @import("std");
const jetzig = @import("jetzig");

pub fn index(request: *jetzig.Request, data: *jetzig.Data) !jetzig.View {
    _ = data;
    return request.render(.ok);
}

pub fn post(request: *jetzig.Request, data: *jetzig.Data) !jetzig.View {
    var root = try data.root(.object);

    const params = try request.params();

    if (try request.file("upload")) |file| {
        try root.put("description", params.getT(.string, "description"));
        try root.put("filename", file.filename);
        try root.put("content", file.content);
        try root.put("uploaded", true);
    }

    return request.render(.created);
}

test "index" {
    var app = try jetzig.testing.app(std.testing.allocator, @import("routes"));
    defer app.deinit();

    const response = try app.request(.GET, "/file_upload", .{});
    try response.expectStatus(.ok);
}

test "post" {
    var app = try jetzig.testing.app(std.testing.allocator, @import("routes"));
    defer app.deinit();

    const response = try app.request(.POST, "/file_upload", .{
        .body = app.multipart(.{
            .description = "example description",
            .upload = jetzig.testing.file("example.txt", "example file content"),
        }),
    });

    try response.expectStatus(.created);
    try response.expectBodyContains("example description");
    try response.expectBodyContains("example.txt");
    try response.expectBodyContains("example file content");
}
