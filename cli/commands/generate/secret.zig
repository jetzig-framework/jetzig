const std = @import("std");

/// Generate a secure random secret and output to stdout.
pub fn run(allocator: std.mem.Allocator, cwd: std.fs.Dir, args: [][]const u8) !void {
    _ = allocator;
    _ = args;
    _ = cwd;
    const chars = "abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789";
    var secret: [44]u8 = undefined;

    for (0..44) |index| {
        secret[index] = chars[std.crypto.random.intRangeAtMost(u8, 0, chars.len)];
    }

    std.debug.print("{s}\n", .{secret});
}
