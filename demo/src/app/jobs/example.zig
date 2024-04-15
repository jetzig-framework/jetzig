const std = @import("std");
const jetzig = @import("jetzig");

/// The `run` function for all jobs receives an arena allocator, a logger, and the params
/// passed to the job when it was created.
pub fn run(allocator: std.mem.Allocator, params: *jetzig.data.Value, logger: jetzig.Logger) !void {
    _ = allocator;
    try logger.INFO("Job received params: {s}", .{try params.toJson()});
}
