const std = @import("std");

const Channel = @import("Channel.zig");

const Message = @This();

data: []const u8,
channel_name: ?[]const u8,
payload: []const u8,
channel: Channel,

pub fn init(channel: Channel, data: []const u8) Message {
    const channel_name = parseChannelName(data);
    const payload = parsePayload(data, channel_name);
    return .{ .data = data, .channel = channel, .channel_name = channel_name, .payload = payload };
}

fn parseChannelName(data: []const u8) ?[]const u8 {
    return if (std.mem.indexOfScalar(u8, data, ':')) |index|
        if (index > 1) data[0..index] else null
    else
        null;
}

fn parsePayload(data: []const u8, maybe_channel_name: ?[]const u8) []const u8 {
    return if (maybe_channel_name) |channel_name|
        data[channel_name.len + 1 ..]
    else
        data;
}

test "message with channel and payload" {
    const message = Message.init("foo:bar");
    try std.testing.expectEqualStrings(message.channel_name.?, "foo");
    try std.testing.expectEqualStrings(message.payload, "bar");
}

test "message with payload only" {
    const message = Message.init("bar");
    try std.testing.expectEqual(message.channel_name, null);
    try std.testing.expectEqualStrings(message.payload, "bar");
}
