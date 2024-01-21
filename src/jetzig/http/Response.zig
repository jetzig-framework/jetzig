const std = @import("std");

const http = @import("../http.zig");

const Self = @This();

allocator: std.mem.Allocator,
content: []const u8,
status_code: http.status_codes.StatusCode,
content_type: []const u8,

pub fn init(
    allocator: std.mem.Allocator,
    content: []const u8,
    status_code: http.status_codes.StatusCode,
    content_type: []const u8,
) Self {
    return .{
        .status_code = status_code,
        .content = content,
        .content_type = content_type,
        .allocator = allocator,
    };
}

pub fn deinit(self: *const Self) void {
    _ = self;
    // self.allocator.free(self.content);
    // self.allocator.free(self.content_type);
}

pub fn dupe(self: *const Self) !Self {
    return .{
        .allocator = self.allocator,
        .status_code = self.status_code,
        .content_type = try self.allocator.dupe(u8, self.content_type),
        .content = try self.allocator.dupe(u8, self.content),
    };
}
