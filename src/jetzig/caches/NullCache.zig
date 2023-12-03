const std = @import("std");

const http = @import("../http.zig");
const Result = @import("Result.zig");

const Self = @This();

allocator: std.mem.Allocator,

pub fn init(allocator: std.mem.Allocator) Self {
    return Self{ .allocator = allocator };
}

pub fn deinit(self: *const Self) void {
    _ = self;
}

pub fn get(self: *const Self, key: []const u8) ?Result {
    _ = key;
    _ = self;
    return null;
}

pub fn put(self: *const Self, key: []const u8, value: http.Response) !Result {
    _ = key;
    return Result{ .value = value, .cached = false, .allocator = self.allocator };
}
