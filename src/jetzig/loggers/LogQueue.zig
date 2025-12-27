const std = @import("std");
const Io = std.Io;
const testing = std.testing;
const Allocator = std.mem.Allocator;
const ArrayList = std.ArrayList;
const Mutex = std.Thread.Mutex;
const Condition = std.Thread.Condition;
const DoublyLinkedList = std.DoublyLinkedList;
const Node = DoublyLinkedList.Node;
const File = std.fs.File;
const MemoryPool = std.heap.MemoryPool;
const assert = std.debug.assert;

const builtin = @import("builtin");

const jetzig = @import("../../jetzig.zig");
const LogFile = jetzig.loggers.LogFile;

const buffer_size = jetzig.config.get(usize, "log_message_buffer_len");
const max_pool_len = jetzig.config.get(usize, "max_log_pool_len");

const List = DoublyLinkedList;
const ListNode = struct {
    event: Event,
    node: Node = .{},
};
const Buffer = [buffer_size]u8;

allocator: Allocator,
node_allocator: MemoryPool(ListNode),
buffer_allocator: MemoryPool(Buffer),
list: List,
read_write_mutex: Mutex,
condition: Condition,
condition_mutex: Mutex,
writer: Writer = undefined,
reader: Reader = undefined,
node_pool: ArrayList(*ListNode),
buffer_pool: ArrayList(*Buffer),
position: usize,
stdout_is_tty: bool = undefined,
stderr_is_tty: bool = undefined,
stdout_colorize: bool = undefined,
stderr_colorize: bool = undefined,
state: enum { pending, ready } = .pending,

const LogQueue = @This();

pub const Target = enum { stdout, stderr };

const Event = struct {
    message: *Buffer,
    len: usize,
    target: Target,
    ptr: ?[]const u8,
};

/// Create a new `LogQueue`.
pub fn init(allocator: Allocator) LogQueue {
    return .{
        .allocator = allocator,
        .node_allocator = initPool(allocator, ListNode),
        .buffer_allocator = initPool(allocator, Buffer),
        .list = .{},
        .condition = .{},
        .condition_mutex = .{},
        .read_write_mutex = .{},
        .node_pool = .empty,
        .buffer_pool = .empty,
        .position = 0,
    };
}

/// Free allocated resources and return to `pending` state.
pub fn deinit(self: *LogQueue) void {
    self.node_pool.deinit(self.allocator);
    self.buffer_pool.deinit(self.allocator);

    self.buffer_allocator.deinit();
    self.node_allocator.deinit();

    self.state = .pending;
}

/// Set the stdout and stderr outputs. Must be called before `print`.
pub fn setFiles(
    self: *LogQueue,
    stdout_file: LogFile,
    stderr_file: LogFile,
) !void {
    self.writer = Writer{
        .queue = self,
        .mutex = .{},
    };
    self.reader = Reader{
        .stdout_file = stdout_file,
        .stderr_file = stderr_file,
        .queue = self,
    };
    self.stdout_is_tty = stdout_file.file.isTty();
    self.stderr_is_tty = stderr_file.file.isTty();

    self.stdout_colorize = std.Io.tty.detectConfig(stdout_file.file) != .no_color;
    self.stderr_colorize = std.Io.tty.detectConfig(stderr_file.file) != .no_color;

    try self.node_pool.ensureTotalCapacity(self.allocator, max_pool_len);
    try self.buffer_pool.ensureTotalCapacity(self.allocator, max_pool_len);

    self.state = .ready;
}

pub fn print(self: *LogQueue, comptime message: []const u8, args: anytype, target: Target) !void {
    assert(self.state == .ready);
    try self.writer.print(message, args, target);
}

