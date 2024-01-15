const std = @import("std");

const Self = @This();
const Timestamp = @import("../types/Timestamp.zig");

allocator: std.mem.Allocator,

pub fn init(allocator: std.mem.Allocator) Self {
    return .{ .allocator = allocator };
}

pub fn debug(self: *Self, comptime message: []const u8, args: anytype) !void {
    const output = try std.fmt.allocPrint(self.allocator, message, args);
    defer self.allocator.free(output);
    const timestamp = Timestamp.init(std.time.timestamp(), self.allocator);
    const iso8601 = try timestamp.iso8601();
    defer self.allocator.free(iso8601);
    std.debug.print("[{s}] {s}\n", .{ iso8601, output });
}
