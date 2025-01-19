const std = @import("std");

const Channels = @This();

pub const Channel = struct {
    name: []const u8,

    pub fn deliver(self: Channel, message: []const u8) !void {
        _ = self;
        std.debug.print("message: {s}\n", .{message});
    }
};

allocator: std.mem.Allocator,
channels: std.StringHashMap(Channel),

pub fn init(allocator: std.mem.Allocator) Channels {
    return .{
        .allocator = allocator,
        .channels = std.StringHashMap(Channel).init(allocator),
    };
}

pub fn acquire(self: *Channels, name: []const u8) !Channel {
    const channel = Channel{ .name = name };
    try self.channels.put(name, channel);
}

pub fn broadcast(self: Channels, message: []const u8) !void {
    var it = self.channels.iterator();
    while (it.next()) |entry| {
        try entry.value_ptr.deliver(message);
    }
}
