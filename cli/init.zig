const std = @import("std");
const args = @import("args");
const init_data = @import("init_data").init_data;

fn base64Decode(allocator: std.mem.Allocator, input: []const u8) ![]const u8 {
    const decoder = std.base64.Base64Decoder.init(
        std.base64.url_safe_no_pad.alphabet_chars,
        std.base64.url_safe_no_pad.pad_char,
    );
    const size = try decoder.calcSizeForSlice(input);
    const ptr = try allocator.alloc(u8, size);
    try decoder.decode(ptr, input);
    return ptr;
}

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
    positionals: [][]const u8,
    other_options: struct { help: bool },
) !void {
    _ = options;
    var install_path: ?[]const u8 = null;

    for (positionals) |arg| {
        if (install_path != null) {
            std.debug.print("Unexpected positional argument: {s}\n", .{arg});
            return error.JetzigUnexpectedPositionalArgumentsError;
        }
        install_path = arg;
    }

    const github_url = try githubUrl(allocator);
    defer allocator.free(github_url);

    if (other_options.help) {
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

    const real_path = try install_dir.realpathAlloc(allocator, ".");
    defer allocator.free(real_path);

    const output = try std.fmt.allocPrint(allocator, "Creating new project in {s}\n\n", .{real_path});
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

    try runCommand(allocator, install_dir, &[_][]const u8{
        "zig",
        "fetch",
        "--save",
        github_url,
    });

    // TODO: Use arg or interactive prompt to do Git setup in net project, default to no.
    // const git_setup = false;
    // if (git_setup) try gitSetup(allocator, install_dir);

    std.debug.print(
        \\
        \\Setup complete! ✈️ 🦎
        \\
        \\Launch your new application:
        \\
        \\    $ cd {s}
        \\
        \\    $ zig build run
        \\
        \\And then browse to http://localhost:8080/
        \\
        \\
    , .{real_path});
}

fn runCommand(allocator: std.mem.Allocator, install_dir: std.fs.Dir, argv: []const []const u8) !void {
    const result = try std.process.Child.run(.{ .allocator = allocator, .argv = argv, .cwd_dir = install_dir });
    defer allocator.free(result.stdout);
    defer allocator.free(result.stderr);

    const command = try std.mem.join(allocator, " ", argv);
    defer allocator.free(command);

    std.debug.print("[exec] {s}", .{command});

    if (result.term.Exited != 0) {
        printFailure();
        std.debug.print(
            \\
            \\Error running command: {s}
            \\
            \\[stdout]:
            \\
            \\{s}
            \\
            \\[stderr]:
            \\
            \\{s}
            \\
        , .{ command, result.stdout, result.stderr });
        return error.JetzigRunCommandError;
    } else {
        printSuccess();
    }
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
            printFailure();
            return err;
        };
        defer allocator.free(initial);
        for (capture) |item| {
            content = try std.mem.replaceOwned(u8, allocator, initial, item.from, item.to);
        }
    } else {
        content = readSourceFile(allocator, src) catch |err| {
            printFailure();
            return err;
        };
    }
    defer allocator.free(content);

    writeSourceFile(install_dir, dest, content) catch |err| {
        printFailure();
        return err;
    };
    printSuccess();
}

// Read a file from Jetzig source code.
fn readSourceFile(allocator: std.mem.Allocator, path: []const u8) ![]const u8 {
    inline for (init_data) |file| {
        if (std.mem.eql(u8, path, file.path)) return try base64Decode(allocator, file.data);
    }
    return error.SourceFileNotFound;
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

// Generate a full GitHub URL for passing to `zig fetch`.
fn githubUrl(allocator: std.mem.Allocator) ![]const u8 {
    var client = std.http.Client{ .allocator = allocator };
    defer client.deinit();

    const url = "https://api.github.com/repos/jetzig-framework/jetzig/branches/main";
    const extra_headers = &[_]std.http.Header{.{ .name = "X-GitHub-Api-Version", .value = "2022-11-28" }};

    var response_storage = std.ArrayList(u8).init(allocator);
    defer response_storage.deinit();

    const fetch_result = try client.fetch(.{
        .location = .{ .url = url },
        .extra_headers = extra_headers,
        .response_storage = .{ .dynamic = &response_storage },
    });

    if (fetch_result.status != .ok) {
        std.debug.print("Error fetching from GitHub: {s}\n", .{url});
        return error.JetzigGitHubFetchError;
    }

    const parsed_response = try std.json.parseFromSlice(
        struct { commit: struct { sha: []const u8 } },
        allocator,
        response_storage.items,
        .{ .ignore_unknown_fields = true },
    );
    defer parsed_response.deinit();

    return try std.mem.concat(
        allocator,
        u8,
        &[_][]const u8{
            "https://github.com/jetzig-framework/jetzig/archive/",
            parsed_response.value.commit.sha,
            ".tar.gz",
        },
    );
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

            if (std.mem.eql(u8, capture, "")) {
                if (options.default) |default| return try allocator.dupe(u8, strip(default));
            } else return try allocator.dupe(u8, strip(capture));
        }
    }
}

// Strip leading and trailing whitespace from a u8 slice.
fn strip(input: []const u8) []const u8 {
    return std.mem.trim(u8, input, &std.ascii.whitespace);
}

// Initialize a new Git repository when setting up a new project (optional).
fn gitSetup(allocator: std.mem.Allocator, install_dir: *std.fs.Dir) !void {
    try runCommand(allocator, install_dir, &[_][]const u8{
        "git",
        "init",
        ".",
    });

    try runCommand(allocator, install_dir, &[_][]const u8{
        "git",
        "add",
        ".",
    });

    try runCommand(allocator, install_dir, &[_][]const u8{
        "git",
        "commit",
        "-m",
        "Initialize Jetzig project",
    });
}

/// Print a success confirmation.
fn printSuccess() void {
    std.debug.print(" ✅\n", .{});
}

/// Print a failure confirmation.
fn printFailure() void {
    std.debug.print(" ❌\n", .{});
}
