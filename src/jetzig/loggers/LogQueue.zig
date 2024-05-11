const std = @import("std");

const jetzig = @import("../../jetzig.zig");

const List = std.DoublyLinkedList(Event);
const buffer_size = jetzig.config.get(usize, "log_message_buffer_len");

allocator: std.mem.Allocator,
list: List,
read_write_mutex: *std.Thread.Mutex,
condition: *std.Thread.Condition,
condition_mutex: *std.Thread.Mutex,
writer: *Writer = undefined,
reader: *Reader = undefined,
node_pool: std.ArrayList(*List.Node),
buffer_pool: std.ArrayList(*[buffer_size:0]u8),
position: usize,
stdout_is_tty: bool = undefined,
stderr_is_tty: bool = undefined,
state: enum { pending, ready } = .pending,

const LogQueue = @This();

pub const Target = enum { stdout, stderr };

const Event = struct {
    message: *[buffer_size:0]u8,
    len: usize,
    target: Target,
    ptr: ?[]const u8,
};

pub fn init(allocator: std.mem.Allocator) !LogQueue {
    return .{
        .allocator = allocator,
        .list = List{},
        .condition = try allocator.create(std.Thread.Condition),
        .condition_mutex = try allocator.create(std.Thread.Mutex),
        .read_write_mutex = try allocator.create(std.Thread.Mutex),
        .node_pool = std.ArrayList(*List.Node).init(allocator),
        .buffer_pool = std.ArrayList(*[buffer_size:0]u8).init(allocator),
        .position = 0,
    };
}

/// Set the stdout and stderr outputs.
pub fn setFiles(self: *LogQueue, stdout_file: std.fs.File, stderr_file: std.fs.File) !void {
    self.writer = try self.allocator.create(Writer);
    self.writer.* = Writer{
        .queue = self,
        .mutex = try self.allocator.create(std.Thread.Mutex),
    };
    self.reader = try self.allocator.create(Reader);
    self.reader.* = Reader{
        .stdout_file = stdout_file,
        .stderr_file = stderr_file,
        .queue = self,
    };
    self.stdout_is_tty = stdout_file.isTty();
    self.stderr_is_tty = stderr_file.isTty();
    self.state = .ready;
}

/// Writer for `LogQueue`. Receives log events and publishes to the queue.
pub const Writer = struct {
    queue: *LogQueue,
    position: usize = 0,
    mutex: *std.Thread.Mutex,

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
        std.debug.assert(self.queue.state == .ready);

        self.mutex.lock();
        defer self.mutex.unlock();

        const buf = try self.getBuffer();
        self.position += 1;
        var ptr: ?[]const u8 = null;

        const result = std.fmt.bufPrintZ(buf, message, args) catch |err| switch (err) {
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

    fn getBuffer(self: *Writer) !*[buffer_size:0]u8 {
        const buffer = if (self.position >= self.queue.buffer_pool.items.len)
            try self.queue.allocator.create([buffer_size:0]u8)
        else
            self.queue.buffer_pool.items[self.position];

        return buffer;
    }
};

/// Reader for `LogQueue`. Reads log events from the queue.
pub const Reader = struct {
    stdout_file: std.fs.File,
    stderr_file: std.fs.File,
    queue: *LogQueue,

    /// Publish log events from the queue. Invoke from a dedicated thread. Sleeps when log queue
    /// is empty, wakes up when a new event is published.
    pub fn publish(self: *Reader) !void {
        std.debug.assert(self.queue.state == .ready);

        const stdout_writer = self.stdout_file.writer();
        const stderr_writer = self.stderr_file.writer();

        while (true) {
            self.queue.condition_mutex.lock();
            defer self.queue.condition_mutex.unlock();

            self.queue.condition.wait(self.queue.condition_mutex);

            var stdout_written = false;
            var stderr_written = false;

            while (try self.queue.popFirst()) |event| {
                self.queue.writer.mutex.lock();
                defer self.queue.writer.mutex.unlock();

                const writer = switch (event.target) {
                    .stdout => blk: {
                        stdout_written = true;
                        break :blk stdout_writer;
                    },
                    .stderr => blk: {
                        stderr_written = true;
                        break :blk stderr_writer;
                    },
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
                    try self.queue.buffer_pool.append(event.message); // TODO: Prevent unlimited inflation
                }
            }

            if (stdout_written and !self.queue.stdout_is_tty) try self.stdout_file.sync();
            if (stderr_written and !self.queue.stderr_is_tty) try self.stderr_file.sync();
        }
    }
};

// Append a log event to the queue. Signal the publish loop thread to wake up. Recycle nodes if
// available in the pool, otherwise create a new one.
fn append(self: *LogQueue, event: Event) !void {
    self.read_write_mutex.lock();
    defer self.read_write_mutex.unlock();

    const node = if (self.position >= self.node_pool.items.len)
        try self.allocator.create(List.Node)
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
            try self.node_pool.append(node); // TODO: Set a maximum here to avoid never-ending inflation.
        }
        return value;
    } else {
        return null;
    }
}

test "setFiles" {
    var log_queue = try LogQueue.init(std.testing.allocator);

    var tmp_dir = std.testing.tmpDir(.{});
    defer tmp_dir.cleanup();

    const stdout = tmp_dir.dir.createFile("stdout.log", .{});
    defer stdout.close();

    const stderr = tmp_dir.dir.createFile("stderr.log", .{});
    defer stderr.close();

    try log_queue.setFiles(stdout, stderr);
}