/// Writer for `LogQueue`. Receives log events and publishes to the queue.
pub const Writer = struct {
    queue: *LogQueue,
    position: usize = 0,
    mutex: Mutex,

    /// Print a log event. Messages longer than `jetzig.config.get(usize, "log_message_buffer_len")`
    /// spill to heap with degraded performance. Adjust buffer length or limit long entries to
    /// ensure fast logging performance.
    /// `target` must be `.stdout` or `.stderr`.
    pub fn print(
        self: *Writer,
        comptime message: []const u8,
        args: anytype,
        target: Target,
    ) !void {
        self.mutex.lock();
        defer self.mutex.unlock();

        const buf = try self.getBuffer();
        self.position += 1;
        var ptr: ?[]const u8 = null;

        const result = std.fmt.bufPrint(buf, message, args) catch |err| switch (err) {
            error.NoSpaceLeft => blk: {
                ptr = try std.fmt.allocPrint(self.queue.allocator, message, args);
                self.position -= 1;
                break :blk null;
            },
        };

        try self.queue.append(.{
            .message = buf,
            .target = target,
            .len = if (ptr) |capture| capture.len else result.?.len,
            .ptr = ptr,
        });
    }

    fn getBuffer(self: *Writer) !*Buffer {
        const buffer = if (self.position >= self.queue.buffer_pool.items.len)
            try self.queue.buffer_allocator.create()
        else
            self.queue.buffer_pool.items[self.position];

        return buffer;
    }
};

/// Reader for `LogQueue`. Reads log events from the queue and writes them to the designated
/// target (stdout or stderr).
pub const Reader = struct {
    stdout_file: LogFile,
    stderr_file: LogFile,
    queue: *LogQueue,

    pub const PublishOptions = struct {
        oneshot: bool = false,
    };

    /// Publish log events from the queue. Invoke from a dedicated thread. Sleeps when log queue
    /// is empty, wakes up when a new event is published.
    pub fn publish(self: *Reader, options: PublishOptions) !void {
        assert(self.queue.state == .ready);

        while (true) {
            self.queue.condition_mutex.lock();
            defer self.queue.condition_mutex.unlock();

            if (!options.oneshot) self.queue.condition.wait(&self.queue.condition_mutex);

            var stdout_written = false;
            var stderr_written = false;
            var file: File = undefined;

            while (try self.queue.popFirst()) |event| {
                self.queue.writer.mutex.lock();
                defer self.queue.writer.mutex.unlock();

                const target_file = switch (event.target) {
                    .stdout => blk: {
                        stdout_written = true;
                        if (builtin.os.tag == .windows) {
                            file = self.stdout_file.file;
                        }
                        break :blk self.stdout_file.file;
                    },
                    .stderr => blk: {
                        stderr_written = true;
                        if (builtin.os.tag == .windows) {
                            file = self.stderr_file.file;
                        }
                        break :blk self.stderr_file.file;
                    },
                };

                if (event.ptr) |ptr| {
                    // Log message spilled to heap
                    defer self.queue.allocator.free(ptr);
                    try target_file.writeAll(ptr);
                    continue;
                }

                try target_file.writeAll(event.message[0..event.len]);

                self.queue.writer.position -= 1;

                if (self.queue.writer.position < self.queue.buffer_pool.items.len) {
                    self.queue.buffer_pool.items[self.queue.writer.position] = event.message;
                } else {
                    if (self.queue.buffer_pool.items.len >= max_pool_len) {
                        self.queue.buffer_allocator.destroy(@alignCast(event.message));
                        self.queue.writer.position += 1;
                    } else {
                        try self.queue.buffer_pool.append(self.queue.allocator, event.message);
                    }
                }
            }

            if (stdout_written and self.stdout_file.sync) try self.stdout_file.file.sync();
            if (stderr_written and self.stderr_file.sync) try self.stderr_file.file.sync();

            if (options.oneshot) break;
        }
    }
};

