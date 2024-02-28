const std = @import("std");
const jetzig = @import("jetzig");

/// This example demonstrates usage of Jetzig's background jobs.
pub fn index(request: *jetzig.Request, data: *jetzig.Data) !jetzig.View {

    // Create a new job using `src/app/jobs/example_job.zig`.
    var job = try request.job("example");

    // Add a param `foo` to the job.
    try job.put("foo", data.string("bar"));
    try job.put("id", data.integer(std.crypto.random.int(u32)));

    // Schedule the job for background processing. The job is added to the queue. When the job is
    // processed a new instance of `example_job` is created and its `run` function is invoked.
    // All params are added above are available to the job by calling `job.params()` inside the
    // `run` function.
    try job.schedule();

    return request.render(.ok);
}
