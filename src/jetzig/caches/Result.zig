const std = @import("std");

const Self = @This();

const jetzig = @import("../../jetzig.zig");

value: jetzig.http.Response,
cached: bool,
allocator: std.mem.Allocator,

pub fn init(allocator: std.mem.Allocator, value: jetzig.http.Response, cached: bool) Self {
    return .{ .allocator = allocator, .cached = cached, .value = value };
}

pub fn deinit(self: *const Self) void {
    if (!self.cached) self.value.deinit();
}
