const std = @import("std");

const jetzig = @import("../../jetzig.zig");

const ArrayList = std.ArrayList;

const Pool = @This();

allocator: std.mem.Allocator,
job_queue: *jetzig.kv.Store.JobQueueStore,
job_env: jetzig.jobs.JobEnv,
pool: std.Thread.Pool = undefined,
workers: ArrayList(*jetzig.jobs.Worker),

/// Initialize a new worker thread pool.
pub fn init(
    allocator: std.mem.Allocator,
    job_queue: *jetzig.kv.Store.JobQueueStore,
    job_env: jetzig.jobs.JobEnv,
) Pool {
    return .{
        .allocator = allocator,
        .job_queue = job_queue,
        .job_env = job_env,
        .workers = .empty,
    };
}

/// Free pool resources and destroy workers.
pub fn deinit(self: *Pool) void {
    self.pool.deinit();
    for (self.workers.items) |worker| self.allocator.destroy(worker);
    self.workers.deinit(self.allocator);
}

/// Spawn a given number of threads and start processing jobs, sleep for a given interval (ms)
/// when no jobs are in the queue. Each worker operates its own work loop.
pub fn work(self: *Pool, threads: usize, interval: usize) !void {
    try self.pool.init(.{ .allocator = self.allocator });

    for (0..threads) |index| {
        const worker = try self.allocator.create(jetzig.jobs.Worker);
        worker.* = jetzig.jobs.Worker.init(
            self.allocator,
            self.job_env,
            index,
            self.job_queue,
            interval,
        );
        try self.workers.append(self.allocator, worker);
        try self.pool.spawn(jetzig.jobs.Worker.work, .{worker});
    }
}
