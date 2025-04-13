const std = @import("std");

const httpz = @import("httpz");

pub const Context = struct {
    allocator: std.mem.Allocator,
};

const Websocket = @This();

connection: *httpz.websocket.Conn,
allocator: std.mem.Allocator,

pub fn init(connection: *httpz.websocket.Conn, context: Context) !Websocket {
    return .{
        .connection = connection,
        .allocator = context.allocator,
    };
}

pub fn clientMessage(self: *Websocket, data: []const u8) !void {
    const message = try std.mem.concat(self.allocator, u8, &.{ "Hello from Jetzig websocket. Your message was: ", data });
    try self.connection.write(message);
}
