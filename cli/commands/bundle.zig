const std = @import("std");
const builtin = @import("builtin");

const args = @import("args");

const util = @import("../util.zig");

/// Command line options for the `bundle` command.
pub const Options = struct {
    optimize: enum { Debug, ReleaseFast, ReleaseSmall } = .ReleaseFast,
    arch: enum { x86, x86_64, aarch64, default } = .default,
    os: enum { linux, macos, windows, default } = .default,

    pub const meta = .{
        .full_text =
        \\Creates a deployment bundle.
        \\
        \\On Windows, `tar.exe` is used to generate a `.zip` file.
        \\
        \\On other operating systems, `tar` is used to generate a `.tar.gz` file.
        \\
        \\The deployment bundle contains a compiled executable with the `public/` and `static/`
        \\directories included. This bundle can be copied to a deployment server, unpacked, and
        \\launched in place.
        ,
        .option_docs = .{
            .optimize = "Set optimization level, must be one of { Debug, ReleaseFast, ReleaseSmall } (default: ReleaseFast)",
            .arch = "Set build target CPU architecture, must be one of { x86_64, aarch64 } (default: Current CPU arch)",
            .os = "Set build target operating system, must be one of { linux, macos, windows } (default: Current OS)",
        },
    };
};

/// Run the deployment bundle generator. Create an archive containing the Jetzig executable,
/// with `public/` and `static/` directories.
pub fn run(
    allocator: std.mem.Allocator,
    options: Options,
    writer: anytype,
    T: type,
    main_options: T,
) !void {
    if (builtin.os.tag == .windows) {
        std.debug.print("Bundling on Windows is currently not supported.\n", .{});
        std.process.exit(1);
    }

    if (main_options.options.help) {
        try args.printHelp(Options, "jetzig bundle", writer);
        return;
    }

    std.debug.print("Compiling bundle...\n", .{});
    var cwd = try util.detectJetzigProjectDir();
    defer cwd.close();

    const path = try cwd.realpathAlloc(allocator, ".");

    cwd.deleteTree(".bundle") catch {};
    var tmpdir = try cwd.makeOpenPath(".bundle", .{});
    defer cwd.deleteTree(".bundle") catch {};
    defer tmpdir.close();

    defer allocator.free(path);

    const views_path = try std.fs.path.join(allocator, &[_][]const u8{ "src", "app", "views" });
    defer allocator.free(views_path);

    const maybe_executable = try zig_build_install(allocator, path, options);
    if (maybe_executable == null) {
        std.debug.print("Unable to locate compiled executable in {s}", .{path});
        util.printFailure();
        std.process.exit(1);
    }

    const executable = maybe_executable.?;

    // * Create .bundle/
    // * Compile exe in .bundle/
    // * Rename exe to `{bundle-name}/server`
    // * Copy `public`, `static` and any markdown files into `{bundle-name}/`
    // * Create tarball inside `.bundle/` from `{bundle-name}/`
    defer allocator.free(executable);

    const exe_basename = std.fs.path.basename(executable);

    // We don't use `std.fs.path.extension` here because the project name may have a `.` in it
    // which would be truncated when no `.exe` extension is present (e.g. on Linux).
    const exe_name_len = if (std.mem.endsWith(u8, executable, ".exe"))
        exe_basename.len - 4
    else
        exe_basename.len;
    const bundle_name = exe_basename[0..exe_name_len];

    var bundle_dir = try tmpdir.makeOpenPath(bundle_name, .{});
    defer bundle_dir.close();

    const bundle_real_path = try bundle_dir.realpathAlloc(allocator, ".");
    defer allocator.free(bundle_real_path);

    const exe_path = try std.fs.path.join(allocator, &[_][]const u8{ "bin", executable });
    defer allocator.free(exe_path);
    const renamed_exe_path = try std.fs.path.join(allocator, &[_][]const u8{ bundle_name, "server" });
    defer allocator.free(renamed_exe_path);

    try tmpdir.rename(exe_path, renamed_exe_path);

    var tar_argv = std.ArrayList([]const u8).init(allocator);
    defer tar_argv.deinit();
    switch (builtin.os.tag) {
        .windows => {}, // TODO
        else => {
            try tar_argv.appendSlice(&[_][]const u8{
                "tar",
                "-zcf",
                "../bundle.tar.gz",
                bundle_name,
            });
        },
    }
    var public_dir: ?std.fs.Dir = cwd.openDir("public", .{}) catch null;
    defer if (public_dir) |*dir| dir.close();

    var static_dir: ?std.fs.Dir = cwd.openDir("static", .{}) catch null;
    defer if (static_dir) |*dir| dir.close();

    if (public_dir != null) {
        const dest_path = try std.fs.path.join(allocator, &[_][]const u8{ bundle_real_path, "public" });
        defer allocator.free(dest_path);
        try copyTree(allocator, cwd, "public", dest_path);
    }

    if (static_dir != null) {
        const dest_path = try std.fs.path.join(allocator, &[_][]const u8{ bundle_real_path, "static" });
        defer allocator.free(dest_path);
        try copyTree(allocator, cwd, "static", dest_path);
    }

    var markdown_paths = std.ArrayList([]const u8).init(allocator);
    try locateMarkdownFiles(allocator, cwd, views_path, &markdown_paths);

    defer markdown_paths.deinit();
    defer for (markdown_paths.items) |markdown_path| allocator.free(markdown_path);
    for (markdown_paths.items) |markdown_path| {
        if (std.fs.path.dirname(markdown_path)) |dirname| bundle_dir.makePath(dirname) catch {};
        try cwd.copyFile(markdown_path, bundle_dir, markdown_path, .{});
    }

    const tmpdir_real_path = try tmpdir.realpathAlloc(allocator, ".");
    defer allocator.free(tmpdir_real_path);

    try util.runCommandInDir(allocator, tar_argv.items, .{ .path = tmpdir_real_path }, .{});

    switch (builtin.os.tag) {
        .windows => {},
        else => std.debug.print("Bundle `bundle.tar.gz` generated successfully.", .{}),
    }
    util.printSuccess(null);
}

