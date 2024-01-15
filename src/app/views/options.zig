const std = @import("std");

const root = @import("root");
const Request = root.jetzig.http.Request;
const Data = root.jetzig.data.Data;
const View = root.jetzig.views.View;

pub fn put(id: []const u8, request: *Request, data: *Data) anyerror!View {
    try request.session.put("option", data.string(id));
    var object = try data.object();
    try object.put("option", data.string(id));
    return request.render(.ok);
}

pub fn get(id: []const u8, request: *Request, data: *Data) anyerror!View {
    if (std.mem.eql(u8, id, "latest")) {
        var object = try data.object();
        var option = try request.session.get("option");
        const latest_option = if (option) |*value| try value.toString() else "...";
        try object.put("option", data.string(latest_option));
    }
    return request.render(.ok);
}
