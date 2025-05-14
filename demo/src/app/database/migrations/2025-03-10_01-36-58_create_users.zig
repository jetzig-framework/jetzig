const std = @import("std");
const jetquery = @import("jetquery");
const t = jetquery.schema.table;
const jetzig = @import("jetzig");

pub fn up(repo: anytype) !void {
    try repo.createTable(
        "users",
        &.{
            t.primaryKey("id", .{}),
            t.column("email", .string, .{ .unique = true, .index = true }),
            t.column("password_hash", .string, .{}),
            t.timestamps(.{}),
        },
        .{},
    );
}

pub fn down(repo: anytype) !void {
    try repo.dropTable("users", .{});
}
