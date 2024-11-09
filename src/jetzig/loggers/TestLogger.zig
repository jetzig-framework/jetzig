const std = @import("std");

const jetzig = @import("../../jetzig.zig");

const TestLogger = @This();

mode: enum { stream, file, disable },
file: ?std.fs.File = null,

pub fn TRACE(self: TestLogger, comptime message: []const u8, args: anytype) !void {
    try self.log(.TRACE, message, args);
}

pub fn DEBUG(self: TestLogger, comptime message: []const u8, args: anytype) !void {
    try self.log(.DEBUG, message, args);
}

pub fn INFO(self: TestLogger, comptime message: []const u8, args: anytype) !void {
    try self.log(.INFO, message, args);
}

pub fn WARN(self: TestLogger, comptime message: []const u8, args: anytype) !void {
    try self.log(.WARN, message, args);
}

pub fn ERROR(self: TestLogger, comptime message: []const u8, args: anytype) !void {
    try self.log(.ERROR, message, args);
}

pub fn FATAL(self: TestLogger, comptime message: []const u8, args: anytype) !void {
    try self.log(.FATAL, message, args);
}

pub fn logRequest(self: TestLogger, request: *const jetzig.http.Request) !void {
    const status = jetzig.http.status_codes.get(request.response.status_code);
    var buf: [256]u8 = undefined;
    try self.log(.INFO, "[{s}|{s}|{s}] {s}", .{
        request.fmtMethod(true),
        try jetzig.colors.duration(&buf, jetzig.util.duration(request.start_time), true),
        status.getFormatted(.{ .colorized = true }),
        request.path.path,
    });
}

pub fn logSql(self: TestLogger, event: jetzig.jetquery.events.Event) !void {
    try self.log(.INFO, "[database] {?s}", .{event.sql});
}

pub fn logError(self: TestLogger, err: anyerror) !void {
    try self.log(.ERROR, "Encountered error: {s}", .{@errorName(err)});
}

pub fn log(
    self: TestLogger,
    comptime level: jetzig.loggers.LogLevel,
    comptime message: []const u8,
    args: anytype,
) !void {
    const template = "-- test logger: " ++ @tagName(level) ++ " " ++ message ++ "\n";
    switch (self.mode) {
        .stream => std.debug.print(template, args),
        .file => try self.file.?.writer().print(template, args),
        .disable => {},
    }
}
