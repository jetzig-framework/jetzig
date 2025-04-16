const std = @import("std");

const jetzig = @import("../../jetzig.zig");

const httpz = @import("httpz");

pub const Context = struct {
    allocator: std.mem.Allocator,
    server: *const jetzig.http.Server,
};

const Websocket = @This();

allocator: std.mem.Allocator,
connection: *httpz.websocket.Conn,
server: *const jetzig.http.Server,

pub fn init(connection: *httpz.websocket.Conn, context: Context) !Websocket {
    return .{
        .allocator = context.allocator,
        .connection = connection,
        .server = context.server,
    };
}

pub fn clientMessage(self: *Websocket, data: []const u8) !void {
    const channel = jetzig.channels.Channel{ .connection = self.connection };
    const message = jetzig.channels.Message.init(channel, data);

    if (message.channel_name) |target_channel_name| {
        if (self.server.matchChannelRoute(target_channel_name)) |route| {
            try route.receiveMessage(message);
        } else try self.server.logger.WARN("Unrecognized channel: {s}", .{target_channel_name});
    } else try self.server.logger.WARN("Invalid channel message format.", .{});
}
