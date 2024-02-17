const std = @import("std");
const Self = @This();
const jetzig = @import("../../jetzig.zig");

response_data: *jetzig.data.Data,
allocator: std.mem.Allocator,

pub fn init(allocator: std.mem.Allocator) !Self {
    return .{
        .allocator = allocator,
        .response_data = try allocator.create(jetzig.data.Data),
    };
}

pub fn deinit(self: *Self) void {
    _ = self;
}

pub fn render(self: *Self, status_code: jetzig.http.status_codes.StatusCode) jetzig.views.View {
    return .{ .data = self.response_data, .status_code = status_code };
}

pub fn resourceId(self: *Self) []const u8 {
    _ = self;
    return "TODO";
}
