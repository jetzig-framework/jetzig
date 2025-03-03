const std = @import("std");
const args = @import("args");

const util = @import("../util.zig");
const cli = @import("../cli.zig");
const init_data = @import("init_data").init_data;

/// Command line options for the `init` command.
pub const Options = struct {
    path: ?[]const u8 = null,

    pub const shorthands = .{
        .p = "path",
    };

    pub const meta = .{
        .usage_summary = "[--path PATH]",
        .full_text =
        \\Initializes a new Jetzig project in the current directory or attempts to
        \\create a new directory specified by PATH
        \\
        \\Creates build.zig, build.zig.zon, src/main.zig, and an example view with a template.
        \\
        \\Run `zig build run` to launch a development server when complete.
        ,
        .option_docs = .{
            .path = "Set the output path relative to the current directory (default: current directory)",
        },
    };
};

/// Run the `jetzig init` command.
pub fn run(
    allocator: std.mem.Allocator,
    options: Options,
    writer: anytype,
    T: type,
    main_options: T,
) !void {
    _ = options;
    var install_path: ?[]const u8 = null;

    for (main_options.positionals) |arg| {
        if (install_path != null) {
            std.debug.print("Unexpected positional argument: {s}\n", .{arg});
            return error.JetzigCommandError;
        }
        install_path = arg;
    }

    const github_url = try util.githubUrl(allocator);
    defer allocator.free(github_url);

    if (main_options.options.help) {
        try args.printHelp(Options, "jetzig init", writer);
        return;
    }

    var install_dir: std.fs.Dir = undefined;
    defer install_dir.close();

    var project_name: []const u8 = undefined;
    defer allocator.free(project_name);

    if (install_path) |path| {
        install_dir = try std.fs.cwd().makeOpenPath(path, .{});
        project_name = try allocator.dupe(u8, std.fs.path.basename(path));
    } else {
        const cwd_realpath = try std.fs.cwd().realpathAlloc(allocator, ".");
        defer allocator.free(cwd_realpath);

        const default_project_name = std.fs.path.basename(cwd_realpath);
        project_name = try promptInput(allocator, "Project name", .{ .default = default_project_name });
        const sub_path = if (std.mem.eql(u8, project_name, default_project_name)) "" else project_name;

        const default_install_path = try std.fs.path.join(
            allocator,
            &[_][]const u8{ cwd_realpath, sub_path },
        );
        defer allocator.free(default_install_path);

        const input_install_path = try promptInput(
            allocator,
            "Install path",
            .{ .default = default_install_path },
        );
        defer allocator.free(input_install_path);
        install_dir = try std.fs.cwd().makeOpenPath(input_install_path, .{});
    }

    const realpath = try install_dir.realpathAlloc(allocator, ".");
    defer allocator.free(realpath);

    const output = try std.fmt.allocPrint(allocator, "Creating new project in {s}\n\n", .{realpath});
    defer allocator.free(output);
    try writer.writeAll(output);

    try copySourceFile(
        allocator,
        install_dir,
        "demo/build.zig",
        "build.zig",
        &[_]Replace{.{ .from = "jetzig-demo", .to = project_name }},
    );

    try copySourceFile(
        allocator,
        install_dir,
        "demo/config/database.zig",
        "config/database.zig",
        null,
    );

    try copySourceFile(
        allocator,
        install_dir,
        "demo/src/main.zig",
        "src/main.zig",
        null,
    );

    try copySourceFile(
        allocator,
        install_dir,
        "demo/src/app/middleware/DemoMiddleware.zig",
        "src/app/middleware/DemoMiddleware.zig",
        null,
    );

    try copySourceFile(
        allocator,
        install_dir,
        "demo/src/app/views/init.zig",
        "src/app/views/root.zig",
        null,
    );

    try copySourceFile(
        allocator,
        install_dir,
        "demo/src/app/views/init/index.zmpl",
        "src/app/views/root/index.zmpl",
        &[_]Replace{
            .{ .from = "init/", .to = "root/" },
        },
    );

    try copySourceFile(
        allocator,
        install_dir,
        "demo/src/app/views/init/_content.zmpl",
        "src/app/views/root/_content.zmpl",
        null,
    );

    try copySourceFile(
        allocator,
        install_dir,
        "demo/public/jetzig.png",
        "public/jetzig.png",
        null,
    );

    try copySourceFile(
        allocator,
        install_dir,
        "demo/public/zmpl.png",
        "public/zmpl.png",
        null,
    );

    try copySourceFile(
        allocator,
        install_dir,
        "demo/public/favicon.ico",
        "public/favicon.ico",
        null,
    );

    try copySourceFile(
        allocator,
        install_dir,
        "demo/public/styles.css",
        "public/styles.css",
        null,
    );

    try copySourceFile(
        allocator,
        install_dir,
        ".gitignore",
        ".gitignore",
        null,
    );

    try util.runCommandInDir(
        allocator,
        &[_][]const u8{
            "zig",
            "fetch",
            "--save",
            github_url,
        },
        .{ .dir = install_dir },
        .{},
    );

    // TODO: Use arg or interactive prompt to do Git setup in net project, default to no.
    // const git_setup = false;
    // if (git_setup) try gitSetup(allocator, install_dir);

    try util.unicodePrint(
        \\
        \\Setup complete! ✈️ 🦎
        \\
        \\Launch your new application:
        \\
        \\    $ cd {s}
        \\
        \\    $ zig build run or jetzig server
        \\
        \\And then browse to http://localhost:8080/
        \\
        \\
    , .{realpath});
}

