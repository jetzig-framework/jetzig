const std = @import("std");
const builtin = @import("builtin");

const jetzig = @import("../../jetzig.zig");

const buffer_size = jetzig.config.get(usize, "log_message_buffer_len");
const max_pool_len = jetzig.config.get(usize, "max_log_pool_len");

const List = std.DoublyLinkedList(Event);
const Buffer = [buffer_size]u8;

allocator: std.mem.Allocator,
node_allocator: std.heap.MemoryPool(List.Node),
buffer_allocator: std.heap.MemoryPool(Buffer),
list: List,
read_write_mutex: std.Thread.Mutex,
condition: std.Thread.Condition,
condition_mutex: std.Thread.Mutex,
writer: Writer = undefined,
reader: Reader = undefined,
node_pool: std.ArrayList(*List.Node),
buffer_pool: std.ArrayList(*Buffer),
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
pub fn init(allocator: std.mem.Allocator) LogQueue {
    return .{
        .allocator = allocator,
        .node_allocator = initPool(allocator, List.Node),
        .buffer_allocator = initPool(allocator, Buffer),
        .list = List{},
        .condition = std.Thread.Condition{},
        .condition_mutex = std.Thread.Mutex{},
        .read_write_mutex = std.Thread.Mutex{},
        .node_pool = std.ArrayList(*List.Node).init(allocator),
        .buffer_pool = std.ArrayList(*Buffer).init(allocator),
        .position = 0,
    };
}

/// Free allocated resources and return to `pending` state.
pub fn deinit(self: *LogQueue) void {
    self.node_pool.deinit();
    self.buffer_pool.deinit();

    self.buffer_allocator.deinit();
    self.node_allocator.deinit();

    self.state = .pending;
}

/// Set the stdout and stderr outputs. Must be called before `print`.
pub fn setFiles(self: *LogQueue, stdout_file: std.fs.File, stderr_file: std.fs.File) !void {
    self.writer = Writer{
        .queue = self,
        .mutex = std.Thread.Mutex{},
    };
    self.reader = Reader{
        .stdout_file = stdout_file,
        .stderr_file = stderr_file,
        .queue = self,
    };
    self.stdout_is_tty = stdout_file.isTty();
    self.stderr_is_tty = stderr_file.isTty();

    self.stdout_colorize = std.io.tty.detectConfig(stdout_file) != .no_color;
    self.stderr_colorize = std.io.tty.detectConfig(stderr_file) != .no_color;

    self.state = .ready;
}

pub fn print(self: *LogQueue, comptime message: []const u8, args: anytype, target: Target) !void {
    std.debug.assert(self.state == .ready);

    try self.writer.print(message, args, target);
}

