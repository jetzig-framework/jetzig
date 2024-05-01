const std = @import("std");
const jetzig = @import("jetzig");

pub fn index(request: *jetzig.Request, data: *jetzig.Data) !jetzig.View {
    var root = try data.object();
    try root.put("cached_value", try request.cache.get("example"));

    return request.render(.ok);
}

pub fn post(request: *jetzig.Request, data: *jetzig.Data) !jetzig.View {
    var root = try data.object();

    const params = try request.params();

    if (params.get("message")) |message| {
        try request.cache.put("message", message);
        try root.put("message", message);
    } else {
        try root.put("message", data.string("[no message param detected]"));
    }

    return request.render(.ok);
}
