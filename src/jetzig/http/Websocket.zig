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
data: *jetzig.Data,
id: [32]u8 = undefined,

pub fn init(connection: *httpz.websocket.Conn, context: Context) !Websocket {
    var websocket = Websocket{
        .allocator = context.allocator,
        .connection = connection,
        .server = context.server,
        .data = try context.allocator.create(jetzig.Data),
    };
    websocket.data.* = jetzig.Data.init(context.allocator);
    _ = jetzig.util.generateRandomString(&websocket.id);

    return websocket;
}

pub fn clientMessage(self: *Websocket, data: []const u8) !void {
    const channel = jetzig.channels.Channel{
        .websocket = self,
        .state = try self.getState(),
    };
    const message = jetzig.channels.Message.init(self.allocator, channel, data);

    if (message.channel_name) |target_channel_name| {
        if (self.server.matchChannelRoute(target_channel_name)) |route| {
            try route.receiveMessage(message);
        } else try self.server.logger.WARN("Unrecognized channel: {s}", .{target_channel_name});
    } else try self.server.logger.WARN("Invalid channel message format.", .{});
}

pub fn syncState(self: *Websocket, channel: jetzig.channels.Channel) !void {
    // TODO: Make this really fast.
    try self.server.channels.put(&self.id, channel.state);
    try self.connection.write(try self.data.toJson());
}

fn getState(self: *Websocket) !*jetzig.data.Value {
    return try self.server.channels.get(self.data, &self.id) orelse blk: {
        const root = try self.data.root(.object);
        try self.server.channels.put(&self.id, root);
        break :blk try self.server.channels.get(self.data, &self.id) orelse error.JetzigInvalidChannel;
    };
}
