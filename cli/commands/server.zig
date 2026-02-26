const std = @import("std");

const args = @import("args");

const util = @import("../util.zig");

const ArrayList = std.ArrayList;

pub const watch_changes_pause_duration = 1 * 1000 * 1000 * 1000;

/// Command line options for the `server` command.
pub const Options = struct {
    reload: bool = true,
    debug: bool = true,
    bind: []const u8 = "127.0.0.1",
    port: u16 = 8080,

    pub const shorthands = .{
        .b = "bind",
        .p = "port",
    };

    pub const meta = .{
        .full_text =
        \\Launches a development server.
        \\
        \\Example:
        \\
        \\  jetzig server
        \\  jetzig server --reload=false --debug=false
        \\  jetzig server --bind 0.0.0.0 --port 3000
        ,
        .option_docs = .{
            .reload = "Enable or disable automatic reload on update (default: true)",
            .debug = "Enable or disable the development debug console (default: true)",
            .bind = "IP address/hostname to bind to (default: 127.0.0.1)",
            .port = "Port to listen on (default: 8080)",
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

    var argv: ArrayList([]const u8) = .empty;
    defer argv.deinit(allocator);

    try argv.appendSlice(allocator, &.{
        "zig",
        "build",
        util.environmentBuildOption(main_options.options.environment),
        "-Djetzig_runner=true",
    });

    if (options.debug) try argv.append(allocator, "-Ddebug_console=true");
    try argv.appendSlice(allocator, &.{
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

        var run_argv: ArrayList([]const u8) = .empty;
        defer run_argv.deinit(allocator);

        try run_argv.append(allocator, exe_path.?);

        if (!std.mem.eql(u8, options.bind, "127.0.0.1")) {
            try run_argv.appendSlice(allocator, &.{ "--bind", options.bind });
        }
        var port_buf: [5]u8 = undefined;
        if (options.port != 8080) {
            const port_str = try std.fmt.bufPrint(&port_buf, "{d}", .{options.port});
            try run_argv.appendSlice(allocator, &.{ "--port", port_str });
        }

        var process = std.process.Child.init(run_argv.items, allocator);
        process.stdin_behavior = .Inherit;
        process.stdout_behavior = .Inherit;
        process.stderr_behavior = .Inherit;
        process.cwd = realpath;

        var stdout_buf: ArrayList(u8) = .empty;
        defer stdout_buf.deinit(allocator);

        var stderr_buf: ArrayList(u8) = .empty;
        defer stderr_buf.deinit(allocator);

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
