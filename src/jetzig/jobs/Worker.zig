const std = @import("std");

const jetzig = @import("../../jetzig.zig");
const Worker = @This();

allocator: std.mem.Allocator,
logger: jetzig.loggers.Logger,
id: usize,
jet_kv: *jetzig.jetkv.JetKV,
job_definitions: []const jetzig.jobs.JobDefinition,
interval: usize,

pub fn init(
    allocator: std.mem.Allocator,
    logger: jetzig.loggers.Logger,
    id: usize,
    jet_kv: *jetzig.jetkv.JetKV,
    job_definitions: []const jetzig.jobs.JobDefinition,
    interval: usize,
) Worker {
    return .{
        .allocator = allocator,
        .logger = logger,
        .id = id,
        .jet_kv = jet_kv,
        .job_definitions = job_definitions,
        .interval = interval * 1000 * 1000, // millisecond => nanosecond
    };
}

/// Begin working through jobs in the queue.
pub fn work(self: *const Worker) void {
    self.log(.INFO, "[worker-{}] Job worker started.", .{self.id});

    while (true) {
        if (self.jet_kv.pop("__jetzig_jobs")) |json| {
            defer self.allocator.free(json);
            if (self.matchJob(json)) |job_definition| {
                self.processJob(job_definition, json);
            }
        } else {
            std.time.sleep(self.interval);
        }
    }

    self.log(.INFO, "[worker-{}] Job worker exited.", .{self.id});
}

// Do a minimal parse of JSON job data to identify job name, then match on known job definitions.
fn matchJob(self: Worker, json: []const u8) ?jetzig.jobs.JobDefinition {
    const parsed_json = std.json.parseFromSlice(
        struct { __jetzig_job_name: []const u8 },
        self.allocator,
        json,
        .{ .ignore_unknown_fields = true },
    ) catch |err| {
        self.log(
            .ERROR,
            "[worker-{}] Error parsing JSON from job queue: {s}",
            .{ self.id, @errorName(err) },
        );
        return null;
    };

    const job_name = parsed_json.value.__jetzig_job_name;

    // TODO: Hashmap
    for (self.job_definitions) |job_definition| {
        if (std.mem.eql(u8, job_definition.name, job_name)) {
            parsed_json.deinit();
            return job_definition;
        }
    } else {
        self.log(.WARN, "[worker-{}] Tried to process unknown job: {s}", .{ self.id, job_name });
        return null;
    }
}

// Fully parse JSON job data and invoke the defined job's run function, passing the parsed params
// as a `*jetzig.data.Value`.
fn processJob(self: Worker, job_definition: jetzig.JobDefinition, json: []const u8) void {
    var data = jetzig.data.Data.init(self.allocator);
    defer data.deinit();

    data.fromJson(json) catch |err| {
        self.log(
            .INFO,
            "[worker-{}] Error parsing JSON for job `{s}`: {s}",
            .{ self.id, job_definition.name, @errorName(err) },
        );
    };

    var arena = std.heap.ArenaAllocator.init(self.allocator);
    defer arena.deinit();

    if (data.value) |params| {
        job_definition.runFn(arena.allocator(), params, self.logger) catch |err| {
            self.log(
                .ERROR,
                "[worker-{}] Encountered error processing job `{s}`: {s}",
                .{ self.id, job_definition.name, @errorName(err) },
            );
            return;
        };
        self.log(.INFO, "[worker-{}] Job completed: {s}", .{ self.id, job_definition.name });
    } else {
        self.log(.ERROR, "Error in job params definition for job: {s}", .{job_definition.name});
    }
}

// Log with error handling and fallback. Prefix with worker ID.
fn log(
    self: Worker,
    comptime level: jetzig.loggers.LogLevel,
    comptime message: []const u8,
    args: anytype,
) void {
    self.logger.log(level, message, args) catch |err| {
        // XXX: In (daemonized) deployment stderr will not be available, find a better solution.
        // Note that this only occurs if logging itself fails.
        std.debug.print("[worker-{}] Logger encountered error: {s}\n", .{ self.id, @errorName(err) });
    };
}
