const std = @import("std");

/// Run the job generator. Create a job in `src/app/jobs/`
pub fn run(allocator: std.mem.Allocator, cwd: std.fs.Dir, args: [][]const u8, help: bool) !void {
    if (help or args.len != 1) {
        std.debug.print(
            \\Generate a new Job. Jobs can be scheduled to run in the background.
            \\Use a Job when you need to return a request immediately and perform
            \\another task asynchronously.
            \\
            \\Example:
            \\
            \\  jetzig generate job iguana
            \\
        , .{});

        if (help) return;

        return error.JetzigCommandError;
    }

    const dir_path = try std.fs.path.join(allocator, &[_][]const u8{ "src", "app", "jobs" });
    defer allocator.free(dir_path);

    var dir = try cwd.makeOpenPath(dir_path, .{});
    defer dir.close();

    const filename = try std.mem.concat(allocator, u8, &[_][]const u8{ args[0], ".zig" });
    defer allocator.free(filename);

    const file = dir.createFile(filename, .{ .exclusive = true }) catch |err| {
        switch (err) {
            error.PathAlreadyExists => {
                std.debug.print("Partial already exists: {s}\n", .{filename});
                return error.JetzigCommandError;
            },
            else => return err,
        }
    };

    try file.writeAll(
        \\const std = @import("std");
        \\const jetzig = @import("jetzig");
        \\
        \\/// The `run` function for all jobs receives an arena allocator, a logger, and the params
        \\/// passed to the job when it was created.
        \\pub fn run(allocator: std.mem.Allocator, params: *jetzig.data.Value, logger: jetzig.Logger) !void {
        \\    // Job execution code
        \\}
        \\
    );

    file.close();

    const realpath = try dir.realpathAlloc(allocator, filename);
    defer allocator.free(realpath);
    std.debug.print("Generated job: {s}\n", .{realpath});
}
