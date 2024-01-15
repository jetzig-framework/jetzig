const std = @import("std");

const root = @import("root");
const Request = root.jetzig.http.Request;
const Data = root.jetzig.data.Data;
const View = root.jetzig.views.View;

pub fn put(id: []const u8, request: *Request, data: *Data) anyerror!View {
    try request.session.put("option", data.string(id));
    var object = try data.object();
    try object.put("option", data.string(id));

    const count = try request.session.get("count");
    if (count) |value| {
        try request.session.put("count", data.integer(value.integer.value + 1));
        try object.put("count", data.integer(value.integer.value + 1));
    } else {
        try request.session.put("count", data.integer(0));
        try object.put("count", data.integer(0));
    }

    return request.render(.ok);
}

pub fn get(id: []const u8, request: *Request, data: *Data) anyerror!View {
    if (std.mem.eql(u8, id, "latest")) {
        var object = try data.object();
        const count = try request.session.get("count");
        if (count) |value| {
            try object.put("count", data.integer(value.integer.value + 1));
        } else {
            try object.put("count", data.integer(0));
        }
    }
    return request.render(.ok);
}
