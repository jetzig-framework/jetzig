const std = @import("std");

/// Generate a secure random secret and output to stdout.
pub fn run(allocator: std.mem.Allocator, cwd: std.fs.Dir, args: [][]const u8, help: bool) !void {
    if (help) {
        std.debug.print(
            \\Generate a secure random secret suitable for use as the `JETZIG_SECRET` environment variable.
            \\
        , .{});
        return;
    }

    _ = allocator;
    _ = args;
    _ = cwd;
    const chars = "abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789";
    const len = 128;
    var secret: [len]u8 = undefined;

    for (0..len) |index| {
        secret[index] = chars[std.crypto.random.intRangeAtMost(u8, 0, chars.len - 1)];
    }

    try std.io.getStdOut().writer().print("{s}\n", .{secret});
}
