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

pub fn repo(allocator: std.mem.Allocator, maybe_options: ?DatabaseOptions) !jetzig.jetquery.Repo {
    const options = maybe_options orelse return try jetzig.jetquery.Repo.init(
        allocator,
        .{ .adapter = .null },
    );

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
                    },
                },
            },
        ),
    };
}
