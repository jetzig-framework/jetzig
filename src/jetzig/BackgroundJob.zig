const std = @import("std");
const jetzig = @import("../jetzig.zig");

allocator: std.mem.Allocator,
name: []const u8,
data: ?*jetzig.data.Data = null,
_params: ?*jetzig.data.Value = null,

const Self = @This();

/// Initializes a new BackgroundJob.
pub fn init(allocator: std.mem.Allocator, name: []const u8) Self {
    return .{ .allocator = allocator, .name = name };
}

/// Deinitializes the BackgroundJob and frees memory.
pub fn deinit(self: *Self) void {
    if (self.data) |data| {
        data.deinit();
        self.allocator.destroy(data);
    }
}

/// Adds a parameter to the BackgroundJob. Parameters are stored
pub fn put(self: *Self, key: []const u8, value: *jetzig.data.Value) !void {
    var job_params = try self.params();
    try job_params.put(key, value);
}

pub fn background(self: *Self) !void {
    _ = self;
}

fn params(self: *Self) !*jetzig.data.Value {
    if (self.data == null) {
        self.data = try self.allocator.create(jetzig.data.Data);
        self.data.?.* = jetzig.data.Data.init(self.allocator);
        self._params = try self.data.?.object();
    }
    return self._params.?;
}

test "create job and set params" {
    var job = Self.init(std.testing.allocator, "example");
    defer job.deinit();

    var data = jetzig.data.Data.init(std.testing.allocator);
    defer data.deinit();

    try job.put("foo", data.string("bar"));
    try std.testing.expectEqualStrings("bar", job.data.?.value.?.get("foo").?.string.value);
}

test "create job and add to queue" {
    // TODO
}
