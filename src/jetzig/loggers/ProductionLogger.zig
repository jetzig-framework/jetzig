const std = @import("std");

const jetzig = @import("../../jetzig.zig");

const ProductionLogger = @This();

const Timestamp = jetzig.types.Timestamp;
const LogLevel = jetzig.loggers.LogLevel;

allocator: std.mem.Allocator,
level: LogLevel,
log_queue: *jetzig.loggers.LogQueue,

/// Initialize a new Development Logger.
pub fn init(
    allocator: std.mem.Allocator,
    level: LogLevel,
    log_queue: *jetzig.loggers.LogQueue,
) ProductionLogger {
    return .{
        .allocator = allocator,
        .level = level,
        .log_queue = log_queue,
    };
}

/// Generic log function, receives log level, message (format string), and args for format string.
pub fn log(
    self: *const ProductionLogger,
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

    const target = jetzig.loggers.logTarget(level);

    try self.log_queue.print(
        "{s} [{s}] {s}\n",
        .{ @tagName(level), iso8601, output },
        target,
    );
}

/// Log a one-liner including response status code, path, method, duration, etc.
pub fn logRequest(self: ProductionLogger, request: *const jetzig.http.Request) !void {
    if (@intFromEnum(LogLevel.INFO) < @intFromEnum(self.level)) return;

    var duration_buf: [256]u8 = undefined;
    const formatted_duration = try jetzig.colors.duration(
        &duration_buf,
        jetzig.util.duration(request.start_time),
        false,
    );

    const status: jetzig.http.status_codes.TaggedStatusCode = switch (request.response.status_code) {
        inline else => |status_code| @unionInit(
            jetzig.http.status_codes.TaggedStatusCode,
            @tagName(status_code),
            .{},
        ),
    };

    const formatted_status = status.getFormatted(.{});
    const timestamp = Timestamp.init(std.time.timestamp());
    var timestamp_buf: [256]u8 = undefined;
    const iso8601 = try timestamp.iso8601(&timestamp_buf);

    const formatted_level = @tagName(.INFO);

    try self.log_queue.print("{s} [{s}] [{s}/{s}/{s}]{s}{s}{s}{s}{s}{s}{s} {s}\n", .{
        formatted_level,
        iso8601,
        formatted_duration,
        request.fmtMethod(false),
        formatted_status,
        if (request.middleware_rendered) |_| " [" else "",
        if (request.middleware_rendered) |middleware| middleware.name else "",
        if (request.middleware_rendered) |_| ":" else "",
        if (request.middleware_rendered) |middleware| middleware.action else "",
        if (request.middleware_rendered) |_| ":" else "",
        if (request.middleware_rendered) |_| @tagName(request.state) else "",
        if (request.middleware_rendered) |_| "]" else "",
        request.path.path,
    }, .stdout);
}

pub fn logSql(self: *const ProductionLogger, event: jetzig.jetquery.events.Event) !void {
    var duration_buf: [256]u8 = undefined;
    const formatted_duration = if (event.duration) |duration| try jetzig.colors.duration(
        &duration_buf,
        duration,
        false,
    ) else "";

    const timestamp = Timestamp.init(std.time.timestamp());
    var timestamp_buf: [256]u8 = undefined;
    const iso8601 = try timestamp.iso8601(&timestamp_buf);

    try self.log_queue.print(
        "{s} [{s}] [database] [sql:{s}] [duration:{s}]\n",
        .{ @tagName(.INFO), iso8601, event.sql orelse "", formatted_duration },
        .stdout,
    );
}

const sql_tokens = .{
    "SELECT",
    "INSERT",
    "UPDATE",
    "DELETE",
    "WHERE",
    "SET",
    "ANY",
    "FROM",
    "INTO",
    "IN",
    "ON",
    "IS",
    "NOT",
    "NULL",
    "LIMIT",
    "ORDER BY",
    "GROUP BY",
    "HAVING",
    "LEFT OUTER JOIN",
    "INNER JOIN",
    "ASC",
    "DESC",
    "MAX",
    "MIN",
    "COUNT",
    "SUM",
    "VALUES",
};

pub fn logError(self: *const ProductionLogger, stack_trace: ?*std.builtin.StackTrace, err: anyerror) !void {
    // TODO: Include line number/column if available.
    _ = stack_trace;
    try self.log(.ERROR, "Encountered Error: {s}", .{@errorName(err)});
}
