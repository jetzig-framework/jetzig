const std = @import("std");
const jetzig = @import("../../jetzig.zig");

pub const middleware_name = "hot_reload";

const HotReloadMiddleware = @This();

pub fn afterRequest(request: *jetzig.http.Request) !void {
    var session = try request.session();
    try session.put("_jetzig_hot_reload", "test");
}

pub fn afterLaunch(server: *jetzig.http.Server) !void {
    try server.logger.INFO("LAUNCH", .{});
    try server.channels.broadcast("jetzig-reload");
}
