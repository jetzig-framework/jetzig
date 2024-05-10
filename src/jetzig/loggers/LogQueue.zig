const std = @import("std");

const List = std.DoublyLinkedList([]const u8);
allocator: std.mem.Allocator,
list: *List,
read_write_mutex: *std.Thread.Mutex,
condition: *std.Thread.Condition,
condition_mutex: *std.Thread.Mutex,
writer: *Writer = undefined,
reader: *Reader = undefined,
pool: std.ArrayList(*List.Node),
position: usize,
is_tty: bool = undefined,

const LogQueue = @This();

pub fn init(allocator: std.mem.Allocator) !LogQueue {
    const list = try allocator.create(std.DoublyLinkedList([]const u8));
    list.* = .{};

    return .{
        .allocator = allocator,
        .list = list,
        .condition = try allocator.create(std.Thread.Condition),
        .condition_mutex = try allocator.create(std.Thread.Mutex),
        .read_write_mutex = try allocator.create(std.Thread.Mutex),
        .pool = std.ArrayList(*List.Node).init(allocator),
        .position = 0,
    };
}

pub fn setFile(self: *LogQueue, file: std.fs.File) !void {
    self.writer = try self.allocator.create(Writer);
    self.writer.* = Writer{ .file = file, .queue = self };
    self.reader = try self.allocator.create(Reader);
    self.reader.* = Reader{ .file = file, .queue = self };
    self.is_tty = file.isTty();
}

/// Writer for `LogQueue`. Receives log events and publishes to the queue.
pub const Writer = struct {
    file: std.fs.File,
    queue: *LogQueue,

    /// True if target output file is a TTY.
    pub fn isTty(self: Writer) bool {
        return self.file.isTty();
    }

    /// Print a log event.
    pub fn print(self: *Writer, comptime message: []const u8, args: anytype) !void {
        const output = try std.fmt.allocPrint(self.queue.allocator, message, args);
        try self.queue.append(output);
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
                defer self.queue.allocator.free(message);
                try writer.writeAll(message);
            }

            if (!self.file.isTty()) try self.file.sync();
        }
    }
};

// Append a log event to the queue. Signal the publish loop thread to wake up. Recycle nodes if
// available in the pool, otherwise create a new one.
fn append(self: *LogQueue, message: []const u8) !void {
    self.read_write_mutex.lock();
    defer self.read_write_mutex.unlock();

    const node = if (self.position >= self.pool.items.len) blk: {
        break :blk try self.allocator.create(List.Node);
    } else blk: {
        break :blk self.pool.items[self.position];
    };
    self.position += 1;

    node.* = .{ .data = message };
    self.list.append(node);

    self.condition.signal();
}

// Pop a log event from the queue. Return node to the pool for re-use.
fn popFirst(self: *LogQueue) !?[]const u8 {
    self.read_write_mutex.lock();
    defer self.read_write_mutex.unlock();

    if (self.list.popFirst()) |node| {
        const value = node.data;
        self.position -= 1;
        if (self.position < self.pool.items.len) {
            self.pool.items[self.position] = node;
        } else {
            try self.pool.append(node); // TODO: Set a maximum here to avoid never-ending inflation.
        }
        return value;
    } else {
        return null;
    }
}
