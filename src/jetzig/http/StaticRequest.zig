const std = @import("std");
const Self = @This();
const jetzig = @import("../../jetzig.zig");

response_data: *jetzig.data.Data,
allocator: std.mem.Allocator,
json: []const u8,

pub fn init(allocator: std.mem.Allocator, json: []const u8) !Self {
    return .{
        .allocator = allocator,
        .response_data = try allocator.create(jetzig.data.Data),
        .json = json,
    };
}

pub fn deinit(self: *Self) void {
    _ = self;
}

pub fn render(self: *Self, status_code: jetzig.http.status_codes.StatusCode) jetzig.views.View {
    return .{ .data = self.response_data, .status_code = status_code };
}

pub fn resourceId(self: *Self) ![]const u8 {
    var data = try self.allocator.create(jetzig.data.Data);
    data.* = jetzig.data.Data.init(self.allocator);
    defer self.allocator.destroy(data);
    defer data.deinit();

    try data.fromJson(self.json);
    // Routes generator rejects missing `.id` option so this should always be present.
    // Note that static requests are never rendered at runtime so we can be unsafe here and risk
    // failing a build (which would not be coherent if we allowed it to complete).
    return data.value.?.get("id").?.string.value;
}

/// Returns the static params defined by `pub const static_params` in the relevant view.
pub fn params(self: *Self) !*jetzig.data.Value {
    var data = try self.allocator.create(jetzig.data.Data);
    data.* = jetzig.data.Data.init(self.allocator);
    try data.fromJson(self.json);
    return data.value.?.get("params") orelse data.object();
}