/// Writer for `LogQueue`. Receives log events and publishes to the queue.
pub const Writer = struct {
    queue: *LogQueue,
    position: usize = 0,
    mutex: std.Thread.Mutex,

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
    stdout_file: std.fs.File,
    stderr_file: std.fs.File,
    queue: *LogQueue,

    pub const PublishOptions = struct {
        oneshot: bool = false,
    };

    /// Publish log events from the queue. Invoke from a dedicated thread. Sleeps when log queue
    /// is empty, wakes up when a new event is published.
    pub fn publish(self: *Reader, options: PublishOptions) !void {
        std.debug.assert(self.queue.state == .ready);

        const stdout_writer = self.stdout_file.writer();
        const stderr_writer = self.stderr_file.writer();

        while (true) {
            self.queue.condition_mutex.lock();
            defer self.queue.condition_mutex.unlock();

            if (!options.oneshot) self.queue.condition.wait(&self.queue.condition_mutex);

            var stdout_written = false;
            var stderr_written = false;
            var file: std.fs.File = undefined;

            while (try self.queue.popFirst()) |event| {
                self.queue.writer.mutex.lock();
                defer self.queue.writer.mutex.unlock();

                switch (event.target) {
                    .stdout => {
                        stdout_written = true;
                        if (builtin.os.tag == .windows) {
                            file = self.stdout_file;
                        }
                    },
                    .stderr => {
                        stderr_written = true;
                        if (builtin.os.tag == .windows) {
                            file = self.stderr_file;
                        }
                    },
                }

                const writer = switch (event.target) {
                    .stdout => stdout_writer,
                    .stderr => stderr_writer,
                };

                if (event.ptr) |ptr| {
                    // Log message spilled to heap
                    defer self.queue.allocator.free(ptr);
                    try writer.writeAll(ptr);
                    continue;
                }

                try writer.writeAll(event.message[0..event.len]);

                self.queue.writer.position -= 1;

                if (self.queue.writer.position < self.queue.buffer_pool.items.len) {
                    self.queue.buffer_pool.items[self.queue.writer.position] = event.message;
                } else {
                    if (self.queue.buffer_pool.items.len >= max_pool_len) {
                        self.queue.buffer_allocator.destroy(@alignCast(event.message));
                        self.queue.writer.position += 1;
                    } else {
                        try self.queue.buffer_pool.append(event.message);
                    }
                }
            }

            if (stdout_written and !self.queue.stdout_is_tty) try self.stdout_file.sync();
            if (stderr_written and !self.queue.stderr_is_tty) try self.stderr_file.sync();

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

    node.* = .{ .data = event };
    self.list.append(node);

    self.condition.signal();
}

// Pop a log event from the queue. Return node to the pool for re-use.
fn popFirst(self: *LogQueue) !?Event {
    self.read_write_mutex.lock();
    defer self.read_write_mutex.unlock();

    if (self.list.popFirst()) |node| {
        const value = node.data;
        self.position -= 1;
        if (self.position < self.node_pool.items.len) {
            self.node_pool.items[self.position] = node;
        } else {
            if (self.node_pool.items.len >= max_pool_len) {
                self.node_allocator.destroy(node);
                self.position += 1;
            } else {
                try self.node_pool.append(node);
            }
        }
        return value;
    } else {
        return null;
    }
}

fn initPool(allocator: std.mem.Allocator, T: type) std.heap.MemoryPool(T) {
    return std.heap.MemoryPool(T).initPreheated(allocator, max_pool_len) catch @panic("OOM");
}

test "print to stdout and stderr" {
    var log_queue = LogQueue.init(std.testing.allocator);
    defer log_queue.deinit();

    var tmp_dir = std.testing.tmpDir(.{});
    defer tmp_dir.cleanup();

    const stdout = try tmp_dir.dir.createFile("stdout.log", .{ .read = true });
    defer stdout.close();

    const stderr = try tmp_dir.dir.createFile("stderr.log", .{ .read = true });
    defer stderr.close();

    try log_queue.setFiles(stdout, stderr);
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

    try std.testing.expectEqualStrings(
        \\foo bar
        \\quux corge
        \\plugh zyzzy
        \\
    , buf[0..len]);

    try stderr.seekTo(0);
    len = try stderr.readAll(&buf);
    try std.testing.expectEqualStrings(
        \\baz qux
        \\grault garply
        \\waldo fred
        \\
    , buf[0..len]);
}

test "long messages" {
    var log_queue = LogQueue.init(std.testing.allocator);
    defer log_queue.deinit();

    var tmp_dir = std.testing.tmpDir(.{});
    defer tmp_dir.cleanup();

    const stdout = try tmp_dir.dir.createFile("stdout.log", .{ .read = true });
    defer stdout.close();

    const stderr = try tmp_dir.dir.createFile("stderr.log", .{ .read = true });
    defer stderr.close();

    try log_queue.setFiles(stdout, stderr);
    try log_queue.print("foo" ** buffer_size, .{}, .stdout);

    try log_queue.reader.publish(.{ .oneshot = true });

    try stdout.seekTo(0);
    var buf: [buffer_size * 3]u8 = undefined;
    const len = try stdout.readAll(&buf);

    try std.testing.expectEqualStrings("foo" ** buffer_size, buf[0..len]);
}
