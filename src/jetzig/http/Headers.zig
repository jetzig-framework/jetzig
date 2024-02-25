const std = @import("std");

allocator: std.mem.Allocator,
std_headers: std.http.Headers,

const Self = @This();

pub fn init(allocator: std.mem.Allocator, headers: std.http.Headers) Self {
    return .{ .allocator = allocator, .std_headers = headers };
}

pub fn deinit(self: *Self) void {
    self.std_headers.deinit();
}

// Gets the first value for a given header identified by `name`.
pub fn getFirstValue(self: *Self, name: []const u8) ?[]const u8 {
    return self.std_headers.getFirstValue(name);
}

/// Appends `name` and `value` to headers.
pub fn append(self: *Self, name: []const u8, value: []const u8) !void {
    try self.std_headers.append(name, value);
}

/// Returns an iterator which implements `next()` returning each name/value of the stored headers.
pub fn iterator(self: *Self) Iterator {
    return Iterator{ .std_headers = self.std_headers };
}

const Iterator = struct {
    std_headers: std.http.Headers,
    index: usize = 0,

    const Header = struct {
        name: []const u8,
        value: []const u8,
    };

    /// Returns the next item in the current iteration of headers.
    pub fn next(self: *Iterator) ?Header {
        if (self.std_headers.list.items.len > self.index) {
            const std_header = self.std_headers.list.items[self.index];
            self.index += 1;
            return .{ .name = std_header.name, .value = std_header.value };
        } else {
            return null;
        }
    }
};

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
