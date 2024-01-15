const std = @import("std");

const jetzig = @import("../../jetzig.zig");

allocator: std.mem.Allocator,
cookie_string: []const u8,
buf: std.ArrayList(u8),
cookies: std.StringArrayHashMap(*Cookie),

const Self = @This();

pub const Cookie = struct {
    value: []const u8,
};

pub fn init(allocator: std.mem.Allocator, cookie_string: []const u8) Self {
    return .{
        .allocator = allocator,
        .cookie_string = cookie_string,
        .cookies = std.StringArrayHashMap(*Cookie).init(allocator),
        .buf = std.ArrayList(u8).init(allocator),
    };
}

pub fn deinit(self: *Self) void {
    var it = self.cookies.iterator();
    while (it.next()) |item| {
        self.allocator.free(item.key_ptr.*);
        self.allocator.free(item.value_ptr.*.value);
        self.allocator.destroy(item.value_ptr.*);
    }
    self.cookies.deinit();
    self.buf.deinit();
}

pub fn get(self: *Self, key: []const u8) ?*Cookie {
    return self.cookies.get(key);
}

pub fn put(self: *Self, key: []const u8, value: Cookie) !void {
    if (self.cookies.fetchSwapRemove(key)) |entry| {
        self.allocator.free(entry.key);
        self.allocator.free(entry.value.value);
        self.allocator.destroy(entry.value);
    }
    const ptr = try self.allocator.create(Cookie);
    ptr.* = value;
    ptr.*.value = try self.allocator.dupe(u8, value.value);
    try self.cookies.put(try self.allocator.dupe(u8, key), ptr);
}

pub const HeaderIterator = struct {
    allocator: std.mem.Allocator,
    cookies_iterator: std.StringArrayHashMap(*Cookie).Iterator,

    pub fn init(allocator: std.mem.Allocator, cookies: *Self) HeaderIterator {
        return .{ .allocator = allocator, .cookies_iterator = cookies.cookies.iterator() };
    }

    pub fn next(self: *HeaderIterator) !?[]const u8 {
        if (self.cookies_iterator.next()) |*item| {
            return try std.fmt.allocPrint(
                self.allocator,
                "{s}={s}; path=/; domain=localhost", // TODO: Add all options, remove hardcoded domain
                .{ item.key_ptr.*, item.value_ptr.*.value },
            );
        } else {
            return null;
        }
    }
};

pub fn headerIterator(self: *Self) HeaderIterator {
    var buf = std.ArrayList([]const u8).init(self.allocator);

    defer buf.deinit();
    defer for (buf.items) |item| self.allocator.free(item);

    return HeaderIterator.init(self.allocator, self);
}

// https://datatracker.ietf.org/doc/html/rfc6265#section-4.2.1
// cookie-header = "Cookie:" OWS cookie-string OWS
// cookie-string = cookie-pair *( ";" SP cookie-pair )
pub fn parse(self: *Self) !void {
    var key_buf = std.ArrayList(u8).init(self.allocator);
    var value_buf = std.ArrayList(u8).init(self.allocator);
    var key_terminated = false;
    var value_started = false;

    defer key_buf.deinit();
    defer value_buf.deinit();

    for (self.cookie_string, 0..) |char, index| {
        if (char == '=') {
            key_terminated = true;
            continue;
        }

        if (char == ';' or index == self.cookie_string.len - 1) {
            if (char != ';') try value_buf.append(char);
            try self.put(
                key_buf.items,
                Cookie{ .value = value_buf.items },
            );
            key_buf.clearAndFree();
            value_buf.clearAndFree();
            value_started = false;
            key_terminated = false;
            continue;
        }

        if (!key_terminated and char == ' ') continue;

        if (!key_terminated) {
            try key_buf.append(char);
            continue;
        }

        if (char == ' ' and !value_started) continue;
        if (char != ' ' and !value_started) value_started = true;

        if (key_terminated and value_started) {
            try value_buf.append(char);
            continue;
        }

        unreachable;
    }
}

test "basic cookie string" {
    const allocator = std.testing.allocator;
    var cookies = Self.init(allocator, "foo=bar; baz=qux;");
    defer cookies.deinit();
    try cookies.parse();
    try std.testing.expectEqualStrings("bar", cookies.get("foo").?.value);
    try std.testing.expectEqualStrings("qux", cookies.get("baz").?.value);
}

test "empty cookie string" {
    const allocator = std.testing.allocator;
    var cookies = Self.init(allocator, "");
    defer cookies.deinit();
    try cookies.parse();
}

test "cookie string with irregular spaces" {
    const allocator = std.testing.allocator;
    var cookies = Self.init(allocator, "foo=   bar;     baz=        qux;");
    defer cookies.deinit();
    try cookies.parse();
    try std.testing.expectEqualStrings("bar", cookies.get("foo").?.value);
    try std.testing.expectEqualStrings("qux", cookies.get("baz").?.value);
}

test "headerIterator" {
    const allocator = std.testing.allocator;
    var buf = std.ArrayList(u8).init(allocator);
    defer buf.deinit();

    const writer = buf.writer();

    var cookies = Self.init(allocator, "foo=bar; baz=qux;");
    defer cookies.deinit();
    try cookies.parse();

    var it = cookies.headerIterator();
    while (try it.next()) |*header| {
        try writer.writeAll(header.*);
        try writer.writeAll("\n");
        allocator.free(header.*);
    }

    try std.testing.expectEqualStrings(
        \\foo=bar; path=/; domain=localhost
        \\baz=qux; path=/; domain=localhost
        \\
    , buf.items);
}
