const std = @import("std");

const httpz = @import("httpz");

const jetzig = @import("../../jetzig.zig");

allocator: std.mem.Allocator,
httpz_headers: *HttpzKeyValue,
new_headers: std.ArrayList(Header),

const Headers = @This();
const Header = struct { name: []const u8, value: []const u8 };
const HttpzKeyValue = std.meta.fieldInfo(httpz.Request, std.meta.FieldEnum(httpz.Request).headers).type;
const max_bytes_header_name = jetzig.config.get(u8, "max_bytes_header_name");

pub fn init(allocator: std.mem.Allocator, httpz_headers: *HttpzKeyValue) Headers {
    return .{
        .allocator = allocator,
        .httpz_headers = httpz_headers,
        .new_headers = std.ArrayList(Header).init(allocator),
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
    var headers = std.ArrayList([]const u8).init(self.allocator);

    for (self.httpz_headers.keys, 0..) |key, index| {
        var buf: [max_bytes_header_name]u8 = undefined;
        const lower = std.ascii.lowerString(&buf, name);

        if (std.mem.eql(u8, lower, key)) headers.append(self.httpz_headers.values[index]) catch @panic("OOM");
    }
    return headers.toOwnedSlice() catch @panic("OOM");
}

/// Deprecated
pub fn getFirstValue(self: *const Headers, name: []const u8) ?[]const u8 {
    return self.get(name);
}

/// Add `name` and `value` to headers.
pub fn append(self: *Headers, name: []const u8, value: []const u8) !void {
    if (self.httpz_headers.len >= self.httpz_headers.keys.len) return error.JetzigTooManyHeaders;

    var buf: [max_bytes_header_name]u8 = undefined;
    const lower = std.ascii.lowerString(&buf, name);

    const header = .{
        .name = try self.allocator.dupe(u8, lower),
        .value = try self.allocator.dupe(u8, value),
    };

    try self.new_headers.append(header);
    self.httpz_headers.add(header.name, header.value);
}

test "append (deprecated)" {
    const allocator = std.testing.allocator;
    var headers = Headers.init(allocator, try HttpzKeyValue.init(allocator, 10));
    defer headers.deinit();
    try headers.append("foo", "bar");
    try std.testing.expectEqualStrings(headers.get("foo").?, "bar");
}

test "add" {
    const allocator = std.testing.allocator;
    var headers = Headers.init(allocator, try HttpzKeyValue.init(allocator, 10));
    defer headers.deinit();
    try headers.append("foo", "bar");
    try std.testing.expectEqualStrings(headers.get("foo").?, "bar");
}

test "get with multiple headers (bugfix regression test)" {
    const allocator = std.testing.allocator;
    var headers = Headers.init(allocator, try HttpzKeyValue.init(allocator, 10));
    defer headers.deinit();
    try headers.append("foo", "bar");
    try headers.append("bar", "baz");
    try std.testing.expectEqualStrings(headers.get("bar").?, "baz");
}

test "getAll" {
    const allocator = std.testing.allocator;
    var headers = Headers.init(allocator, try HttpzKeyValue.init(allocator, 10));
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
    var headers = Headers.init(allocator, try HttpzKeyValue.init(allocator, 10));
    defer headers.deinit();
    for (0..10) |_| try headers.append("foo", "bar");

    try std.testing.expectError(error.JetzigTooManyHeaders, headers.append("foo", "bar"));
}

test "case-insensitive matching" {
    const allocator = std.testing.allocator;
    var headers = Headers.init(allocator, try HttpzKeyValue.init(allocator, 10));
    defer headers.deinit();
    try headers.append("Content-Type", "bar");
    try std.testing.expectEqualStrings(headers.get("content-type").?, "bar");
}
