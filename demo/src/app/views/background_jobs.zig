const jetzig = @import("jetzig");

/// This example demonstrates usage of Jetzig's background jobs.
pub fn index(request: *jetzig.Request, data: *jetzig.Data) !jetzig.View {
    var root = try data.object();

    var job = try request.job();
    try job.put("foo", data.string("bar"));
    try job.background();

    // Fetch a string from the KV store. If it exists, store it in the root data object,
    // otherwise store a string value to be picked up by the next request.
    if (request.kvGet(jetzig.KVString, "example-key")) |capture| {
        try root.put("stored_string", data.string(capture));
    } else {
        try request.kvPut(jetzig.KVString, "example-key", "example-value");
    }

    // Pop an item from the array and store it in the root data object. This will empty the
    // array after multiple requests.
    if (request.kvPop("example-array")) |string| try root.put("popped", data.string(string));

    // Fetch an array from the KV store. If it exists, store its values in the root data object,
    // otherwise store a new array to be picked up by the next request.
    if (request.kvGet(jetzig.KVArray, "example-array")) |kv_array| {
        var array = try data.array();
        for (kv_array.items()) |item| try array.append(data.string(item));
        try root.put("stored_array", array);
    } else {
        // Create a KV Array and store it in the key value store.
        var kv_array = jetzig.KVArray.init(request.allocator);
        try kv_array.append("hello");
        try kv_array.append("goodbye");
        try kv_array.append("hello again");
        try request.kvPut(jetzig.KVArray, "example-array", kv_array);
    }

    return request.render(.ok);
}