const Replace = struct {
    from: []const u8,
    to: []const u8,
};

fn copySourceFile(
    allocator: std.mem.Allocator,
    install_dir: std.fs.Dir,
    src: []const u8,
    dest: []const u8,
    replace: ?[]const Replace,
) !void {
    std.debug.print("[create] {s}", .{dest});

    var content: []const u8 = undefined;
    if (replace) |capture| {
        const initial = readSourceFile(allocator, src) catch |err| {
            util.printFailure();
            return err;
        };
        defer allocator.free(initial);
        for (capture) |item| {
            content = try std.mem.replaceOwned(u8, allocator, initial, item.from, item.to);
        }
    } else {
        content = readSourceFile(allocator, src) catch |err| {
            util.printFailure();
            return err;
        };
    }
    defer allocator.free(content);

    writeSourceFile(install_dir, dest, content) catch |err| {
        util.printFailure();
        return err;
    };
    util.printSuccess(null);
}

// Read a file from Jetzig source code.
fn readSourceFile(allocator: std.mem.Allocator, path: []const u8) ![]const u8 {
    inline for (init_data) |file| {
        if (std.mem.eql(u8, path, file.path)) return try util.base64Decode(allocator, file.data);
    }
    return error.JetzigCommandError;
}

// Write a file to the new project's directory.
fn writeSourceFile(install_dir: std.fs.Dir, path: []const u8, content: []const u8) !void {
    // TODO: Detect presence and ask for confirmation if necessary.
    if (std.fs.path.dirname(path)) |dirname| {
        var dir = try install_dir.makeOpenPath(dirname, .{});
        defer dir.close();

        const file = try dir.createFile(std.fs.path.basename(path), .{ .truncate = true });
        defer file.close();

        try file.writeAll(content);
    } else {
        const file = try install_dir.createFile(path, .{ .truncate = true });
        defer file.close();

        try file.writeAll(content);
    }
}

// Prompt a user for input and return the result. Accepts an optional default value.
fn promptInput(
    allocator: std.mem.Allocator,
    prompt: []const u8,
    options: struct { default: ?[]const u8 },
) ![]const u8 {
    const stdin = std.io.getStdIn();
    const reader = stdin.reader();

    const max_read_bytes = 1024;

    while (true) {
        if (options.default) |default| {
            std.debug.print(
                \\{s} [default: "{s}"]: 
            , .{ prompt, default });
        } else {
            std.debug.print(
                \\{s}: 
            , .{prompt});
        }
        const input = try reader.readUntilDelimiterOrEofAlloc(allocator, '\n', max_read_bytes);
        if (input) |capture| {
            defer allocator.free(capture);
            const stripped_input = util.strip(capture);

            if (std.mem.eql(u8, stripped_input, "")) {
                if (options.default) |default| return try allocator.dupe(u8, util.strip(default));
            } else return try allocator.dupe(u8, stripped_input);
        }
    }
}

// Initialize a new Git repository when setting up a new project (optional).
fn gitSetup(allocator: std.mem.Allocator, install_dir: *std.fs.Dir) !void {
    try util.runCommandInDir(
        allocator,
        &[_][]const u8{
            "git",
            "init",
            ".",
        },
        .{ .path = install_dir },
        .{},
    );

    try util.runCommandInDir(
        allocator,
        &[_][]const u8{
            "git",
            "add",
            ".",
        },
        .{ .path = install_dir },
        .{},
    );

    try util.runCommandInDir(
        allocator,
        &[_][]const u8{
            "git",
            "commit",
            "-m",
            "Initialize Jetzig project",
        },
        .{ .path = install_dir },
        .{},
    );
}
