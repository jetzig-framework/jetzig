const std = @import("std");
const jetzig = @import("../../jetzig.zig");

/// Job name and run function, used when generating an array of job definitions at build time.
pub const JobDefinition = struct {
    name: []const u8,
    runFn: *const fn (std.mem.Allocator, *jetzig.data.Value, JobEnv) anyerror!void,
};

/// Environment passed to all jobs.
pub const JobEnv = struct {
    /// The Jetzig server logger
    logger: jetzig.loggers.Logger,
    /// The current server environment, `enum { development, production }`
    environment: jetzig.Environment.EnvironmentName,
    /// Environment configured at server launch
    vars: jetzig.Environment.Vars,
    /// All routes detected by Jetzig on startup
    routes: []*const jetzig.Route,
    /// All mailers detected by Jetzig on startup
    mailers: []const jetzig.MailerDefinition,
    /// All jobs detected by Jetzig on startup
    jobs: []const jetzig.JobDefinition,
    /// Global key-value store
    store: *jetzig.kv.Store,
    /// Global cache
    cache: *jetzig.kv.Store,
    /// Database repo
    repo: *jetzig.database.Repo,
    /// Global mutex - use with caution if it is necessary to guarantee thread safety/consistency
    /// between concurrent job workers
    mutex: *std.Thread.Mutex,
};

allocator: std.mem.Allocator,
store: *jetzig.kv.Store,
job_queue: *jetzig.kv.Store,
cache: *jetzig.kv.Store,
logger: jetzig.loggers.Logger,
name: []const u8,
definition: ?JobDefinition,
data: *jetzig.data.Data,
params: *jetzig.data.Value,

const Job = @This();

/// Initialize a new Job
pub fn init(
    allocator: std.mem.Allocator,
    store: *jetzig.kv.Store,
    job_queue: *jetzig.kv.Store,
    cache: *jetzig.kv.Store,
    logger: jetzig.loggers.Logger,
    jobs: []const JobDefinition,
    name: []const u8,
) Job {
    var definition: ?JobDefinition = null;

    for (jobs) |job_definition| {
        if (std.mem.eql(u8, job_definition.name, name)) {
            definition = job_definition;
            break;
        }
    }

    const data = allocator.create(jetzig.data.Data) catch @panic("OOM");
    data.* = jetzig.data.Data.init(allocator);

    return .{
        .allocator = allocator,
        .store = store,
        .job_queue = job_queue,
        .cache = cache,
        .logger = logger,
        .name = name,
        .definition = definition,
        .data = data,
        .params = data.object() catch @panic("OOM"),
    };
}

/// Deinitialize the Job and frees memory
pub fn deinit(self: *Job) void {
    self.data.deinit();
    self.allocator.destroy(self.data);
}

/// Add a Job to the queue
pub fn schedule(self: *Job) !void {
    try self.params.put("__jetzig_job_name", self.data.string(self.name));
    try self.job_queue.append("__jetzig_jobs", self.data.value.?);
    try self.logger.INFO("Scheduled job: {s}", .{self.name});
}
