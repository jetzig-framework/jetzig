const std = @import("std");

const jetzig = @import("../../jetzig.zig");

const Message = @This();

allocator: std.mem.Allocator,
payload: []const u8,
data: *jetzig.data.Data,
channel: jetzig.channels.Channel,

pub fn init(
    allocator: std.mem.Allocator,
    channel: jetzig.channels.Channel,
    payload: []const u8,
) Message {
    return .{
        .allocator = allocator,
        .channel = channel,
        .data = channel.data,
        .payload = payload,
    };
}

pub fn params(message: Message) !?*jetzig.data.Value {
    var d = try message.allocator.create(jetzig.data.Data);
    d.* = jetzig.data.Data.init(message.allocator);
    d.fromJson(message.payload) catch |err| {
        switch (err) {
            error.SyntaxError => {
                message.channel.websocket.logger.ERROR("Invalid JSON received in Channel message.", .{}) catch {};
            },
            else => {
                message.channel.websocket.logger.logError(@errorReturnTrace(), err) catch {};
            },
        }
        return null;
    };
    return d.value;
}

test "message with payload" {
    const message = Message.init(
        std.testing.allocator,
        jetzig.channels.Channel{
            .websocket = undefined,
            .state = undefined,
            .allocator = undefined,
            .data = undefined,
        },
        "foo",
    );
    try std.testing.expectEqualStrings(message.payload, "foo");
}
