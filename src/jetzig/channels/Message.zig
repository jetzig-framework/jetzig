const std = @import("std");

const jetzig = @import("../../jetzig.zig");

const Channel = @import("Channel.zig");

const Message = @This();

allocator: std.mem.Allocator,
raw_data: []const u8,
channel_name: ?[]const u8,
payload: []const u8,
channel: Channel,

pub fn init(allocator: std.mem.Allocator, channel: Channel, raw_data: []const u8) Message {
    const channel_name = parseChannelName(raw_data);
    const payload = parsePayload(raw_data, channel_name);
    return .{
        .allocator = allocator,
        .raw_data = raw_data,
        .channel = channel,
        .channel_name = channel_name,
        .payload = payload,
    };
}

pub fn data(message: Message) !*jetzig.data.Value {
    var d = try message.allocator.create(jetzig.data.Data);
    d.* = jetzig.data.Data.init(message.allocator);
    try d.fromJson(message.payload);
    return d.value.?;
}

fn parseChannelName(raw_data: []const u8) ?[]const u8 {
    return if (std.mem.indexOfScalar(u8, raw_data, ':')) |index|
        if (index > 1) raw_data[0..index] else null
    else
        null;
}

fn parsePayload(raw_data: []const u8, maybe_channel_name: ?[]const u8) []const u8 {
    return if (maybe_channel_name) |channel_name|
        raw_data[channel_name.len + 1 ..]
    else
        raw_data;
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
