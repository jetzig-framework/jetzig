const std = @import("std");

const jetzig = @import("../jetzig.zig");

pub const adapter = std.enums.nameCast(
    jetzig.jetquery.adapters.Name,
    @field(jetzig.jetquery.config.database, @tagName(jetzig.environment)).adapter,
);

pub const Schema = jetzig.config.get(type, "Schema");
pub const Repo = jetzig.jetquery.Repo(adapter, Schema);

pub fn Query(comptime model: anytype) type {
    return jetzig.jetquery.Query(adapter, Schema, model);
}

pub fn repo(allocator: std.mem.Allocator, app: anytype) !Repo {
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
            .lazy_connect = switch (jetzig.environment) {
                .development, .production => true,
                .testing => false,
            },
            // Checking field presence here makes setting up test App a bit simpler.
            .env = if (@hasField(@TypeOf(app), "env")) try repoEnv(app.env) else .{},
        },
    );
}

fn eventCallback(event: jetzig.jetquery.events.Event, app: anytype) !void {
    try app.server.logger.logSql(event);
    if (event.err) |err| {
        try app.server.logger.ERROR("[database] {?s}", .{err.message});
    }
}

pub fn repoEnv(env: jetzig.Environment) !Repo.AdapterOptions {
    return switch (comptime adapter) {
        .null => .{},
        .postgresql => .{
            .hostname = @as(?[]const u8, env.vars.get("JETQUERY_HOSTNAME")),
            .port = @as(?u16, try env.vars.getT(u16, "JETQUERY_PORT")),
            .username = @as(?[]const u8, env.vars.get("JETQUERY_USERNAME")),
            .password = @as(?[]const u8, env.vars.get("JETQUERY_PASSWORD")),
            .database = @as(?[]const u8, env.vars.get("JETQUERY_DATABASE")),
        },
    };
}
