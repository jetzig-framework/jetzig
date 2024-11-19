const std = @import("std");

const jetzig = @import("../../jetzig.zig");

pub inline fn log(self: @This(), comptime level: jetzig.loggers.LogLevel, comptime message: []const u8, args: anytype) !void {
    _ = self;
    _ = level;
    _ = message;
    _ = args;
}

pub inline fn logSql(self: @This(), event: jetzig.jetquery.events.Event) !void {
    _ = self;
    _ = event;
}

pub inline fn logRequest(self: @This(), request: *const jetzig.http.Request) !void {
    _ = self;
    _ = request;
}

pub inline fn logError(self: @This(), stack_trace: ?*std.builtin.StackTrace, err: anyerror) !void {
    _ = self;
    _ = stack_trace;
    std.debug.print("Error: {s}\n", .{@errorName(err)});
}
