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
log_queue: *jetzig.loggers.LogQueue,
level: LogLevel,

/// Initialize a new JSON Logger.
pub fn init(
    allocator: std.mem.Allocator,
    level: LogLevel,
    log_queue: *jetzig.loggers.LogQueue,
) JsonLogger {
    return .{
        .allocator = allocator,
        .level = level,
        .log_queue = log_queue,
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

    const timestamp = Timestamp.init(std.time.timestamp());
    var timestamp_buf: [256]u8 = undefined;
    const iso8601 = try timestamp.iso8601(&timestamp_buf);

    const log_message = LogMessage{ .level = @tagName(level), .timestamp = iso8601, .message = output };

    const json = try std.json.stringifyAlloc(self.allocator, log_message, .{ .whitespace = .minified });
    defer self.allocator.free(json);

    try self.log_queue.print("{s}\n", .{json}, jetzig.loggers.logTarget(level));
}

/// Log a one-liner including response status code, path, method, duration, etc.
pub fn logRequest(self: *const JsonLogger, request: *const jetzig.http.Request) !void {
    const level: LogLevel = .INFO;

    const duration = jetzig.util.duration(request.start_time);

    const timestamp = Timestamp.init(std.time.timestamp());
    var timestamp_buf: [256]u8 = undefined;
    const iso8601 = try timestamp.iso8601(&timestamp_buf);

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

    var buf: [4096]u8 = undefined;
    var stream = std.io.fixedBufferStream(&buf);
    std.json.stringify(message, .{ .whitespace = .minified }, stream.writer()) catch |err| {
        switch (err) {
            error.NoSpaceLeft => {}, // TODO: Spill to heap
            else => return err,
        }
    };

    try self.log_queue.print("{s}\n", .{stream.getWritten()}, .stdout);
}

fn getFile(self: JsonLogger, level: LogLevel) std.fs.File {
    return switch (level) {
        .TRACE, .DEBUG, .INFO => self.stdout,
        .WARN, .ERROR, .FATAL => self.stderr,
    };
}
