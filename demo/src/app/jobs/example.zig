const std = @import("std");
const jetzig = @import("jetzig");

/// The `run` function for all jobs receives an arena allocator, the params passed to the job
/// when it was created, and an environment which provides a logger, the current server
/// environment `{ development, production }`.
pub fn run(allocator: std.mem.Allocator, params: *jetzig.data.Value, env: jetzig.jobs.JobEnv) !void {
    try env.logger.INFO("Job received params: {s}", .{try params.toJson()});

    const mail = jetzig.mail.Mail.init(
        allocator,
        env,
        .{
            .subject = "Hello!!!",
            .from = .{ .email = "bob@jetzig.dev" },
            .to = &.{.{ .email = "bob@jetzig.dev" }},
            .html = "<div>Hello!</div>",
            .text = "Hello!",
        },
    );

    try mail.deliver();
}
