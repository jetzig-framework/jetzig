const std = @import("std");
const jetzig = @import("../../jetzig.zig");

/// Job name and run function, used when generating an array of job definitions at build time.
pub const JobDefinition = struct {
    name: []const u8,
    runFn: *const fn (std.mem.Allocator, *jetzig.data.Value, jetzig.loggers.Logger) anyerror!void,
};

allocator: std.mem.Allocator,
jet_kv: *jetzig.jetkv.JetKV,
logger: jetzig.loggers.Logger,
name: []const u8,
definition: ?JobDefinition,
data: ?*jetzig.data.Data = null,
_params: ?*jetzig.data.Value = null,

const Job = @This();

/// Initialize a new Job
pub fn init(
    allocator: std.mem.Allocator,
    jet_kv: *jetzig.jetkv.JetKV,
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

    return .{
        .allocator = allocator,
        .jet_kv = jet_kv,
        .logger = logger,
        .name = name,
        .definition = definition,
    };
}

/// Deinitialize the Job and frees memory
pub fn deinit(self: *Job) void {
    if (self.data) |data| {
        data.deinit();
        self.allocator.destroy(data);
    }
}

/// Add a parameter to the Job
pub fn put(self: *Job, key: []const u8, value: *jetzig.data.Value) !void {
    var job_params = try self.params();
    try job_params.put(key, value);
}

/// Add a Job to the queue
pub fn schedule(self: *Job) !void {
    _ = try self.params();
    const json = try self.data.?.toJson();
    try self.jet_kv.prepend("__jetzig_jobs", json);
    try self.logger.INFO("Scheduled job: {s}", .{self.name});
}

fn params(self: *Job) !*jetzig.data.Value {
    if (self.data == null) {
        self.data = try self.allocator.create(jetzig.data.Data);
        self.data.?.* = jetzig.data.Data.init(self.allocator);
        self._params = try self.data.?.object();
        try self._params.?.put("__jetzig_job_name", self.data.?.string(self.name));
    }
    return self._params.?;
}

// TODO: Tests :)
