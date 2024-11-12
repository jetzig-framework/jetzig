const std = @import("std");

const jetzig = @import("../jetzig.zig");

const Self = @This();

pub const DevelopmentLogger = @import("loggers/DevelopmentLogger.zig");
pub const JsonLogger = @import("loggers/JsonLogger.zig");
pub const TestLogger = @import("loggers/TestLogger.zig");
pub const ProductionLogger = @import("loggers/ProductionLogger.zig");
pub const NullLogger = @import("loggers/NullLogger.zig");

pub const LogQueue = @import("loggers/LogQueue.zig");

pub const LogLevel = enum(u4) { TRACE, DEBUG, INFO, WARN, ERROR, FATAL };
pub const LogFormat = enum { development, production, json, null };

/// Infer a log target (stdout or stderr) from a given log level.
pub inline fn logTarget(comptime level: LogLevel) LogQueue.Target {
    return switch (level) {
        .TRACE, .DEBUG, .INFO => .stdout,
        .WARN, .ERROR, .FATAL => .stderr,
    };
}
pub const Logger = union(enum) {
    development_logger: DevelopmentLogger,
    json_logger: JsonLogger,
    test_logger: TestLogger,
    production_logger: ProductionLogger,
    null_logger: NullLogger,

    /// Log a TRACE level message to the configured logger.
    pub fn TRACE(self: *const Logger, comptime message: []const u8, args: anytype) !void {
        switch (self.*) {
            inline else => |*logger| try logger.log(.TRACE, message, args),
        }
    }

    /// Log a DEBUG level message to the configured logger.
    pub fn DEBUG(self: *const Logger, comptime message: []const u8, args: anytype) !void {
        switch (self.*) {
            inline else => |*logger| try logger.log(.DEBUG, message, args),
        }
    }

    /// Log an INFO level message to the configured logger.
    pub fn INFO(self: *const Logger, comptime message: []const u8, args: anytype) !void {
        switch (self.*) {
            inline else => |*logger| try logger.log(.INFO, message, args),
        }
    }

    /// Log a WARN level message to the configured logger.
    pub fn WARN(self: *const Logger, comptime message: []const u8, args: anytype) !void {
        switch (self.*) {
            inline else => |*logger| try logger.log(.WARN, message, args),
        }
    }

    /// Log an ERROR level message to the configured logger.
    pub fn ERROR(self: *const Logger, comptime message: []const u8, args: anytype) !void {
        switch (self.*) {
            inline else => |*logger| try logger.log(.ERROR, message, args),
        }
    }

    /// Log a FATAL level message to the configured logger.
    pub fn FATAL(self: *const Logger, comptime message: []const u8, args: anytype) !void {
        switch (self.*) {
            inline else => |*logger| try logger.log(.FATAL, message, args),
        }
    }

    pub fn logRequest(self: *const Logger, request: *const jetzig.http.Request) !void {
        switch (self.*) {
            inline else => |*logger| try logger.logRequest(request),
        }
    }

    pub fn logSql(self: *const Logger, request: jetzig.jetquery.events.Event) !void {
        switch (self.*) {
            inline else => |*logger| try logger.logSql(request),
        }
    }

    pub fn logError(self: *const Logger, err: anyerror) !void {
        switch (self.*) {
            inline else => |*logger| try logger.logError(err),
        }
    }

    pub fn log(
        self: *const Logger,
        comptime level: LogLevel,
        comptime message: []const u8,
        args: anytype,
    ) !void {
        switch (self.*) {
            inline else => |*logger| try logger.log(level, message, args),
        }
    }
};
