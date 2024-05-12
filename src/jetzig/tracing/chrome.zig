pub const std = @import("std");
pub const tracing = @import("../tracing.zig");

pub const ChromeJsonBackend = @This();
pid: std.os.linux.pid_t = undefined,
mutex: std.Thread.Mutex = .{},
buffered_writer: std.io.BufferedWriter(4096, std.fs.File.Writer) = undefined,
backend_file: std.fs.File = undefined,
timer: std.time.Timer = undefined,
threadlocal var tid: std.os.linux.pid_t = undefined;

inline fn init(backend: *ChromeJsonBackend) void {
    backend.pid = std.os.linux.getpid();
    var name_buffer: [std.fs.MAX_NAME_BYTES]u8 = undefined;
    const file_name = std.fmt.bufPrint(&name_buffer, "trace-{d}.chrome.json", .{backend.pid});
    backend.backend_file = std.fs.cwd().createFile(file_name) catch @panic(std.fmt.comptimePrint("Failed to create the tracing file at {s}:{d}:{d}", blk: {
        const src = @src();
        break :blk .{ src.file, src.line, src.column };
    }));
    backend.buffered_writer = .{ .unbuffered_writer = backend.backend_file.writer() };
    backend.timer = std.time.Timer.start() catch @panic(std.fmt.comptimePrint("Failed to start the timer at {s}:{d}:{d: Verify you computer has support for monotonic timers OR your maching has correct settings (seccomp for example)", blk: {
        const src = @src();
        break :blk .{ src.file, src.line, src.column };
    }));
    backend.buffered_writer.writer().writeAll("[\n") catch @panic(std.fmt.comptimePrint("Failed to write to the tracing file at {s}:{d}:{d}", blk: {
        const src = @src();
        break :blk .{ src.file, src.line, src.column };
    }));
}
inline fn initThread(_: *ChromeJsonBackend) void {
    tid = std.os.linux.gettid();
}
inline fn denitThread(_: *ChromeJsonBackend) void {}
inline fn deinit(_: *ChromeJsonBackend) void {}
inline fn finish(ctx: tracing.TracingContext) void {
    var backend = ctx.ImplInterface.chrome;
    backend.mutex.lock();
    defer backend.mutex.unlock();
    backend.buffered_writer.writer().print(
        \\{{"cat":"function", "ph": "E", "pid": {d}, "tid": {d}, "ts": {d}}},
        \\
    ,
        .{ backend.pid, tid, backend.timer.elapsed() },
    ) catch {};
}
inline fn trace(backend: ChromeJsonBackend, context: tracing.TracingContext, comptime formatted_message: []const u8, args: anytype) void {
    backend.mutex.lock();
    defer backend.mutex.unlock();
    var writer = backend.buffered_writer.writer();
    writer.print(
        \\{{"cat":"function", "name":"{s}:{d}:{d} ({s})
        ++ formatted_message ++
            \\", "ph": "B", "pid": {d}, "tid": {d}, "ts": {d}}},
            \\
    ,
        blk: {
            const src = context.source;
            break :blk .{ src.file, src.line, src.column, src.function };
        } ++ args ++
            .{
            backend.pid,
            tid,
            backend.timer.elapsed(),
        },
    ) catch {};
}
