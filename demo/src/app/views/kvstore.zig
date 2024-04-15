const jetzig = @import("jetzig");

/// This example demonstrates usage of Jetzig's KV store.
pub fn index(request: *jetzig.Request, data: *jetzig.Data) !jetzig.View {
    var root = try data.object();

    // Fetch a string from the KV store. If it exists, store it in the root data object,
    // otherwise store a string value to be picked up by the next request.
    if (request.kvGet(.string, "example-key")) |capture| {
        try root.put("stored_string", data.string(capture));
    } else {
        try request.kvPut(.string, "example-key", "example-value");
    }

    // Pop an item from the array and store it in the root data object. This will empty the
    // array after multiple requests.
    if (request.kvPop("example-array")) |string| try root.put("popped", data.string(string));

    // Fetch an array from the KV store. If it exists, store its values in the root data object,
    // otherwise store a new array to be picked up by the next request.
    if (request.kvGet(.array, "example-array")) |kv_array| {
        var array = try data.array();
        for (kv_array.items()) |item| try array.append(data.string(item));
        try root.put("stored_array", array);
    } else {
        // Create a KV Array and store it in the key value store.
        var kv_array = request.kvArray();
        try kv_array.append("hello");
        try kv_array.append("goodbye");
        try kv_array.append("hello again");
        try request.kvPut(.array, "example-array", kv_array);
    }

    return request.render(.ok);
}
