const std = @import("std");

const jetzig = @import("../../jetzig.zig");

const Channel = @import("Channel.zig");

const Message = @This();

allocator: std.mem.Allocator,
payload: []const u8,
data: *jetzig.data.Data,
channel: Channel,

pub fn init(allocator: std.mem.Allocator, channel: Channel, payload: []const u8) Message {
    return .{
        .allocator = allocator,
        .channel = channel,
        .data = channel.data,
        .payload = payload,
    };
}

pub fn value(message: Message) !*jetzig.data.Value {
    var d = try message.allocator.create(jetzig.data.Data);
    d.* = jetzig.data.Data.init(message.allocator);
    try d.fromJson(message.payload);
    return d.value.?;
}

test "message with payload" {
    const message = Message.init(
        std.testing.allocator,
        Channel{
            .websocket = undefined,
            .state = undefined,
            .allocator = undefined,
            .data = undefined,
        },
        "foo",
    );
    try std.testing.expectEqualStrings(message.payload, "foo");
}
