const std = @import("std");

const jetzig = @import("../../jetzig.zig");
const Worker = @This();

allocator: std.mem.Allocator,
job_env: jetzig.jobs.JobEnv,
id: usize,
job_queue: *jetzig.kv.Store,
interval: usize,

pub fn init(
    allocator: std.mem.Allocator,
    job_env: jetzig.jobs.JobEnv,
    id: usize,
    job_queue: *jetzig.kv.Store,
    interval: usize,
) Worker {
    return .{
        .allocator = allocator,
        .job_env = job_env,
        .id = id,
        .job_queue = job_queue,
        .interval = interval * 1000 * 1000, // millisecond => nanosecond
    };
}

/// Begin working through jobs in the queue.
pub fn work(self: *const Worker) void {
    self.log(.INFO, "[worker-{}] Job worker started.", .{self.id});

    while (true) {
        var data = jetzig.data.Data.init(self.allocator);
        defer data.deinit();
        const maybe_value = self.job_queue.popFirst(&data, "__jetzig_jobs") catch |err| blk: {
            self.log(.ERROR, "Error fetching job from queue: {s}", .{@errorName(err)});
            break :blk null; // FIXME: Probably close thread here ?
        };

        if (maybe_value) |value| {
            if (self.matchJob(value)) |job_definition| {
                self.processJob(job_definition, value);
            }
        } else {
            std.time.sleep(self.interval);
        }
    }

    self.log(.INFO, "[worker-{}] Job worker exited.", .{self.id});
}

// Do a minimal parse of JSON job data to identify job name, then match on known job definitions.
fn matchJob(self: Worker, value: *const jetzig.data.Value) ?jetzig.jobs.JobDefinition {
    const job_name = value.getT(.string, "__jetzig_job_name") orelse {
        self.log(
            .ERROR,
            "[worker-{}] Missing expected job name field `__jetzig_job_name`",
            .{self.id},
        );
        return null;
    };

    // TODO: Hashmap
    for (self.job_env.jobs) |job_definition| {
        if (std.mem.eql(u8, job_definition.name, job_name)) {
            return job_definition;
        }
    } else {
        self.log(.WARN, "[worker-{}] Tried to process unknown job: {s}", .{ self.id, job_name });
        return null;
    }
}

// Fully parse JSON job data and invoke the defined job's run function, passing the parsed params
// as a `*jetzig.data.Value`.
fn processJob(self: Worker, job_definition: jetzig.JobDefinition, params: *jetzig.data.Value) void {
    var arena = std.heap.ArenaAllocator.init(self.allocator);
    defer arena.deinit();

    job_definition.runFn(arena.allocator(), params, self.job_env) catch |err| {
        self.log(
            .ERROR,
            "[worker-{}] Encountered error processing job `{s}`: {s}",
            .{ self.id, job_definition.name, @errorName(err) },
        );
        return;
    };
    self.log(.INFO, "[worker-{}] Job completed: {s}", .{ self.id, job_definition.name });
}

// Log with error handling and fallback. Prefix with worker ID.
fn log(
    self: Worker,
    comptime level: jetzig.loggers.LogLevel,
    comptime message: []const u8,
    args: anytype,
) void {
    self.job_env.logger.log(level, message, args) catch |err| {
        // XXX: In (daemonized) deployment stderr will not be available, find a better solution.
        // Note that this only occurs if logging itself fails.
        std.debug.print("[worker-{}] Logger encountered error: {s}\n", .{ self.id, @errorName(err) });
    };
}
