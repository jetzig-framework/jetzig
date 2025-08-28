const std = @import("std");

const httpz = @import("httpz");

const jetzig = @import("../../jetzig.zig");

allocator: std.mem.Allocator,
httpz_headers: *httpz.key_value.StringKeyValue,
new_headers: std.array_list.Managed(Header),

const Headers = @This();
const Header = struct { name: []const u8, value: []const u8 };
const max_bytes_header_name = jetzig.config.get(u8, "max_bytes_header_name");

pub fn init(allocator: std.mem.Allocator, httpz_headers: *httpz.key_value.StringKeyValue) Headers {
    return .{
        .allocator = allocator,
        .httpz_headers = httpz_headers,
        .new_headers = std.array_list.Managed(Header).init(allocator),
    };
}

pub fn deinit(self: *Headers) void {
    self.httpz_headers.deinit(self.allocator);

    for (self.new_headers.items) |header| {
        self.allocator.free(header.name);
        self.allocator.free(header.value);
    }

    self.new_headers.deinit();
}

/// Get the first value for a given header identified by `name`. Names are case insensitive.
pub fn get(self: Headers, name: []const u8) ?[]const u8 {
    std.debug.assert(name.len <= max_bytes_header_name);

    var buf: [max_bytes_header_name]u8 = undefined;
    const lower = std.ascii.lowerString(&buf, name);

    return self.httpz_headers.get(lower);
}

/// Get all values for a given header identified by `name`. Names are case insensitive.
pub fn getAll(self: Headers, name: []const u8) []const []const u8 {
    var headers = std.array_list.Managed([]const u8).init(self.allocator);

    for (self.httpz_headers.keys, 0..) |key, index| {
        if (std.ascii.eqlIgnoreCase(name, key)) {
            headers.append(self.httpz_headers.values[index]) catch @panic("OOM");
        }
    }
    return headers.toOwnedSlice() catch @panic("OOM");
}

/// Deprecated
pub fn getFirstValue(self: *const Headers, name: []const u8) ?[]const u8 {
    return self.get(name);
}

pub fn count(self: Headers) usize {
    return self.httpz_headers.len;
}

/// Add `name` and `value` to headers.
pub fn append(self: *Headers, name: []const u8, value: []const u8) !void {
    if (self.httpz_headers.len >= self.httpz_headers.keys.len) return error.JetzigTooManyHeaders;

    var buf: [max_bytes_header_name]u8 = undefined;
    const lower = std.ascii.lowerString(&buf, name);

    const header = Header{
        .name = try self.allocator.dupe(u8, lower),
        .value = try self.allocator.dupe(u8, value),
    };

    try self.new_headers.append(header);
    self.httpz_headers.add(header.name, header.value);
}

const Iterator = struct {
    position: usize = 0,
    headers: Headers,
    filter_name: ?[]const u8 = null,

    pub fn next(self: *Iterator) ?Header {
        const header_count = self.headers.count();
        if (self.position >= header_count) {
            return null;
        }
        const start = self.position;

        var buf: [jetzig.config.get(u16, "max_bytes_header_name")]u8 = undefined;
        const filter_name = if (self.filter_name) |name| std.ascii.lowerString(&buf, name) else null;

        for (start..header_count) |index| {
            const key = self.headers.httpz_headers.keys[start + index];
            const value = self.headers.httpz_headers.values[start + index];
            self.position += 1;
            if (filter_name) |name| {
                if (std.mem.eql(u8, name, key)) {
                    return .{ .name = key, .value = value };
                }
            } else {
                return .{ .name = key, .value = value };
            }
        }

        return null;
    }
};

pub fn getAllIterator(self: Headers, name: []const u8) Iterator {
    return .{ .headers = self, .filter_name = name };
}

pub fn iterator(self: Headers) Iterator {
    return .{ .headers = self };
}

test "append (deprecated)" {
    const allocator = std.testing.allocator;
    var httpz_headers = try httpz.key_value.StringKeyValue.init(allocator, 10);
    var headers = Headers.init(allocator, &httpz_headers);
    defer headers.deinit();
    try headers.append("foo", "bar");
    try std.testing.expectEqualStrings(headers.get("foo").?, "bar");
}

test "add" {
    const allocator = std.testing.allocator;
    var httpz_headers = try httpz.key_value.StringKeyValue.init(allocator, 10);
    var headers = Headers.init(allocator, &httpz_headers);
    defer headers.deinit();
    try headers.append("foo", "bar");
    try std.testing.expectEqualStrings(headers.get("foo").?, "bar");
}

test "get with multiple headers (bugfix regression test)" {
    const allocator = std.testing.allocator;
    var httpz_headers = try httpz.key_value.StringKeyValue.init(allocator, 10);
    var headers = Headers.init(allocator, &httpz_headers);
    defer headers.deinit();
    try headers.append("foo", "bar");
    try headers.append("bar", "baz");
    try std.testing.expectEqualStrings(headers.get("bar").?, "baz");
}

test "getAll" {
    const allocator = std.testing.allocator;
    var httpz_headers = try httpz.key_value.StringKeyValue.init(allocator, 10);
    var headers = Headers.init(allocator, &httpz_headers);
    defer headers.deinit();
    try headers.append("foo", "bar");
    try headers.append("foo", "baz");
    try headers.append("bar", "qux");
    const all = headers.getAll("foo");
    defer allocator.free(all);
    try std.testing.expectEqualDeep(all, &[_][]const u8{ "bar", "baz" });
}

test "add too many headers" {
    const allocator = std.testing.allocator;
    var httpz_headers = try httpz.key_value.StringKeyValue.init(allocator, 10);
    var headers = Headers.init(allocator, &httpz_headers);
    defer headers.deinit();
    for (0..10) |_| try headers.append("foo", "bar");

    try std.testing.expectError(error.JetzigTooManyHeaders, headers.append("foo", "bar"));
}

test "case-insensitive matching" {
    const allocator = std.testing.allocator;
    var httpz_headers = try httpz.key_value.StringKeyValue.init(allocator, 10);
    var headers = Headers.init(allocator, &httpz_headers);
    defer headers.deinit();
    try headers.append("Content-Type", "bar");
    try std.testing.expectEqualStrings(headers.get("content-type").?, "bar");
}
