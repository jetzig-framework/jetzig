const std = @import("std");
const jetquery = @import("jetquery");

pub fn run(repo: anytype) !void {
    try repo.insert(
        .User,
        .{
            .email = "iguana@jetzig.dev",
            .password_hash = "not_secure",
        },
    );

    try repo.insert(
        .User,
        .{
            .email = "admin@jetzig.dev",
            .password_hash = "do_not_use",
        },
    );
}
