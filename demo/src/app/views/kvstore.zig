const jetzig = @import("jetzig");

/// This example demonstrates usage of Jetzig's KV store.
pub fn index(request: *jetzig.Request, data: *jetzig.Data) !jetzig.View {
    var root = try data.object();

    // Fetch a string from the KV store. If it exists, store it in the root data object,
    // otherwise store a string value to be picked up by the next request.
    if (try request.store.fetchRemove("example-key")) |capture| {
        try root.put("stored_string", capture);
    } else {
        try root.put("stored_string", null);
        try request.store.put("example-key", data.string("example-value"));
    }

    // Left-pop an item from the array and store it in the root data object. This will empty the
    // array after multiple requests.
    if (try request.store.popFirst("example-array")) |value| {
        try root.put("popped", value);
    } else {
        try root.put("popped", null);
        // Store some values in an array in the KV store.
        try request.store.append("example-array", data.string("hello"));
        try request.store.append("example-array", data.string("goodbye"));
        try request.store.append("example-array", data.string("hello again"));
    }

    return request.render(.ok);
}
