const std = @import("std");

const args = @import("args");

const util = @import("../util.zig");

pub const watch_changes_pause_duration = 1 * 1000 * 1000 * 1000;

/// Command line options for the `server` command.
pub const Options = struct {
    reload: bool = true,
    debug: bool = true,

    pub const meta = .{
        .full_text =
        \\Launches a development server.
        \\
        \\Example:
        \\
        \\  jetzig server
        \\  jetzig server --reload=false --debug=false
        ,
        .option_docs = .{
            .reload = "Enable or disable automatic reload on update (default: true)",
            .debug = "Enable or disable the development debug console (default: true)",
        },
    };
};

/// Run the `jetzig server` command.
pub fn run(
    allocator: std.mem.Allocator,
    options: Options,
    writer: anytype,
    T: type,
    main_options: T,
) !void {
    if (main_options.options.help) {
        try args.printHelp(Options, "jetzig server", writer);
        return;
    }

    if (main_options.positionals.len > 0) {
        std.debug.print("The `server` command does not accept positional arguments.", .{});
        return error.JetzigCommandError;
    }

    var cwd = try util.detectJetzigProjectDir();
    defer cwd.close();

    const realpath = try std.fs.realpathAlloc(allocator, ".");
    defer allocator.free(realpath);

    var mtime = try totalMtime(allocator, cwd, "src");

    std.debug.print(
        "Launching development server. [reload:{s}]\n",
        .{
            if (options.reload) "enabled" else "disabled",
        },
    );

    var argv = std.ArrayList([]const u8).init(allocator);
    defer argv.deinit();

    try argv.appendSlice(&.{
        "zig",
        "build",
        util.environmentBuildOption(main_options.options.environment),
        "-Djetzig_runner=true",
    });

    if (options.debug) try argv.append("-Ddebug_console=true");
    try argv.appendSlice(&.{
        "install",
        "--color",
        "on",
    });

    while (true) {
        util.runCommandInDir(allocator, argv.items, .{ .path = realpath }, .{}) catch {
            std.debug.print("Build failed, waiting for file change...\n", .{});
            try awaitFileChange(allocator, cwd, &mtime);
            std.debug.print("Changes detected, restarting server...\n", .{});
            continue;
        };

        const exe_path = try util.locateExecutable(allocator, cwd, .{});
        if (exe_path == null) {
            std.debug.print("Unable to locate compiled executable. Exiting.\n", .{});
            std.process.exit(1);
        }

        defer allocator.free(exe_path.?);

        var process = std.process.Child.init(&.{exe_path.?}, allocator);
        process.stdin_behavior = .Inherit;
        process.stdout_behavior = .Inherit;
        process.stderr_behavior = .Inherit;
        process.cwd = realpath;

        var stdout_buf = std.ArrayList(u8).init(allocator);
        defer stdout_buf.deinit();

        var stderr_buf = std.ArrayList(u8).init(allocator);
        defer stderr_buf.deinit();

        try process.spawn();

        if (!options.reload) {
            const term = try process.wait();
            std.process.exit(term.Exited);
        }

        // HACK: This currenly doesn't restart the server when it exits, maybe that
        // could be implemented in the future.

        try awaitFileChange(allocator, cwd, &mtime);
        std.debug.print("Changes detected, restarting server...\n", .{});
        _ = try process.kill();
    }
}

fn awaitFileChange(allocator: std.mem.Allocator, cwd: std.fs.Dir, mtime: *i128) !void {
    while (true) {
        std.time.sleep(watch_changes_pause_duration);
        const new_mtime = try totalMtime(allocator, cwd, "src");
        if (new_mtime > mtime.*) {
            mtime.* = new_mtime;
            return;
        }
    }
}

fn totalMtime(allocator: std.mem.Allocator, cwd: std.fs.Dir, sub_path: []const u8) !i128 {
    var dir = try cwd.openDir(sub_path, .{ .iterate = true });
    defer dir.close();

    var walker = try dir.walk(allocator);
    defer walker.deinit();

    var sum: i128 = 0;

    while (try walker.next()) |entry| {
        if (entry.kind != .file) continue;
        const extension = std.fs.path.extension(entry.path);

        if (std.mem.eql(u8, extension, ".zig") or std.mem.eql(u8, extension, ".zmpl")) {
            const stat = try dir.statFile(entry.path);
            sum += stat.mtime;
        }
    }

    return sum;
}
