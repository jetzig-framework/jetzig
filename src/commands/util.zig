const std = @import("std");
const colors = @import("jetzig").colors;

const icons = .{
    .check = "✅",
    .cross = "❌",
};

/// Print a success confirmation.
pub fn printSuccess() void {
    std.debug.print(" " ++ icons.check ++ "\n", .{});
}

/// Print a failure confirmation.
pub fn printFailure() void {
    std.debug.print(" " ++ icons.cross ++ "\n", .{});
}

const PrintContext = enum { success, failure };
/// Print some output in with a given context to stderr.
pub fn print(comptime context: PrintContext, comptime message: []const u8, args: anytype) !void {
    const writer = std.io.getStdErr().writer();
    switch (context) {
        .success => try writer.print(
            std.fmt.comptimePrint("{s} {s}\n", .{ icons.check, colors.green(message) }),
            args,
        ),
        .failure => try writer.print(
            std.fmt.comptimePrint("{s} {s}\n", .{ icons.cross, colors.red(message) }),
            args,
        ),
    }
}
