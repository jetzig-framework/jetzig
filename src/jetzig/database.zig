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

pub const Schema = jetzig.config.get(type, "Schema");

pub fn Query(comptime table: jetzig.jetquery.DeclEnum(jetzig.config.get(type, "Schema"))) type {
    return jetzig.jetquery.Query(Schema, table);
}

pub fn repo(allocator: std.mem.Allocator, app: *const jetzig.App) !jetzig.jetquery.Repo {
    // XXX: Is this terrible ?
    const Callback = struct {
        var jetzig_app: *const jetzig.App = undefined;
        pub fn callbackFn(event: jetzig.jetquery.events.Event) !void {
            try eventCallback(event, jetzig_app);
        }
    };
    Callback.jetzig_app = app;

    return try jetzig.jetquery.Repo.loadConfig(
        allocator,
        .{ .eventCallback = Callback.callbackFn, .lazy_connect = true },
    );
}

fn eventCallback(event: jetzig.jetquery.events.Event, app: *const jetzig.App) !void {
    try app.server.logger.INFO("[database] {?s}", .{event.sql});
    if (event.err) |err| {
        try app.server.logger.ERROR("[database] {?s}", .{err.message});
    }
}
