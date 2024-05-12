pub const std = @import("std");
pub const tracing = @import("../tracing.zig");
pub const logger = @import("../loggers.zig");
pub const LoggerBackend = @This();

logger: logger.Logger,
timer: std.time.Timer,

inline fn init(_: *LoggerBackend) void {}
inline fn initThread(_: *LoggerBackend) void {}
inline fn denitThread(_: *LoggerBackend) void {}
inline fn deinit(_: *LoggerBackend) void {}
inline fn finish(_: tracing.TracingContext) void {}

inline fn trace(backend: LoggerBackend, context: tracing.TracingContext, comptime formatted_message: []const u8, args: anytype) void {
    backend.logger.logRequest(.TRACE, "{d}ns since last event - {s}:{d}:{d} ({s})" ++ formatted_message, .{
        backend.timer.lap(),    context.source.file,
        context.source.line,    context.source.column,
        context.source.fn_name,
    } ++ args) catch return;
}
