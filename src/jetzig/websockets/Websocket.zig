const std = @import("std");

const jetzig = @import("../../jetzig.zig");

const httpz = @import("httpz");

pub const Context = struct {
    allocator: std.mem.Allocator,
    route: jetzig.channels.Route,
    session_id: []const u8,
    channels: *jetzig.kv.Store.ChannelStore,
    logger: jetzig.loggers.Logger,
};

pub fn RoutedWebsocket(Routes: type) type {
    return struct {
        allocator: std.mem.Allocator,
        connection: *httpz.websocket.Conn,
        channels: *jetzig.kv.Store.ChannelStore,
        route: jetzig.channels.Route,
        data: *jetzig.Data,
        session_id: []const u8,
        logger: jetzig.loggers.Logger,

        const Websocket = @This();
        const router = jetzig.channels.ActionRouter.initComptime(Routes);

        pub fn init(connection: *httpz.websocket.Conn, context: Context) !Websocket {
            const data = try context.allocator.create(jetzig.Data);
            data.* = jetzig.Data.init(context.allocator);

            return Websocket{
                .allocator = context.allocator,
                .connection = connection,
                .route = context.route,
                .session_id = context.session_id,
                .channels = context.channels,
                .logger = context.logger,
                .data = data,
            };
        }

        pub fn afterInit(websocket: *Websocket, context: Context) !void {
            _ = context;
            if (router.encoded_params.get(websocket.route.path)) |params| {
                var stack_fallback = std.heap.stackFallback(4096, websocket.allocator);
                const allocator = stack_fallback.get();

                var write_buffer = websocket.connection.writeBuffer(allocator, .text);
                defer write_buffer.deinit();

                const writer = write_buffer.writer();
                try writer.print("__jetzig_actions__:{s}", .{params});
                try write_buffer.flush();
            }

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
            const channel = jetzig.channels.RoutedChannel(Routes){
                .allocator = allocator,
                .websocket = websocket,
                .state = try websocket.getState(),
                .data = websocket.data,
            };

            if (websocket.invoke(channel, data)) |maybe_action| {
                if (maybe_action) |action| {
                    websocket.logger.DEBUG(
                        "Invoked Channel Action `{s}:{?s}`",
                        .{ websocket.route.path, action },
                    ) catch {};
                    return;
                }
            } else |err| {
                websocket.logger.logError(@errorReturnTrace(), err) catch {};
                return;
            }

            const message = jetzig.channels.Message.init(allocator, channel, data);

            websocket.route.receiveMessage(message) catch |err| {
                websocket.logger.logError(@errorReturnTrace(), err) catch {};
            };
            websocket.logger.DEBUG("Routed Channel message for `{s}`", .{websocket.route.path}) catch {};
        }

        pub fn syncState(websocket: *Websocket, channel: jetzig.channels.RoutedChannel(Routes)) !void {
            var stack_fallback = std.heap.stackFallback(4096, channel.allocator);
            const allocator = stack_fallback.get();

            var write_buffer = channel.websocket.connection.writeBuffer(allocator, .text);
            defer write_buffer.deinit();

            const writer = write_buffer.writer();

            // TODO: Make this really fast.
            try websocket.channels.put(websocket.session_id, channel.state);
            try writer.print("__jetzig_channel_state__:{s}", .{try websocket.data.toJson()});
            try write_buffer.flush();

            websocket.logger.DEBUG("Synchronized Channel state for `{s}`", .{websocket.route.path}) catch {};
        }

        pub fn getState(websocket: *Websocket) !*jetzig.data.Value {
            return try websocket.channels.get(websocket.data, websocket.session_id) orelse blk: {
                const root = try websocket.data.root(.object);
                try websocket.channels.put(websocket.session_id, root);
                break :blk try websocket.channels.get(websocket.data, websocket.session_id) orelse error.JetzigInvalidChannel;
            };
        }

        fn invoke(
            websocket: *Websocket,
            channel: jetzig.channels.RoutedChannel(Routes),
            data: []const u8,
        ) !?[]const u8 {
            return router.invoke(
                websocket.allocator,
                websocket.route.path,
                data,
                @TypeOf(channel),
                channel,
            );
        }
    };
}
