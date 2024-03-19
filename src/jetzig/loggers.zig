const std = @import("std");

const Self = @This();

pub const DevelopmentLogger = @import("loggers/DevelopmentLogger.zig");

pub const LogLevel = enum { TRACE, DEBUG, INFO, WARN, ERROR, FATAL };

pub const Logger = union(enum) {
    development_logger: DevelopmentLogger,

    pub fn isColorized(self: Logger) bool {
        switch (self) {
            inline else => |logger| return logger.isColorized(),
        }
    }

    /// Log a TRACE level message to the configured logger.
    pub fn TRACE(self: *const Logger, comptime message: []const u8, args: anytype) !void {
        switch (self.*) {
            inline else => |*logger| try logger.TRACE(message, args),
        }
    }

    /// Log a DEBUG level message to the configured logger.
    pub fn DEBUG(self: *const Logger, comptime message: []const u8, args: anytype) !void {
        switch (self.*) {
            inline else => |*logger| try logger.DEBUG(message, args),
        }
    }

    /// Log an INFO level message to the configured logger.
    pub fn INFO(self: *const Logger, comptime message: []const u8, args: anytype) !void {
        switch (self.*) {
            inline else => |*logger| try logger.INFO(message, args),
        }
    }

    /// Log a WARN level message to the configured logger.
    pub fn WARN(self: *const Logger, comptime message: []const u8, args: anytype) !void {
        switch (self.*) {
            inline else => |*logger| try logger.WARN(message, args),
        }
    }

    /// Log an ERROR level message to the configured logger.
    pub fn ERROR(self: *const Logger, comptime message: []const u8, args: anytype) !void {
        switch (self.*) {
            inline else => |*logger| try logger.ERROR(message, args),
        }
    }

    /// Log a FATAL level message to the configured logger.
    pub fn FATAL(self: *const Logger, comptime message: []const u8, args: anytype) !void {
        switch (self.*) {
            inline else => |*logger| try logger.FATAL(message, args),
        }
    }
};
