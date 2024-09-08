const std = @import("std");

const jetzig = @import("../jetzig.zig");

pub const DatabaseOptions = struct {
    adapter: enum { postgresql },
    hostname: []const u8,
    port: u16,
    username: []const u8,
    password: []const u8,
    database: []const u8,
};

pub const Schema = jetzig.get(type, "Schema");

pub fn repo(allocator: std.mem.Allocator, maybe_options: ?DatabaseOptions, app: *const jetzig.App) !jetzig.jetquery.Repo {
    const options = maybe_options orelse return try jetzig.jetquery.Repo.init(
        allocator,
        .{ .adapter = .null },
    );

    // XXX: Is this terrible ?
    const Callback = struct {
        var jetzig_app: *const jetzig.App = undefined;
        pub fn callbackFn(event: jetzig.jetquery.events.Event) !void {
            try eventCallback(event, jetzig_app);
        }
    };
    Callback.jetzig_app = app;

    return switch (options.adapter) {
        .postgresql => try jetzig.jetquery.Repo.init(
            allocator,
            .{
                .adapter = .{
                    .postgresql = .{
                        .hostname = options.hostname,
                        .port = options.port,
                        .username = options.username,
                        .password = options.password,
                        .database = options.database,
                        .lazy_connect = @hasField(@import("root"), "database_lazy_connect"),
                    },
                },
                .eventCallback = Callback.callbackFn,
            },
        ),
    };
}

fn eventCallback(event: jetzig.jetquery.events.Event, app: *const jetzig.App) !void {
    try app.server.logger.INFO("[database] {?s}", .{event.sql});
}
