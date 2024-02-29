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
    self.headers.deinit();
}

// Gets the first value for a given header identified by `name`.
pub fn getFirstValue(self: *Self, name: []const u8) ?[]const u8 {
    for (self.headers.items) |header| {
        if (std.mem.eql(u8, header.name, name)) return header.value;
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
