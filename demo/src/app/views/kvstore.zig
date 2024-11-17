const std = @import("std");
const jetzig = @import("jetzig");

/// This example demonstrates usage of Jetzig's KV store.
pub fn index(request: *jetzig.Request) !jetzig.View {
    var root = try request.data(.object);

    // Fetch a string from the KV store. If it exists, store it in the root data object,
    // otherwise store a string value to be picked up by the next request.
    if (try request.store.get("example-key")) |capture| {
        try root.put("stored_string", capture);
    } else {
        try root.put("stored_string", null);
        try request.store.put("example-key", "example-value");
    }

    // Left-pop an item from an array and store it in the root data object. This will empty the
    // array after multiple requests.
    // If the array is empty or not found, append some new values to the array.
    if (try request.store.popFirst("example-array")) |value| {
        try root.put("popped", value);
    } else {
        // Store some values in an array in the KV store.
        try request.store.append("example-array", "hello");
        try request.store.append("example-array", "goodbye");
        try request.store.append("example-array", "hello again");

        try root.put("popped", null);
    }

    return request.render(.ok);
}

test "index" {
    var app = try jetzig.testing.app(std.testing.allocator, @import("routes"));
    defer app.deinit();

    const response1 = try app.request(.GET, "/kvstore.json", .{});
    try response1.expectStatus(.ok);
    try response1.expectJson(".stored_string", null);

    const response2 = try app.request(.GET, "/kvstore.json", .{});
    try response2.expectJson(".stored_string", "example-value");
    try response2.expectJson(".popped", "hello");
    try (try app.request(.GET, "/kvstore.json", .{})).expectJson(".popped", "goodbye");
    try (try app.request(.GET, "/kvstore.json", .{})).expectJson(".popped", "hello again");
}
