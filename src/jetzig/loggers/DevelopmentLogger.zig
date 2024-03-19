const std = @import("std");

const jetzig = @import("../../jetzig.zig");

const Self = @This();

const Timestamp = jetzig.types.Timestamp;
const LogLevel = jetzig.loggers.LogLevel;

allocator: std.mem.Allocator,
file: std.fs.File,
colorized: bool,

pub fn init(allocator: std.mem.Allocator, file: std.fs.File) Self {
    return .{ .allocator = allocator, .file = file, .colorized = file.isTty() };
}

/// Return true if logger was initialized with colorization (i.e. if log file is a tty)
pub fn isColorized(self: Self) bool {
    return self.colorized;
}

/// Log a TRACE level message to the configured logger.
pub fn TRACE(self: *const Self, comptime message: []const u8, args: anytype) !void {
    try self.log(.DEBUG, message, args);
}

/// Log a DEBUG level message to the configured logger.
pub fn DEBUG(self: *const Self, comptime message: []const u8, args: anytype) !void {
    try self.log(.DEBUG, message, args);
}

/// Log an INFO level message to the configured logger.
pub fn INFO(self: *const Self, comptime message: []const u8, args: anytype) !void {
    try self.log(.INFO, message, args);
}

/// Log a WARN level message to the configured logger.
pub fn WARN(self: *const Self, comptime message: []const u8, args: anytype) !void {
    try self.log(.WARN, message, args);
}

/// Log an ERROR level message to the configured logger.
pub fn ERROR(self: *const Self, comptime message: []const u8, args: anytype) !void {
    try self.log(.ERROR, message, args);
}

/// Log a FATAL level message to the configured logger.
pub fn FATAL(self: *const Self, comptime message: []const u8, args: anytype) !void {
    try self.log(.FATAL, message, args);
}

pub fn log(self: Self, comptime level: LogLevel, comptime message: []const u8, args: anytype) !void {
    const output = try std.fmt.allocPrint(self.allocator, message, args);
    defer self.allocator.free(output);
    const timestamp = Timestamp.init(std.time.timestamp(), self.allocator);
    const iso8601 = try timestamp.iso8601();
    defer self.allocator.free(iso8601);
    const writer = self.file.writer();
    const level_formatted = if (self.colorized) colorizedLogLevel(level) else @tagName(level);
    try writer.print("{s: >5} [{s}] {s}\n", .{ level_formatted, iso8601, output });
    if (!self.file.isTty()) try self.file.sync();
}

fn colorizedLogLevel(comptime level: LogLevel) []const u8 {
    return switch (level) {
        .TRACE => jetzig.colors.white(@tagName(level)),
        .DEBUG => jetzig.colors.cyan(@tagName(level)),
        .INFO => jetzig.colors.blue(@tagName(level) ++ " "),
        .WARN => jetzig.colors.yellow(@tagName(level) ++ " "),
        .ERROR => jetzig.colors.red(@tagName(level)),
        .FATAL => jetzig.colors.red(@tagName(level)),
    };
}
