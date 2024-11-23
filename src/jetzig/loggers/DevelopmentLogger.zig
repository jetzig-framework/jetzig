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
mutex: *std.Thread.Mutex,

/// Initialize a new Development Logger.
pub fn init(
    allocator: std.mem.Allocator,
    level: LogLevel,
    stdout: std.fs.File,
    stderr: std.fs.File,
) DevelopmentLogger {
    const mutex = allocator.create(std.Thread.Mutex) catch unreachable;
    mutex.* = std.Thread.Mutex{};

    return .{
        .allocator = allocator,
        .level = level,
        .stdout = stdout,
        .stderr = stderr,
        .stdout_colorized = stdout.isTty(),
        .stderr_colorized = stderr.isTty(),
        .mutex = mutex,
    };
}

/// Generic log function, receives log level, message (format string), and args for format string.
pub fn log(
    self: *const DevelopmentLogger,
    comptime level: LogLevel,
    comptime message: []const u8,
    args: anytype,
) !void {
    self.mutex.lock();
    defer self.mutex.unlock();

    if (@intFromEnum(level) < @intFromEnum(self.level)) return;

    const output = try std.fmt.allocPrint(self.allocator, message, args);
    defer self.allocator.free(output);

    const timestamp = Timestamp.init(std.time.timestamp());
    var timestamp_buf: [256]u8 = undefined;
    const iso8601 = try timestamp.iso8601(&timestamp_buf);

    const formatted_level = colorizedLogLevel(level);

    try self.print(
        level,
        "{s: >5} [{s}] {s}\n",
        .{ formatted_level, iso8601, output },
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

    try self.print(.INFO, "{s: >5} [{s}] [{s}/{s}/{s}]{s}{s}{s}{s}{s}{s}{s}{s}{s}{s} {s}\n", .{
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
        if (request.middleware_rendered) |_| @tagName(request.state) else "",
        if (request.middleware_rendered) |_| jetzig.colors.codes.escape ++ jetzig.colors.codes.reset else "",
        if (request.middleware_rendered) |_| "]" else "",
        request.path.path,
    });
}

pub fn logSql(self: *const DevelopmentLogger, event: jetzig.jetquery.events.Event) !void {
    // XXX: This function does not make any effort to prevent log messages clobbering each other
    // from multiple threads. JSON logger etc. write in one call and the log queue prevents
    // clobbering, but this is not the case here.
    const formatted_level = if (self.stdout_colorized) colorizedLogLevel(.INFO) else @tagName(.INFO);
    try self.print(.INFO, "{s} [database] ", .{formatted_level});
    try self.printSql(event.sql orelse "");

    var duration_buf: [256]u8 = undefined;
    const formatted_duration = if (event.duration) |duration| try jetzig.colors.duration(
        &duration_buf,
        duration,
        self.stdout_colorized,
    ) else "";

    try self.print(
        .INFO,
        std.fmt.comptimePrint(" [{s}]\n", .{jetzig.colors.cyan("{s}")}),
        .{formatted_duration},
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

fn printSql(self: *const DevelopmentLogger, sql: []const u8) !void {
    const string_color = jetzig.colors.codes.escape ++ jetzig.colors.codes.green;
    const identifier_color = jetzig.colors.codes.escape ++ jetzig.colors.codes.yellow;
    const reset_color = jetzig.colors.codes.escape ++ jetzig.colors.codes.reset;
    var buf: [4096]u8 = undefined;
    var stream = std.io.fixedBufferStream(&buf);
    const writer = stream.writer();

    var index: usize = 0;
    var single_quote: bool = false;
    var double_quote: bool = false;
    while (index < sql.len) {
        // TODO: Escapes
        switch (sql[index]) {
            '"' => {
                if (!single_quote) {
                    double_quote = !double_quote;
                    if (double_quote) {
                        try writer.print(identifier_color ++ "\"", .{});
                    } else {
                        try writer.print("\"" ++ reset_color, .{});
                    }
                    index += 1;
                }
            },
            '\'' => {
                if (!double_quote) {
                    single_quote = !single_quote;
                    if (single_quote) {
                        try writer.print(string_color ++ "'", .{});
                    } else {
                        try writer.print("'" ++ reset_color, .{});
                    }
                }
                index += 1;
            },
            '$' => {
                if (double_quote or single_quote) {
                    try writer.print("{c}", .{sql[index]});
                    index += 1;
                } else {
                    const param = sql[index..][0 .. std.mem.indexOfAny(
                        u8,
                        sql[index..],
                        &std.ascii.whitespace,
                    ) orelse sql.len - index];
                    try writer.print(jetzig.colors.magenta("{s}"), .{param});
                    index += param.len;
                }
            },
            else => {
                if (double_quote or single_quote) {
                    try writer.print("{c}", .{sql[index]});
                    index += 1;
                } else {
                    inline for (sql_tokens) |token| {
                        if (std.mem.startsWith(u8, sql[index..], token)) {
                            try writer.print(jetzig.colors.cyan(token), .{});
                            index += token.len;
                            break;
                        }
                    } else {
                        try writer.print("{c}", .{sql[index]});
                        index += 1;
                    }
                }
            },
        }
    }
    try self.print(.INFO, "{s}", .{stream.getWritten()});
}

pub fn logError(self: *const DevelopmentLogger, stack_trace: ?*std.builtin.StackTrace, err: anyerror) !void {
    if (stack_trace) |stack| {
        try self.log(.ERROR, "Encountered Error: {s}", .{@errorName(err)});
        try self.log(.ERROR, "Stack trace:\n{}", .{stack});
    } else {
        try self.log(.ERROR, "Encountered Error: {s}", .{@errorName(err)});
    }
}

fn logFile(self: DevelopmentLogger, comptime level: jetzig.loggers.LogLevel) std.fs.File {
    const target = comptime jetzig.loggers.logTarget(level);
    return switch (target) {
        .stdout => self.stdout,
        .stderr => self.stderr,
    };
}

fn logWriter(self: DevelopmentLogger, comptime level: jetzig.loggers.LogLevel) std.fs.File.Writer {
    return self.logFile(level).writer();
}

fn print(
    self: DevelopmentLogger,
    comptime level: jetzig.loggers.LogLevel,
    comptime template: []const u8,
    args: anytype,
) !void {
    const log_writer = self.logWriter(level);
    const count = std.fmt.count(template, args);
    const buf_size = 4096;
    if (count <= buf_size) {
        var buf: [buf_size]u8 = undefined;
        var stream = std.io.fixedBufferStream(&buf);
        const writer = stream.writer();
        try writer.print(template, args);
        try jetzig.util.writeAnsi(self.logFile(level), log_writer, stream.getWritten());
    } else {
        const buf = try self.allocator.alloc(u8, count);
        defer self.allocator.free(buf);
        var stream = std.io.fixedBufferStream(buf);
        const writer = stream.writer();
        try writer.print(template, args);
        try jetzig.util.writeAnsi(self.logFile(level), log_writer, stream.getWritten());
    }
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
