const std = @import("std");

const List = std.DoublyLinkedList(*[buffer_size:0]u8);
const buffer_size = 4096;

allocator: std.mem.Allocator,
list: *List,
read_write_mutex: *std.Thread.Mutex,
condition: *std.Thread.Condition,
condition_mutex: *std.Thread.Mutex,
writer: *Writer = undefined,
reader: *Reader = undefined,
node_pool: std.ArrayList(*List.Node),
buffer_pool: std.ArrayList(*[buffer_size:0]u8),
position: usize,
is_tty: bool = undefined,

const LogQueue = @This();

pub fn init(allocator: std.mem.Allocator) !LogQueue {
    const list = try allocator.create(std.DoublyLinkedList(*[buffer_size:0]u8));
    list.* = .{};

    return .{
        .allocator = allocator,
        .list = list,
        .condition = try allocator.create(std.Thread.Condition),
        .condition_mutex = try allocator.create(std.Thread.Mutex),
        .read_write_mutex = try allocator.create(std.Thread.Mutex),
        .node_pool = std.ArrayList(*List.Node).init(allocator),
        .buffer_pool = std.ArrayList(*[buffer_size:0]u8).init(allocator),
        .position = 0,
    };
}

pub fn setFile(self: *LogQueue, file: std.fs.File) !void {
    self.writer = try self.allocator.create(Writer);
    self.writer.* = Writer{ .file = file, .queue = self, .mutex = try self.allocator.create(std.Thread.Mutex) };
    self.reader = try self.allocator.create(Reader);
    self.reader.* = Reader{ .file = file, .queue = self };
    self.is_tty = file.isTty();
}

/// Writer for `LogQueue`. Receives log events and publishes to the queue.
pub const Writer = struct {
    file: std.fs.File,
    queue: *LogQueue,
    position: usize = 0,
    mutex: *std.Thread.Mutex,

    /// True if target output file is a TTY.
    pub fn isTty(self: Writer) bool {
        return self.file.isTty();
    }

    /// Print a log event.
    pub fn print(self: *Writer, comptime message: []const u8, args: anytype) !void {
        self.mutex.lock();
        defer self.mutex.unlock();

        const buf = try self.getBuffer();
        self.position += 1;
        _ = try std.fmt.bufPrintZ(buf, message, args);
        try self.queue.append(buf);
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
    file: std.fs.File,
    queue: *LogQueue,

    /// Publish log events from the queue. Invoke from a dedicated thread. Sleeps when log queue
    /// is empty, wakes up when a new event is published.
    pub fn publish(self: *Reader) !void {
        const writer = self.file.writer();
        while (true) {
            self.queue.condition_mutex.lock();
            defer self.queue.condition_mutex.unlock();

            self.queue.condition.wait(self.queue.condition_mutex);

            while (try self.queue.popFirst()) |message| {
                self.queue.writer.mutex.lock();
                defer self.queue.writer.mutex.unlock();

                try writer.writeAll(message[0..std.mem.indexOfSentinel(u8, 0, message)]);
                self.queue.writer.position -= 1;
                if (self.queue.writer.position < self.queue.buffer_pool.items.len) {
                    self.queue.buffer_pool.items[self.queue.writer.position] = message;
                } else {
                    try self.queue.buffer_pool.append(message);
                }
            }

            if (!self.file.isTty()) try self.file.sync();
        }
    }
};

// Append a log event to the queue. Signal the publish loop thread to wake up. Recycle nodes if
// available in the pool, otherwise create a new one.
fn append(self: *LogQueue, message: *[buffer_size:0]u8) !void {
    self.read_write_mutex.lock();
    defer self.read_write_mutex.unlock();

    const node = if (self.position >= self.node_pool.items.len)
        try self.allocator.create(List.Node)
    else
        self.node_pool.items[self.position];

    self.position += 1;

    node.* = .{ .data = message };
    self.list.append(node);

    self.condition.signal();
}

// Pop a log event from the queue. Return node to the pool for re-use.
fn popFirst(self: *LogQueue) !?*[buffer_size:0]u8 {
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
