const std = @import("std");

allocator: std.mem.Allocator,
headers: std.http.Headers,

const Self = @This();

pub fn init(allocator: std.mem.Allocator, headers: std.http.Headers) Self {
    return .{ .allocator = allocator, .headers = headers };
}

pub fn getFirstValue(self: *Self, key: []const u8) ?[]const u8 {
    return self.headers.getFirstValue(key);
}

pub fn append(self: *Self, key: []const u8, value: []const u8) !void {
    try self.headers.append(key, value);
}

test {
    const allocator = std.testing.allocator;
    var headers = std.http.Headers.init(allocator);
    defer headers.deinit();
    try headers.append("foo", "bar");
    var jetzig_headers = Self.init(allocator, headers);
    try std.testing.expectEqualStrings(
        headers.getFirstValue("foo").?,
        jetzig_headers.getFirstValue("foo").?,
    );
}
