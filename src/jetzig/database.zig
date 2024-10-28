const std = @import("std");

const jetzig = @import("../jetzig.zig");

pub const Schema = jetzig.config.get(type, "Schema");
pub const adapter = jetzig.jetquery.config.database.adapter;
pub const Repo = jetzig.jetquery.Repo(jetzig.jetquery.config.database.adapter, Schema);

pub fn Query(comptime model: anytype) type {
    return jetzig.jetquery.Query(adapter, Schema, model);
}

pub fn repo(allocator: std.mem.Allocator, app: *const jetzig.App) !Repo {
    // XXX: Is this terrible ?
    const Callback = struct {
        var jetzig_app: *const jetzig.App = undefined;
        pub fn callbackFn(event: jetzig.jetquery.events.Event) !void {
            try eventCallback(event, jetzig_app);
        }
    };
    Callback.jetzig_app = app;

    return try Repo.loadConfig(
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
