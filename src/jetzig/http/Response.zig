const std = @import("std");

const http = @import("../http.zig");

const Self = @This();

allocator: std.mem.Allocator,
content: []const u8,
status_code: http.status_codes.StatusCode,

pub fn deinit(self: *const Self) void {
    _ = self;
    // self.allocator.free(self.content);
}

pub fn dupe(self: *const Self) !Self {
    return .{
        .allocator = self.allocator,
        .status_code = self.status_code,
        .content = try self.allocator.dupe(u8, self.content),
    };
}
