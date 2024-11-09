const std = @import("std");

const jetzig = @import("../jetzig.zig");

pub const adapter = @field(jetzig.jetquery.config.database, @tagName(jetzig.environment)).adapter;
pub const Schema = jetzig.config.get(type, "Schema");
pub const Repo = jetzig.jetquery.Repo(adapter, Schema);

pub fn Query(comptime model: anytype) type {
    return jetzig.jetquery.Query(adapter, Schema, model);
}

pub fn repo(allocator: std.mem.Allocator, app: anytype) !Repo {
    // XXX: Is this terrible ?
    const Callback = struct {
        var jetzig_app: @TypeOf(app) = undefined;
        pub fn callbackFn(event: jetzig.jetquery.events.Event) !void {
            try eventCallback(event, jetzig_app);
        }
    };
    Callback.jetzig_app = app;

    return try Repo.loadConfig(
        allocator,
        std.enums.nameCast(jetzig.jetquery.Environment, jetzig.environment),
        .{
            .eventCallback = Callback.callbackFn,
            .lazy_connect = jetzig.environment == .development,
        },
    );
}

fn eventCallback(event: jetzig.jetquery.events.Event, app: anytype) !void {
    try app.server.logger.logSql(event);
    if (event.err) |err| {
        try app.server.logger.ERROR("[database] {?s}", .{err.message});
    }
}
