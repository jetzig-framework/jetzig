const std = @import("std");

const httpz = @import("httpz");

const jetzig = @import("../../jetzig.zig");

const Channel = @This();

websocket: *jetzig.http.Websocket,
state: *jetzig.data.Value,

pub fn publish(self: Channel, data: []const u8) !void {
    try self.connection.write(data);
}

pub fn getT(
    self: Channel,
    comptime T: jetzig.data.Data.ValueType,
    key: []const u8,
) @TypeOf(self.state.getT(T, key)) {
    return self.state.getT(T, key);
}

pub fn get(self: Channel, key: []const u8) ?*jetzig.data.Value {
    return self.state.get(key);
}

pub fn put(self: Channel, key: []const u8, value: anytype) @TypeOf(self.state.put(key, value)) {
    return try self.state.put(key, value);
}

pub fn sync(self: Channel) !void {
    try self.websocket.syncState(self);
}
