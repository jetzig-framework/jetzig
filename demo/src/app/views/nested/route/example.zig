const std = @import("std");
const jetzig = @import("jetzig");

pub fn index(request: *jetzig.Request, data: *jetzig.Data) !jetzig.View {
    _ = data;
    return request.render(.ok);
}

pub const static_params = .{
    .get = .{
        .{ .id = "foo", .params = .{ .foo = "bar" } },
        .{ .id = "foo" },
    },
};

pub fn get(id: []const u8, request: *jetzig.StaticRequest, data: *jetzig.Data) !jetzig.View {
    var object = try data.object();
    try object.put("id", data.string(id));
    const params = try request.params();
    if (params.get("foo")) |value| try object.put("foo", value);
    return request.render(.ok);
}
