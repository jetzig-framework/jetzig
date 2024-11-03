const std = @import("std");
const jetzig = @import("jetzig");

pub fn index(request: *jetzig.Request, data: *jetzig.Data) !jetzig.View {
    var root = try data.object();

    const session = try request.session();

    if (try session.get("message")) |message| {
        try root.put("message", message);
    } else {
        try root.put("message", data.string("No message saved yet"));
    }

    return request.render(.ok);
}

pub fn post(request: *jetzig.Request, data: *jetzig.Data) !jetzig.View {
    _ = data;
    const params = try request.params();
    var session = try request.session();

    if (params.get("message")) |message| {
        if (std.mem.eql(u8, message.string.value, "delete")) {
            _ = try session.remove("message");
        } else {
            try session.put("message", message);
        }
    }

    return request.redirect("/session", .moved_permanently);
}
