const std = @import("std");

const httpz = @import("httpz");

const jetzig = @import("../../jetzig.zig");

pub fn RoutedChannel(Routes: type) type {
    return struct {
        const Channel = @This();

        allocator: std.mem.Allocator,
        websocket: *jetzig.websockets.RoutedWebsocket(Routes),
        state: *jetzig.data.Value,
        data: *jetzig.data.Data,

        pub fn publish(channel: Channel, data: anytype) !void {
            var stack_fallback = std.heap.stackFallback(4096, channel.allocator);
            const allocator = stack_fallback.get();

            var write_buffer = channel.websocket.connection.writeBuffer(allocator, .text);
            defer write_buffer.deinit();

            const writer = write_buffer.writer();
            try std.json.stringify(data, .{}, writer);
            try write_buffer.flush();
        }

        pub fn getT(
            channel: Channel,
            comptime T: jetzig.data.Data.ValueType,
            key: []const u8,
        ) @TypeOf(channel.state.getT(T, key)) {
            return channel.state.getT(T, key);
        }

        pub fn get(channel: Channel, key: []const u8) ?*jetzig.data.Value {
            return channel.state.get(key);
        }

        pub fn put(
            channel: Channel,
            key: []const u8,
            value: anytype,
        ) @TypeOf(channel.state.put(key, value)) {
            return try channel.state.put(key, value);
        }

        pub fn sync(channel: Channel) !void {
            try channel.websocket.syncState(channel);
        }
    };
}
