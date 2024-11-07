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
mutex: *std.Thread.Mutex,

/// Initialize a new Development Logger.
pub fn init(
    allocator: std.mem.Allocator,
    level: LogLevel,
    log_queue: *jetzig.loggers.LogQueue,
) DevelopmentLogger {
    const mutex = allocator.create(std.Thread.Mutex) catch unreachable;
    return .{
        .allocator = allocator,
        .level = level,
        .log_queue = log_queue,
        .stdout_colorized = log_queue.stdout_is_tty,
        .stderr_colorized = log_queue.stderr_is_tty,
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

pub fn logSql(self: *const DevelopmentLogger, event: jetzig.jetquery.events.Event) !void {
    self.mutex.lock();
    defer self.mutex.unlock();

    // XXX: This function does not make any effort to prevent log messages clobbering each other
    // from multiple threads. JSON logger etc. write in one call and the logger's mutex prevents
    // clobbering, but this is not the case here.
    const formatted_level = if (self.stdout_colorized) colorizedLogLevel(.INFO) else @tagName(.INFO);
    try self.log_queue.print(
        "{s} [database] ",
        .{formatted_level},
        .stdout,
    );
    try self.printSql(event.sql orelse "");

    var duration_buf: [256]u8 = undefined;
    const formatted_duration = if (event.duration) |duration| try jetzig.colors.duration(
        &duration_buf,
        duration,
        self.stdout_colorized,
    ) else "";

    try self.log_queue.print(
        std.fmt.comptimePrint(" [{s}]\n", .{jetzig.colors.cyan("{s}")}),
        .{formatted_duration},
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

fn printSql(self: *const DevelopmentLogger, sql: []const u8) !void {
    const string_color = jetzig.colors.codes.escape ++ jetzig.colors.codes.green;
    const identifier_color = jetzig.colors.codes.escape ++ jetzig.colors.codes.yellow;
    const reset_color = jetzig.colors.codes.escape ++ jetzig.colors.codes.reset;

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
                        try self.log_queue.print(identifier_color ++ "\"", .{}, .stdout);
                    } else {
                        try self.log_queue.print("\"" ++ reset_color, .{}, .stdout);
                    }
                    index += 1;
                }
            },
            '\'' => {
                if (!double_quote) {
                    single_quote = !single_quote;
                    if (single_quote) {
                        try self.log_queue.print(string_color ++ "'", .{}, .stdout);
                    } else {
                        try self.log_queue.print("'" ++ reset_color, .{}, .stdout);
                    }
                }
                index += 1;
            },
            '$' => {
                if (double_quote or single_quote) {
                    try self.log_queue.print("{c}", .{sql[index]}, .stdout);
                    index += 1;
                } else {
                    const param = sql[index..][0 .. std.mem.indexOfAny(
                        u8,
                        sql[index..],
                        &std.ascii.whitespace,
                    ) orelse sql.len - index];
                    try self.log_queue.print(jetzig.colors.magenta("{s}"), .{param}, .stdout);
                    index += param.len;
                }
            },
            else => {
                if (double_quote or single_quote) {
                    try self.log_queue.print("{c}", .{sql[index]}, .stdout);
                    index += 1;
                } else {
                    inline for (sql_tokens) |token| {
                        if (std.mem.startsWith(u8, sql[index..], token)) {
                            try self.log_queue.print(jetzig.colors.cyan(token), .{}, .stdout);
                            index += token.len;
                            break;
                        }
                    } else {
                        try self.log_queue.print("{c}", .{sql[index]}, .stdout);
                        index += 1;
                    }
                }
            },
        }
    }
}

pub fn logError(self: *const DevelopmentLogger, err: anyerror) !void {
    if (@errorReturnTrace()) |stack| {
        try self.log(.ERROR, "\nStack Trace:\n{}", .{stack});
        var buf = std.ArrayList(u8).init(self.allocator);
        defer buf.deinit();
        const writer = buf.writer();
        try stack.format("", .{}, writer);
        try self.logger.ERROR("{s}\n", .{buf.items});
    }

    try self.log(.ERROR, "Encountered Error: {s}", .{@errorName(err)});
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
