const std = @import("std");

const httpz = @import("httpz");
const jetzig = @import("../../jetzig.zig");

allocator: std.mem.Allocator,
websocket_client: *httpz.websocket.Client,

const WebsocketClient = @This();

pub fn init(allocator: std.mem.Allocator, options: struct {}) !WebsocketClient {
    _ = options;
    const client = try allocator.create(httpz.websocket.Client);
    client.* = try httpz.websocket.Client.init(allocator, .{
        .port = 9224,
        .host = "localhost",
    });

    return .{
        .allocator = allocator,
        .websocket_client = client,
    };
}

pub fn deinit(self: WebsocketClient) void {
    self.websocket_client.deinit();
}

pub fn handshake(self: WebsocketClient) !void {
    try self.websocket_client.handshake("/ws", .{
        .timeout_ms = 1000,
        .headers = "Host: localhost:9224", // TODO: Auth header ?
    });
}

pub fn broadcast(self: WebsocketClient, message: []const u8) !void {
    try self.websocket_client.write(@constCast(message));
}
