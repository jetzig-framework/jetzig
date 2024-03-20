const std = @import("std");

const jetzig = @import("../../jetzig.zig");

const DevelopmentLogger = @This();

const Timestamp = jetzig.types.Timestamp;
const LogLevel = jetzig.loggers.LogLevel;

allocator: std.mem.Allocator,
stdout: std.fs.File,
stderr: std.fs.File,
stdout_colorized: bool,
stderr_colorized: bool,
level: LogLevel,

/// Initialize a new Development Logger.
pub fn init(
    allocator: std.mem.Allocator,
    level: LogLevel,
    stdout: std.fs.File,
    stderr: std.fs.File,
) DevelopmentLogger {
    return .{
        .allocator = allocator,
        .level = level,
        .stdout = stdout,
        .stderr = stderr,
        .stdout_colorized = stdout.isTty(),
        .stderr_colorized = stderr.isTty(),
    };
}

/// Generic log function, receives log level, message (format string), and args for format string.
pub fn log(
    self: DevelopmentLogger,
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

    const colorized = switch (level) {
        .TRACE, .DEBUG, .INFO => self.stdout_colorized,
        .WARN, .ERROR, .FATAL => self.stderr_colorized,
    };
    const file = switch (level) {
        .TRACE, .DEBUG, .INFO => self.stdout,
        .WARN, .ERROR, .FATAL => self.stderr,
    };
    const writer = file.writer();
    const level_formatted = if (colorized) colorizedLogLevel(level) else @tagName(level);

    try writer.print("{s: >5} [{s}] {s}\n", .{ level_formatted, iso8601, output });

    if (!file.isTty()) try file.sync();
}

/// Log a one-liner including response status code, path, method, duration, etc.
pub fn logRequest(self: DevelopmentLogger, request: *const jetzig.http.Request) !void {
    const formatted_duration = if (self.stdout_colorized)
        try jetzig.colors.duration(self.allocator, jetzig.util.duration(request.start_time))
    else
        try std.fmt.allocPrint(self.allocator, "{}", .{jetzig.util.duration(request.start_time)});
    defer self.allocator.free(formatted_duration);

    const status: jetzig.http.status_codes.TaggedStatusCode = switch (request.response.status_code) {
        inline else => |status_code| @unionInit(
            jetzig.http.status_codes.TaggedStatusCode,
            @tagName(status_code),
            .{},
        ),
    };

    const message = try std.fmt.allocPrint(self.allocator, "[{s}/{s}/{s}] {s}", .{
        formatted_duration,
        request.fmtMethod(self.stdout_colorized),
        status.format(self.stdout_colorized),
        request.path.path,
    });
    defer self.allocator.free(message);
    try self.log(.INFO, "{s}", .{message});
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
