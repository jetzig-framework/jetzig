const std = @import("std");
const StaticRequest = @This();
const jetzig = @import("../../jetzig.zig");

response_data: *jetzig.data.Data,
allocator: std.mem.Allocator,
json: []const u8,

pub fn init(allocator: std.mem.Allocator, json: []const u8) !StaticRequest {
    return .{
        .allocator = allocator,
        .response_data = try allocator.create(jetzig.data.Data),
        .json = json,
    };
}

pub fn deinit(self: *StaticRequest) void {
    _ = self;
}

pub fn render(self: *StaticRequest, status_code: jetzig.http.status_codes.StatusCode) jetzig.views.View {
    return .{ .data = self.response_data, .status_code = status_code };
}

pub fn data(self: *StaticRequest, comptime root: @TypeOf(.enum_literal)) !*jetzig.Data.Value {
    return try self.response_data.root(root);
}

pub fn resourceId(self: *StaticRequest) ![]const u8 {
    var params_data = try self.allocator.create(jetzig.data.Data);
    params_data.* = jetzig.data.Data.init(self.allocator);
    defer self.allocator.destroy(params_data);
    defer params_data.deinit();

    try params_data.fromJson(self.json);
    // Routes generator rejects missing `.id` option so this should always be present.
    // Note that static requests are never rendered at runtime so we can be unsafe here and risk
    // failing a build (which would not be coherent if we allowed it to complete).
    return try self.allocator.dupe(u8, params_data.value.?.get("id").?.string.value);
}

/// Returns the static params defined by `pub const static_params` in the relevant view.
pub fn params(self: *StaticRequest) !*jetzig.data.Value {
    var params_data = try self.allocator.create(jetzig.data.Data);
    params_data.* = jetzig.data.Data.init(self.allocator);
    try params_data.fromJson(self.json);
    return params_data.value.?.get("params") orelse params_data.object();
}
