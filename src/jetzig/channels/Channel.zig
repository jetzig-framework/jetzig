const std = @import("std");

const httpz = @import("httpz");

const Channel = @This();

connection: *httpz.websocket.Conn,

pub fn publish(self: Channel, data: []const u8) !void {
    try self.connection.write(data);
}
