const std = @import("std");

const Self = @This();

pub const DevelopmentLogger = @import("loggers/DevelopmentLogger.zig");

const LogLevel = enum {
    debug,
};

pub const Logger = union(enum) {
    development_logger: DevelopmentLogger,

    pub fn debug(self: *Logger, comptime message: []const u8, args: anytype) void {
        switch (self.*) {
            inline else => |*case| case.debug(message, args) catch |err| {
                std.debug.print("{}\n", .{err});
            },
        }
    }
};
