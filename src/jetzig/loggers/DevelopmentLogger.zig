const std = @import("std");

const jetzig = @import("../../jetzig.zig");

const DevelopmentLogger = @This();

const Timestamp = jetzig.types.Timestamp;
const LogLevel = jetzig.loggers.LogLevel;

allocator: std.mem.Allocator,
stdout_colorized: bool,
stderr_colorized: bool,
level: LogLevel,
log_queue: *jetzig.loggers.LogQueue,

/// Initialize a new Development Logger.
pub fn init(
    allocator: std.mem.Allocator,
    level: LogLevel,
    log_queue: *jetzig.loggers.LogQueue,
) DevelopmentLogger {
    return .{
        .allocator = allocator,
        .level = level,
        .log_queue = log_queue,
        .stdout_colorized = log_queue.stdout_is_tty,
        .stderr_colorized = log_queue.stderr_is_tty,
    };
}

/// Generic log function, receives log level, message (format string), and args for format string.
pub fn log(
    self: *const DevelopmentLogger,
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
    const formatted_level = colorizedLogLevel(level);

    try self.log_queue.print(
        "{s: >5} [{s}] {s}\n",
        .{ formatted_level, iso8601, output },
        target,
    );
}

/// Log a one-liner including response status code, path, method, duration, etc.
pub fn logRequest(self: DevelopmentLogger, request: *const jetzig.http.Request) !void {
    if (@intFromEnum(LogLevel.INFO) < @intFromEnum(self.level)) return;

    var duration_buf: [256]u8 = undefined;
    const formatted_duration = try jetzig.colors.duration(
        &duration_buf,
        jetzig.util.duration(request.start_time),
        self.stdout_colorized,
    );

    const status: jetzig.http.status_codes.TaggedStatusCode = switch (request.response.status_code) {
        inline else => |status_code| @unionInit(
            jetzig.http.status_codes.TaggedStatusCode,
            @tagName(status_code),
            .{},
        ),
    };

    const formatted_status = if (self.stdout_colorized)
        status.getFormatted(.{ .colorized = true })
    else
        status.getFormatted(.{});

    const timestamp = Timestamp.init(std.time.timestamp());
    var timestamp_buf: [256]u8 = undefined;
    const iso8601 = try timestamp.iso8601(&timestamp_buf);

    const formatted_level = if (self.stdout_colorized) colorizedLogLevel(.INFO) else @tagName(.INFO);

    try self.log_queue.print("{s: >5} [{s}] [{s}/{s}/{s}]{s}{s}{s}{s}{s}{s}{s}{s}{s}{s} {s}\n", .{
        formatted_level,
        iso8601,
        formatted_duration,
        request.fmtMethod(self.stdout_colorized),
        formatted_status,
        if (request.middleware_rendered) |_| " [" ++ jetzig.colors.codes.escape ++ jetzig.colors.codes.magenta else "",
        if (request.middleware_rendered) |middleware| middleware.name else "",
        if (request.middleware_rendered) |_| jetzig.colors.codes.escape ++ jetzig.colors.codes.white ++ ":" else "",
        if (request.middleware_rendered) |_| jetzig.colors.codes.escape ++ jetzig.colors.codes.blue else "",
        if (request.middleware_rendered) |middleware| middleware.action else "",
        if (request.middleware_rendered) |_| jetzig.colors.codes.escape ++ jetzig.colors.codes.white ++ ":" else "",
        if (request.middleware_rendered) |_| jetzig.colors.codes.escape ++ jetzig.colors.codes.bright_cyan else "",
        if (request.middleware_rendered) |_| if (request.redirected) "redirect" else "render" else "",
        if (request.middleware_rendered) |_| jetzig.colors.codes.escape ++ jetzig.colors.codes.reset else "",
        if (request.middleware_rendered) |_| "]" else "",
        request.path.path,
    }, .stdout);
}

inline fn colorizedLogLevel(comptime level: LogLevel) []const u8 {
    return switch (level) {
        .TRACE => jetzig.colors.white(@tagName(level)),
        .DEBUG => jetzig.colors.cyan(@tagName(level)),
        .INFO => jetzig.colors.blue(@tagName(level) ++ " "),
        .WARN => jetzig.colors.yellow(@tagName(level) ++ " "),
        .ERROR => jetzig.colors.red(@tagName(level)),
        .FATAL => jetzig.colors.red(@tagName(level)),
    };
}
