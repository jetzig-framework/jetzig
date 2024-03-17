const std = @import("std");

allocator: std.mem.Allocator,
headers: HeadersArray,

const Self = @This();
pub const max_headers = 25;
const HeadersArray = std.ArrayListUnmanaged(std.http.Header);

pub fn init(allocator: std.mem.Allocator) Self {
    return .{
        .allocator = allocator,
        .headers = HeadersArray.initCapacity(allocator, max_headers) catch @panic("OOM"),
    };
}

pub fn deinit(self: *Self) void {
    self.headers.deinit(self.allocator);
}

// Gets the first value for a given header identified by `name`. Case-insensitive string comparison.
pub fn getFirstValue(self: *Self, name: []const u8) ?[]const u8 {
    headers: for (self.headers.items) |header| {
        if (name.len != header.name.len) continue;
        for (name, header.name) |expected, actual| {
            if (std.ascii.toLower(expected) != std.ascii.toLower(actual)) continue :headers;
        }
        return header.value;
    }
    return null;
}

/// Appends `name` and `value` to headers.
pub fn append(self: *Self, name: []const u8, value: []const u8) !void {
    self.headers.appendAssumeCapacity(.{ .name = name, .value = value });
}

/// Returns an iterator which implements `next()` returning each name/value of the stored headers.
pub fn iterator(self: *Self) Iterator {
    return Iterator{ .headers = self.headers };
}

/// Returns an array of `std.http.Header`, can be used to set response headers directly.
/// Caller owns memory.
pub fn stdHeaders(self: *Self) !std.ArrayListUnmanaged(std.http.Header) {
    var array = try std.ArrayListUnmanaged(std.http.Header).initCapacity(self.allocator, max_headers);

    var it = self.iterator();
    while (it.next()) |header| {
        array.appendAssumeCapacity(.{ .name = header.name, .value = header.value });
    }
    return array;
}

/// Iterates through stored headers yielidng a `Header` on each call to `next()`
const Iterator = struct {
    headers: HeadersArray,
    index: usize = 0,

    const Header = struct {
        name: []const u8,
        value: []const u8,
    };

    /// Returns the next item in the current iteration of headers.
    pub fn next(self: *Iterator) ?Header {
        if (self.headers.items.len > self.index) {
            const std_header = self.headers.items[self.index];
            self.index += 1;
            return .{ .name = std_header.name, .value = std_header.value };
        } else {
            return null;
        }
    }
};

test "append" {
    const allocator = std.testing.allocator;
    var headers = Self.init(allocator);
    defer headers.deinit();
    try headers.append("foo", "bar");
    try std.testing.expectEqualStrings(headers.getFirstValue("foo").?, "bar");
}

test "getFirstValue with multiple headers (bugfix regression test)" {
    const allocator = std.testing.allocator;
    var headers = Self.init(allocator);
    defer headers.deinit();
    try headers.append("foo", "bar");
    try headers.append("bar", "baz");
    try std.testing.expectEqualStrings(headers.getFirstValue("bar").?, "baz");
}

test "case-insensitive matching" {
    const allocator = std.testing.allocator;
    var headers = Self.init(allocator);
    defer headers.deinit();
    try headers.append("Content-Type", "bar");
    try std.testing.expectEqualStrings(headers.getFirstValue("content-type").?, "bar");
}

test "iterator" {
    const allocator = std.testing.allocator;
    var headers = Self.init(allocator);
    defer headers.deinit();

    try headers.append("foo", "bar");

    var it = headers.iterator();
    while (it.next()) |header| {
        try std.testing.expectEqualStrings("foo", header.name);
        try std.testing.expectEqualStrings("bar", header.value);
        break;
    } else {
        try std.testing.expect(false);
    }
}

test "stdHeaders" {
    const allocator = std.testing.allocator;
    var headers = Self.init(allocator);
    defer headers.deinit();

    try headers.append("foo", "bar");
    try headers.append("baz", "qux");

    var std_headers = try headers.stdHeaders();
    defer std_headers.deinit(allocator);

    try std.testing.expectEqualStrings("foo", std_headers.items[0].name);
    try std.testing.expectEqualStrings("bar", std_headers.items[0].value);
    try std.testing.expectEqualStrings("baz", std_headers.items[1].name);
    try std.testing.expectEqualStrings("qux", std_headers.items[1].value);
}
