const std = @import("std");
const jetzig = @import("../../jetzig.zig");

allocator: std.mem.Allocator,
headers: HeadersArray,

const Headers = @This();
pub const max_headers = 25;
const HeadersArray = std.ArrayListUnmanaged(std.http.Header);

pub fn init(allocator: std.mem.Allocator) Headers {
    return .{
        .allocator = allocator,
        .headers = HeadersArray.initCapacity(allocator, max_headers) catch @panic("OOM"),
    };
}

pub fn deinit(self: *Headers) void {
    self.headers.deinit(self.allocator);
}

/// Gets the first value for a given header identified by `name`. Names are case insensitive.
pub fn get(self: Headers, name: []const u8) ?[]const u8 {
    for (self.headers.items) |header| {
        if (jetzig.util.equalStringsCaseInsensitive(name, header.name)) return header.value;
    }
    return null;
}

/// Gets the first value for a given header identified by `name`. Names are case insensitive.
pub fn getAll(self: Headers, name: []const u8) []const []const u8 {
    var headers = std.ArrayList([]const u8).init(self.allocator);

    for (self.headers.items) |header| {
        if (jetzig.util.equalStringsCaseInsensitive(name, header.name)) {
            headers.append(header.value) catch @panic("OOM");
        }
    }
    return headers.toOwnedSlice() catch @panic("OOM");
}

// Deprecated
pub fn getFirstValue(self: *const Headers, name: []const u8) ?[]const u8 {
    return self.get(name);
}

/// Appends `name` and `value` to headers.
pub fn append(self: *Headers, name: []const u8, value: []const u8) !void {
    if (self.headers.items.len >= 25) return error.JetzigTooManyHeaders;

    self.headers.appendAssumeCapacity(.{ .name = name, .value = value });
}

/// Removes **all** header entries matching `name`. Names are case-insensitive.
pub fn remove(self: *Headers, name: []const u8) void {
    if (self.headers.items.len == 0) return;

    var index: usize = self.headers.items.len;

    while (index > 0) {
        index -= 1;
        if (jetzig.util.equalStringsCaseInsensitive(name, self.headers.items[index].name)) {
            _ = self.headers.orderedRemove(index);
        }
    }
}

/// Returns an iterator which implements `next()` returning each name/value of the stored headers.
pub fn iterator(self: Headers) Iterator {
    return Iterator{ .headers = self.headers };
}

/// Returns an array of `std.http.Header`, can be used to set response headers directly.
/// Caller owns memory.
pub fn stdHeaders(self: *Headers) !std.ArrayListUnmanaged(std.http.Header) {
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
    var headers = Headers.init(allocator);
    defer headers.deinit();
    try headers.append("foo", "bar");
    try std.testing.expectEqualStrings(headers.getFirstValue("foo").?, "bar");
}

test "get with multiple headers (bugfix regression test)" {
    const allocator = std.testing.allocator;
    var headers = Headers.init(allocator);
    defer headers.deinit();
    try headers.append("foo", "bar");
    try headers.append("bar", "baz");
    try std.testing.expectEqualStrings(headers.get("bar").?, "baz");
}

test "getAll" {
    const allocator = std.testing.allocator;
    var headers = Headers.init(allocator);
    defer headers.deinit();
    try headers.append("foo", "bar");
    try headers.append("foo", "baz");
    try headers.append("bar", "qux");
    const all = headers.getAll("foo");
    defer allocator.free(all);
    try std.testing.expectEqualSlices([]const u8, all, &[_][]const u8{ "bar", "baz" });
}

test "append too many headers" {
    const allocator = std.testing.allocator;
    var headers = Headers.init(allocator);
    defer headers.deinit();
    for (0..25) |_| try headers.append("foo", "bar");

    try std.testing.expectError(error.JetzigTooManyHeaders, headers.append("foo", "bar"));
}

test "case-insensitive matching" {
    const allocator = std.testing.allocator;
    var headers = Headers.init(allocator);
    defer headers.deinit();
    try headers.append("Content-Type", "bar");
    try std.testing.expectEqualStrings(headers.getFirstValue("content-type").?, "bar");
}

test "iterator" {
    const allocator = std.testing.allocator;
    var headers = Headers.init(allocator);
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

test "remove" {
    const allocator = std.testing.allocator;
    var headers = Headers.init(allocator);
    defer headers.deinit();
    try headers.append("foo", "baz");
    try headers.append("foo", "qux");
    try headers.append("bar", "quux");
    headers.remove("Foo"); // Headers are case-insensitive.
    try std.testing.expect(headers.getFirstValue("foo") == null);
    try std.testing.expectEqualStrings(headers.getFirstValue("bar").?, "quux");
}

test "stdHeaders" {
    const allocator = std.testing.allocator;
    var headers = Headers.init(allocator);
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
