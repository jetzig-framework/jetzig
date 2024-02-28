const std = @import("std");

const jetzig = @import("../../jetzig.zig");

const JsonLogger = @This();

const Timestamp = jetzig.types.Timestamp;
const LogLevel = jetzig.loggers.LogLevel;
const LogMessage = struct {
    level: []const u8,
    timestamp: []const u8,
    message: []const u8,
};
const RequestLogMessage = struct {
    level: []const u8,
    timestamp: []const u8,
    method: []const u8,
    status: []const u8,
    path: []const u8,
    duration: i64,
};

allocator: std.mem.Allocator,
stdout: std.fs.File,
stderr: std.fs.File,
level: LogLevel,
mutex: std.Thread.Mutex,

/// Initialize a new JSON Logger.
pub fn init(
    allocator: std.mem.Allocator,
    level: LogLevel,
    stdout: std.fs.File,
    stderr: std.fs.File,
) JsonLogger {
    return .{
        .allocator = allocator,
        .level = level,
        .stdout = stdout,
        .stderr = stderr,
        .mutex = std.Thread.Mutex{},
    };
}

/// Generic log function, receives log level, message (format string), and args for format string.
pub fn log(
    self: *const JsonLogger,
    comptime level: LogLevel,
    comptime message: []const u8,
    args: anytype,
) !void {
    if (@intFromEnum(level) < @intFromEnum(self.level)) return;

    const output = try std.fmt.allocPrint(self.allocator, message, args);
    defer self.allocator.free(output);

    const timestamp = Timestamp.init(std.time.timestamp(), self.allocator);
    const iso8601 = try timestamp.iso8601();
    defer self.allocator.free(iso8601);

    const file = self.getFile(level);
    const writer = file.writer();
    const log_message = LogMessage{ .level = @tagName(level), .timestamp = iso8601, .message = output };

    const json = try std.json.stringifyAlloc(self.allocator, log_message, .{ .whitespace = .minified });
    defer self.allocator.free(json);

    @constCast(self).mutex.lock();
    defer @constCast(self).mutex.unlock();

    try writer.writeAll(json);
    try writer.writeByte('\n');

    if (!file.isTty()) try file.sync(); // Make configurable ?
}

/// Log a one-liner including response status code, path, method, duration, etc.
pub fn logRequest(self: *const JsonLogger, request: *const jetzig.http.Request) !void {
    const level: LogLevel = .INFO;

    const duration = jetzig.util.duration(request.start_time);

    const timestamp = Timestamp.init(std.time.timestamp(), self.allocator);
    const iso8601 = try timestamp.iso8601();
    defer self.allocator.free(iso8601);

    const status = switch (request.response.status_code) {
        inline else => |status_code| @unionInit(
            jetzig.http.status_codes.TaggedStatusCode,
            @tagName(status_code),
            .{},
        ),
    };
    const message = RequestLogMessage{
        .level = @tagName(level),
        .timestamp = iso8601,
        .method = @tagName(request.method),
        .status = status.getCode(),
        .path = request.path.path,
        .duration = duration,
    };
    const json = try std.json.stringifyAlloc(self.allocator, message, .{ .whitespace = .minified });
    defer self.allocator.free(json);

    const file = self.getFile(level);
    const writer = file.writer();

    @constCast(self).mutex.lock();
    defer @constCast(self).mutex.unlock();

    try writer.writeAll(json);
    try writer.writeByte('\n');

    if (!file.isTty()) try file.sync(); // Make configurable ?
}

fn getFile(self: JsonLogger, level: LogLevel) std.fs.File {
    return switch (level) {
        .TRACE, .DEBUG, .INFO => self.stdout,
        .WARN, .ERROR, .FATAL => self.stderr,
    };
}
