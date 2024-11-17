const std = @import("std");
const jetzig = @import("jetzig");

pub fn post(request: *jetzig.Request) !jetzig.View {
    const Params = struct {
        // Required param - `expectParams` returns `null` if not present:
        name: []const u8,
        // Enum params are converted from string, `expectParams` returns `null` if no match:
        favorite_animal: enum { cat, dog, raccoon },
        // Optional params are not required. Numbers are coerced from strings. `expectParams`
        // returns `null` if a type coercion fails.
        age: ?u8 = 100,
    };
    const params = try request.expectParams(Params) orelse {
        // Inspect information about the failed params with `request.paramsInfo()`:
        // std.debug.print("{?}\n", .{try request.paramsInfo()});
        return request.fail(.unprocessable_entity);
    };

    var root = try request.data(.object);
    try root.put("info", params);

    return request.render(.created);
}

test "post query params" {
    var app = try jetzig.testing.app(std.testing.allocator, @import("routes"));
    defer app.deinit();

    const response1 = try app.request(.POST, "/params", .{
        .params = .{
            .name = "Bob",
            .favorite_animal = "raccoon",
        },
    });
    try response1.expectStatus(.created);

    const response2 = try app.request(.POST, "/params", .{
        .params = .{
            .name = "Bob",
            .favorite_animal = "platypus",
        },
    });
    try response2.expectStatus(.unprocessable_entity);
}

test "post json" {
    var app = try jetzig.testing.app(std.testing.allocator, @import("routes"));
    defer app.deinit();

    const response1 = try app.request(.POST, "/params", .{
        .json = .{
            .name = "Bob",
            .favorite_animal = "raccoon",
        },
    });
    try response1.expectJson("$.info.name", "Bob");
    try response1.expectJson("$.info.favorite_animal", "raccoon");
    try response1.expectJson("$.info.age", 100);

    const response2 = try app.request(.POST, "/params", .{
        .json = .{
            .name = "Hercules",
            .favorite_animal = "cat",
            .age = 11,
        },
    });
    try response2.expectJson("$.info.name", "Hercules");
    try response2.expectJson("$.info.favorite_animal", "cat");
    try response2.expectJson("$.info.age", 11);

    const response3 = try app.request(.POST, "/params", .{
        .json = .{
            .name = "Hercules",
            .favorite_animal = "platypus",
            .age = 11,
        },
    });
    try response3.expectStatus(.unprocessable_entity);
}
