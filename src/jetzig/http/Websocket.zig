const std = @import("std");

const jetzig = @import("../../jetzig.zig");

const httpz = @import("httpz");

pub const Context = struct {
    allocator: std.mem.Allocator,
    route: jetzig.channels.Route,
    session_id: []const u8,
    channels: *jetzig.kv.Store.ChannelStore,
};

const Websocket = @This();

allocator: std.mem.Allocator,
connection: *httpz.websocket.Conn,
channels: *jetzig.kv.Store.ChannelStore,
route: jetzig.channels.Route,
data: *jetzig.Data,
session_id: []const u8,

pub fn init(connection: *httpz.websocket.Conn, context: Context) !Websocket {
    const data = try context.allocator.create(jetzig.Data);
    data.* = jetzig.Data.init(context.allocator);

    return Websocket{
        .allocator = context.allocator,
        .connection = connection,
        .route = context.route,
        .session_id = context.session_id,
        .channels = context.channels,
        .data = data,
    };
}

pub fn afterInit(websocket: *Websocket, context: Context) !void {
    _ = context;

    const func = websocket.route.openConnectionFn orelse return;

    const channel = jetzig.channels.Channel{
        .allocator = websocket.allocator,
        .websocket = websocket,
        .state = try websocket.getState(),
        .data = websocket.data,
    };
    try func(channel);
}

pub fn clientMessage(websocket: *Websocket, allocator: std.mem.Allocator, data: []const u8) !void {
    const channel = jetzig.channels.Channel{
        .allocator = allocator,
        .websocket = websocket,
        .state = try websocket.getState(),
        .data = websocket.data,
    };
    const message = jetzig.channels.Message.init(allocator, channel, data);

    try websocket.route.receiveMessage(message);
}

pub fn syncState(websocket: *Websocket, channel: jetzig.channels.Channel) !void {
    var stack_fallback = std.heap.stackFallback(4096, channel.allocator);
    const allocator = stack_fallback.get();

    var write_buffer = channel.websocket.connection.writeBuffer(allocator, .text);
    defer write_buffer.deinit();

    const writer = write_buffer.writer();

    // TODO: Make this really fast.
    try websocket.channels.put(websocket.session_id, channel.state);
    try writer.print("__jetzig_channel_state__:{s}", .{try websocket.data.toJson()});
    try write_buffer.flush();
}

pub fn getState(websocket: *Websocket) !*jetzig.data.Value {
    return try websocket.channels.get(websocket.data, websocket.session_id) orelse blk: {
        const root = try websocket.data.root(.object);
        try websocket.channels.put(websocket.session_id, root);
        break :blk try websocket.channels.get(websocket.data, websocket.session_id) orelse error.JetzigInvalidChannel;
    };
}
