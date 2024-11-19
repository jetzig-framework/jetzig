const std = @import("std");
const jetzig = @import("jetzig");

pub fn index(request: *jetzig.Request) !jetzig.View {
    return request.render(.ok);
}

pub const static_params = .{
    .get = .{
        .{ .id = "foo", .params = .{ .foo = "bar" } },
        .{ .id = "foo" },
    },
};

pub fn get(id: []const u8, request: *jetzig.StaticRequest) !jetzig.View {
    var object = try request.data(.object);
    try object.put("id", id);
    const params = try request.params();
    if (params.get("foo")) |value| try object.put("foo", value);
    return request.render(.ok);
}