// Append a log event to the queue. Signal the publish loop thread to wake up. Recycle nodes if
// available in the pool, otherwise create a new one.
fn append(self: *LogQueue, event: Event) !void {
    self.read_write_mutex.lock();
    defer self.read_write_mutex.unlock();

    const node = if (self.position >= self.node_pool.items.len)
        try self.node_allocator.create()
    else
        self.node_pool.items[self.position];

    self.position += 1;

    node.* = .{ .event = event };
    self.list.append(&node.node);

    self.condition.signal();
}

// Pop a log event from the queue. Return node to the pool for re-use.
fn popFirst(self: *LogQueue) !?Event {
    self.read_write_mutex.lock();
    defer self.read_write_mutex.unlock();

    if (self.list.popFirst()) |node| {
        const list_node: *ListNode = @fieldParentPtr("node", node);
        const value = list_node.event;
        self.position -= 1;
        if (self.position < self.node_pool.items.len) {
            self.node_pool.items[self.position] = list_node;
        } else {
            if (self.node_pool.items.len >= max_pool_len) {
                self.node_allocator.destroy(list_node);
                self.position += 1;
            } else {
                try self.node_pool.append(self.allocator, list_node);
            }
        }
        return value;
    }
    return null;
}

fn initPool(allocator: Allocator, T: type) MemoryPool(T) {
    return MemoryPool(T).initPreheated(allocator, max_pool_len) catch @panic("OOM");
}

test "print to stdout and stderr" {
    var log_queue: LogQueue = .init(testing.allocator);
    defer log_queue.deinit();

    var tmp_dir = testing.tmpDir(.{});
    defer tmp_dir.cleanup();

    const stdout = try tmp_dir.dir.createFile("stdout.log", .{ .read = true, .truncate = true });
    defer stdout.close();

    const stderr = try tmp_dir.dir.createFile("stderr.log", .{ .read = true, .truncate = true });
    defer stderr.close();

    try log_queue.setFiles(.{ .file = stdout, .sync = true }, .{ .file = stderr, .sync = true });
    try log_queue.print("foo {s}\n", .{"bar"}, .stdout);
    try log_queue.print("baz {s}\n", .{"qux"}, .stderr);
    try log_queue.print("quux {s}\n", .{"corge"}, .stdout);
    try log_queue.print("grault {s}\n", .{"garply"}, .stderr);
    try log_queue.print("waldo {s}\n", .{"fred"}, .stderr);
    try log_queue.print("plugh {s}\n", .{"zyzzy"}, .stdout);

    try log_queue.reader.publish(.{ .oneshot = true });

    try stdout.seekTo(0);
    var buf: [1024]u8 = undefined;
    var len = try stdout.readAll(&buf);

    try testing.expectEqualStrings(
        \\foo bar
        \\quux corge
        \\plugh zyzzy
        \\
    , buf[0..len]);

    try stderr.seekTo(0);
    len = try stderr.readAll(&buf);
    try testing.expectEqualStrings(
        \\baz qux
        \\grault garply
        \\waldo fred
        \\
    , buf[0..len]);
}

test "long messages" {
    var log_queue: LogQueue = .init(testing.allocator);
    defer log_queue.deinit();

    var tmp_dir = testing.tmpDir(.{});
    defer tmp_dir.cleanup();

    const stdout = try tmp_dir.dir.createFile("stdout.log", .{ .read = true, .truncate = true });
    defer stdout.close();

    const stderr = try tmp_dir.dir.createFile("stderr.log", .{ .read = true, .truncate = true });
    defer stderr.close();

    try log_queue.setFiles(.{ .file = stdout, .sync = true }, .{ .file = stderr, .sync = true });
    try log_queue.print("foo" ** buffer_size, .{}, .stdout);

    try log_queue.reader.publish(.{ .oneshot = true });

    try stdout.seekTo(0);
    var buf: [buffer_size * 3]u8 = undefined;
    const len = try stdout.readAll(&buf);

    try testing.expectEqualStrings("foo" ** buffer_size, buf[0..len]);
}
