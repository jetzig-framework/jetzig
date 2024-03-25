const std = @import("std");
const builtin = @import("builtin");

const args = @import("args");

const util = @import("../util.zig");

/// Command line options for the `bundle` command.
pub const Options = struct {
    optimize: enum { Debug, ReleaseFast, ReleaseSmall } = .ReleaseFast,
    arch: enum { x86_64, aarch64, default } = .default,
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
    positionals: [][]const u8,
    other_options: struct { help: bool },
) !void {
    _ = positionals;
    if (other_options.help) {
        try args.printHelp(Options, "jetzig bundle", writer);
        return;
    }

    std.debug.print("Compiling bundle...\n", .{});
    var cwd = try util.detectJetzigProjectDir();
    defer cwd.close();

    const path = try cwd.realpathAlloc(allocator, ".");
    defer allocator.free(path);

    if (try util.locateExecutable(allocator, cwd, .{ .relative = true })) |executable| {
        defer allocator.free(executable);

        var tar_argv = std.ArrayList([]const u8).init(allocator);
        defer tar_argv.deinit();

        var install_argv = std.ArrayList([]const u8).init(allocator);
        defer install_argv.deinit();

        try install_argv.appendSlice(&[_][]const u8{ "zig", "build", "--color", "on" });

        switch (builtin.os.tag) {
            .windows => try tar_argv.appendSlice(&[_][]const u8{
                "tar.exe",
                "-a",
                "-c",
                "-f",
                "bundle.zip",
                executable,
            }),
            else => try tar_argv.appendSlice(&[_][]const u8{
                "tar",
                "--transform=s,^,jetzig/,",
                "--transform=s,^jetzig/zig-out/bin/,jetzig/,",
                "-zcf",
                "bundle.tar.gz",
                executable,
            }),
        }

        switch (options.optimize) {
            .ReleaseFast => try install_argv.append("-Doptimize=ReleaseFast"),
            .ReleaseSmall => try install_argv.append("-Doptimize=ReleaseSmall"),
            .Debug => try install_argv.append("-Doptimize=Debug"),
        }

        var target_buf = std.ArrayList([]const u8).init(allocator);
        defer target_buf.deinit();

        try target_buf.append("-Dtarget=");
        switch (options.arch) {
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

        try install_argv.append(target);
        try install_argv.append("install");

        var public_dir: ?std.fs.Dir = cwd.openDir("public", .{}) catch null;
        defer if (public_dir) |*dir| dir.close();

        var static_dir: ?std.fs.Dir = cwd.openDir("static", .{}) catch null;
        defer if (static_dir) |*dir| dir.close();

        if (public_dir != null) try tar_argv.append("public");
        if (static_dir != null) try tar_argv.append("static");

        try util.runCommand(allocator, path, install_argv.items);
        try util.runCommand(allocator, path, tar_argv.items);

        switch (builtin.os.tag) {
            .windows => std.debug.print("Bundle `bundle.zip` generated successfully.", .{}),
            else => std.debug.print("Bundle `bundle.tar.gz` generated successfully.", .{}),
        }
        util.printSuccess();
    } else {
        std.debug.print("Unable to locate compiled executable. Exiting.", .{});
        util.printFailure();
        std.process.exit(1);
    }
}
