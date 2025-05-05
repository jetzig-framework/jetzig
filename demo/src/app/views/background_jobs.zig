const std = @import("std");
const jetzig = @import("jetzig");

/// This example demonstrates usage of Jetzig's background jobs.
pub fn index(request: *jetzig.Request, data: *jetzig.Data) !jetzig.View {
    // Prepare a job using `src/app/jobs/example.zig`.
    var job = try request.job("example");

    // Add a param `foo` to the job.
    try job.params.put("foo", data.string("bar"));
    try job.params.put("id", data.integer(std.crypto.random.int(u32)));

    // Schedule the job for background processing.
    try job.schedule();

    return request.render(.ok);
}

test "index" {
    var app = try jetzig.testing.app(std.testing.allocator, @import("routes"));
    defer app.deinit();

    const response = try app.request(.GET, "/background_jobs", .{});
    try response.expectJob("example", .{ .foo = "bar" });
}
