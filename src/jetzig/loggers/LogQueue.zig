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

pub const Writer = struct {
    file: std.fs.File,
    queue: *LogQueue,

    pub fn isTty(self: Writer) bool {
        return self.file.isTty();
    }

    pub fn print(self: *Writer, comptime message: []const u8, args: anytype) !void {
        const output = try std.fmt.allocPrint(self.queue.allocator, message, args);
        try self.queue.append(output);
    }
};

pub const Reader = struct {
    file: std.fs.File,
    queue: *LogQueue,

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

pub fn append(self: *LogQueue, message: []const u8) !void {
    self.read_write_mutex.lock();
    defer self.read_write_mutex.unlock();

    const node = if (self.position >= self.pool.items.len) blk: {
        self.position += 1;
        break :blk try self.allocator.create(List.Node);
    } else blk: {
        self.position += 1;
        break :blk self.pool.items[self.position - 1];
    };

    node.* = .{ .data = message };
    self.list.append(node);

    self.condition.signal();
}

pub fn popFirst(self: *LogQueue) !?[]const u8 {
    self.read_write_mutex.lock();
    defer self.read_write_mutex.unlock();

    if (self.list.popFirst()) |node| {
        const value = node.data;
        self.position -= 1;
        if (self.position < self.pool.items.len) {
            self.pool.items[self.position] = node;
        } else {
            try self.pool.append(node);
        }
        return value;
    } else {
        return null;
    }
}
