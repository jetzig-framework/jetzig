const std = @import("std");

const http = @import("../http.zig");
const Result = @import("Result.zig");

allocator: std.mem.Allocator,
cache: std.StringHashMap(http.Response),

const Self = @This();

pub fn init(allocator: std.mem.Allocator) Self {
    const cache = std.StringHashMap(http.Response).init(allocator);

    return .{ .allocator = allocator, .cache = cache };
}

pub fn deinit(self: *Self) void {
    var iterator = self.cache.keyIterator();
    while (iterator.next()) |key| {
        self.allocator.free(key.*);
    }
    self.cache.deinit();
}

pub fn get(self: *Self, key: []const u8) ?Result {
    if (self.cache.get(key)) |value| {
        return Result.init(self.allocator, value, true);
    } else {
        return null;
    }
}

pub fn put(self: *Self, key: []const u8, value: http.Response) !Result {
    const key_dupe = try self.allocator.dupe(u8, key);
    const value_dupe = try value.dupe();
    try self.cache.put(key_dupe, value_dupe);

    return Result.init(self.allocator, value_dupe, true);
}
