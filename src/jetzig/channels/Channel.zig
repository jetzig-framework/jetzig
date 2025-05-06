const std = @import("std");

const httpz = @import("httpz");

const jetzig = @import("../../jetzig.zig");

pub const Env = struct {
    store: *jetzig.kv.Store.GeneralStore,
    cache: *jetzig.kv.Store.CacheStore,
    job_queue: *jetzig.kv.Store.JobQueueStore,
    logger: jetzig.loggers.Logger,
};

pub fn RoutedChannel(Routes: type) type {
    return struct {
        const Channel = @This();

        allocator: std.mem.Allocator,
        websocket: *jetzig.websockets.RoutedWebsocket(Routes),
        root_state: *jetzig.data.Value,
        data: *jetzig.data.Data,
        _connections: *std.StringHashMap(Connection),
        route: jetzig.channels.Route,
        env: Env,
        path: []const u8,
        host: []const u8,

        const Connection = struct {
            state: *jetzig.data.Value,
            key: []const u8,
        };

        pub fn init(allocator: std.mem.Allocator, websocket: *jetzig.websockets.Websocket) !Channel {
            const connections = try allocator.create(std.StringHashMap(Connection));
            connections.* = std.StringHashMap(Connection).init(allocator);

            return .{
                .allocator = allocator,
                .websocket = websocket,
                .root_state = try websocket.getState(),
                .data = websocket.data,
                ._connections = connections,
                .route = websocket.route,
                .path = websocket.path,
                .host = websocket.host,
                .env = .{
                    .store = websocket.store,
                    .cache = websocket.cache,
                    .job_queue = websocket.job_queue,
                    .logger = websocket.logger,
                },
            };
        }

        pub fn publish(channel: Channel, data: anytype) !void {
            var stack_fallback = std.heap.stackFallback(4096, channel.allocator);
            const allocator = stack_fallback.get();

            var write_buffer = channel.websocket.connection.writeBuffer(allocator, .text);
            defer write_buffer.deinit();

            const writer = write_buffer.writer();
            try std.json.stringify(data, .{}, writer);
            try write_buffer.flush();
            channel.env.logger.DEBUG(
                "Published Channel message for `{s}`",
                .{channel.websocket.route.path},
            ) catch {};
        }

        pub fn invoke(
            channel: Channel,
            comptime method: @TypeOf(.enum_literal),
            args: anytype,
        ) !void {
            // TODO: DRY
            var stack_fallback = std.heap.stackFallback(4096, channel.allocator);
            const allocator = stack_fallback.get();

            var write_buffer = channel.websocket.connection.writeBuffer(allocator, .text);
            defer write_buffer.deinit();

            const writer = write_buffer.writer();
            try writer.writeAll("__jetzig_event__:");
            try std.json.stringify(.{ .method = method, .params = args }, .{}, writer);
            try write_buffer.flush();
            channel.env.logger.DEBUG(
                "Invoked Javascript function `{s}` for `{s}`",
                .{ @tagName(method), channel.websocket.route.path },
            ) catch {};
        }

        pub fn state(channel: Channel, comptime scope: []const u8) !*jetzig.data.Value {
            if (channel._connections.get(scope)) |cached| {
                // Ensure an identical value is returned for each invocation of `state` for a
                // given scope.
                return cached.state;
            }

            if (channel.websocket.session_id.len != 32) return error.JetzigInvalidSessionIdLength;

            const connections = channel.get("_connections") orelse try channel.put("_connections", .array);
            const connection_id = for (connections.items(.array)) |connection| {
                if (connection.getT(.string, "scope")) |connection_scope| {
                    if (std.mem.eql(u8, connection_scope, scope)) {
                        break connection.getT(.string, "id") orelse return error.JetzigInvalidChannelState;
                    }
                }
            } else blk: {
                const id = try channel.allocator.alloc(u8, 32);
                _ = jetzig.util.generateRandomString(id);
                try connections.append(.{ .id = id, .scope = scope });
                break :blk id;
            };

            const connection_key = try std.fmt.allocPrint(channel.allocator, "{s}:{s}", .{ channel.websocket.session_id, connection_id });
            const channel_state = try channel.websocket.channels.get(channel.data, connection_key) orelse blk: {
                const channel_state = try channel.data.object();
                // TODO - store this in a way that won't clobber the key with each new state.
                try channel_state.put("__connection_url__", try std.fmt.allocPrint(channel.allocator, "http://{s}{s}?key={s}", .{ channel.host, channel.path, connection_key }));
                try channel.websocket.channels.put(connection_key, channel_state);
                break :blk channel_state;
            };
            try channel._connections.put(scope, .{ .key = connection_key, .state = channel_state });
            return channel_state;
        }

        pub fn connect(channel: Channel, comptime scope: []const u8, session_id: []const u8) !void {
            _ = channel;
            _ = scope;
            _ = session_id;
        }

        pub fn getT(
            channel: Channel,
            comptime T: jetzig.data.Data.ValueType,
            key: []const u8,
        ) @TypeOf(channel.root_state.getT(T, key)) {
            return channel.root_state.getT(T, key);
        }

        pub fn get(channel: Channel, key: []const u8) ?*jetzig.data.Value {
            return channel.root_state.get(key);
        }

        pub fn put(
            channel: Channel,
            key: []const u8,
            value: anytype,
        ) @TypeOf(channel.root_state.put(key, value)) {
            return try channel.root_state.put(key, value);
        }

        pub fn remove(channel: Channel, key: []const u8) bool {
            return channel.root_state.remove(key);
        }

        pub fn sync(channel: Channel) !void {
            try channel.websocket.syncState(channel.root_state, "__root__", channel.websocket.session_id);

            var it = channel._connections.iterator();
            while (it.next()) |entry| {
                const connection = entry.value_ptr.*;
                const scope = entry.key_ptr.*;
                try channel.websocket.syncState(connection.state, scope, connection.key);
            }
        }
    };
}
