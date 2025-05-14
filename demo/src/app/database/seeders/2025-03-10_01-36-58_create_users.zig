const std = @import("std");

const jetzig = @import("jetzig");

pub fn run(repo: anytype) !void {
    try repo.insert(
        .User,
        .{
            .email = "iguana@jetzig.dev",
            .password_hash = try jetzig.auth.hashPassword(repo.allocator, "password"),
        },
    );

    try repo.insert(
        .User,
        .{
            .email = "admin@jetzig.dev",
            .password_hash = try jetzig.auth.hashPassword(repo.allocator, "admin"),
        },
    );
}