fn locateMarkdownFiles(allocator: std.mem.Allocator, dir: std.fs.Dir, views_path: []const u8, paths: *std.ArrayList([]const u8)) !void {
    var views_dir = try dir.openDir(views_path, .{ .iterate = true });
    defer views_dir.close();
    var walker = try views_dir.walk(allocator);
    defer walker.deinit();

    while (try walker.next()) |entry| {
        if (std.mem.eql(u8, std.fs.path.extension(entry.path), ".md")) {
            const path = try std.fs.path.join(allocator, &[_][]const u8{ views_path, entry.path });
            try paths.append(path);
        }
    }
}

fn zig_build_install(allocator: std.mem.Allocator, path: []const u8, options: Options) !?[]const u8 {
    var install_argv = std.ArrayList([]const u8).init(allocator);
    defer install_argv.deinit();

    try install_argv.appendSlice(&[_][]const u8{ "zig", "build", "-Denvironment=production" });

    switch (options.optimize) {
        .ReleaseFast => try install_argv.append("-Doptimize=ReleaseFast"),
        .ReleaseSmall => try install_argv.append("-Doptimize=ReleaseSmall"),
        .Debug => try install_argv.append("-Doptimize=Debug"),
    }

    var target_buf = std.ArrayList([]const u8).init(allocator);
    defer target_buf.deinit();

    try target_buf.append("-Dtarget=");
    switch (options.arch) {
        .x86 => try target_buf.append("x86"),
        .x86_64 => try target_buf.append("x86_64"),
        .aarch64 => try target_buf.append("aarch64"),
        .default => try target_buf.append(@tagName(builtin.cpu.arch)),
    }

    try target_buf.append("-");

    switch (options.os) {
        .linux => try target_buf.append("linux"),
        .macos => try target_buf.append("macos"),
        .windows => try target_buf.append("windows"),
        .default => try target_buf.append(@tagName(builtin.os.tag)),
    }

    const target = try std.mem.concat(allocator, u8, target_buf.items);
    defer allocator.free(target);

    try install_argv.appendSlice(&[_][]const u8{
        target, "--prefix", ".bundle", "install",
    });

    var project_dir = try std.fs.openDirAbsolute(path, .{});
    defer project_dir.close();
    project_dir.makePath(".bundle") catch {};

    try util.runCommandInDir(allocator, install_argv.items, .{ .path = path }, .{});

    const install_bin_path = try std.fs.path.join(allocator, &[_][]const u8{ ".bundle", "bin" });
    defer allocator.free(install_bin_path);
    var install_dir = try project_dir.openDir(install_bin_path, .{ .iterate = true });
    defer install_dir.close();

    var install_walker = try install_dir.walk(allocator);
    defer install_walker.deinit();
    while (try install_walker.next()) |entry| {
        // TODO: Figure out what to do when multiple exe files are found.
        return try allocator.dupe(u8, entry.path);
    }
    return null;
}

fn copyTree(
    allocator: std.mem.Allocator,
    src_dir: std.fs.Dir,
    sub_path: []const u8,
    dest_path: []const u8,
) !void {
    var dir = try src_dir.openDir(sub_path, .{ .iterate = true });
    defer dir.close();

    var walker = try dir.walk(allocator);
    defer walker.deinit();

    std.fs.makeDirAbsolute(dest_path) catch {};
    var dest_dir = try std.fs.openDirAbsolute(dest_path, .{});
    defer dest_dir.close();

    while (try walker.next()) |entry| {
        if (std.fs.path.dirname(entry.path)) |dirname| dest_dir.makePath(dirname) catch {};
        try dir.copyFile(entry.path, dest_dir, entry.path, .{});
    }
}
