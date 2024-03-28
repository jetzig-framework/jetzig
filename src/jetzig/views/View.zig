const std = @import("std");

const Self = @This();

const jetzig = @import("../../jetzig.zig");

data: *jetzig.data.Data,
status_code: jetzig.http.status_codes.StatusCode = .ok,

pub fn deinit(self: Self) void {
    _ = self;
}
