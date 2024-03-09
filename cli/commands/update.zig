const std = @import("std");
const args = @import("args");
const util = @import("../util.zig");

/// Command line options for the `update` command.
pub const Options = struct {
    pub const meta = .{
        .usage_summary = "[NAME=jetzig]",
        .full_text =
        \\Updates the current project to the latest version of Jetzig.
        \\
        \\Optionally pass a positional argument to save the dependency to `build.zig.zon` with an
        \\alternative name.
        \\
        \\Equivalent to running `zig fetch --save=jetzig https://github.com/jetzig-framework/jetzig/archive/<latest-commit>.tar.gz`
        \\
        \\Example:
        \\
        \\  jetzig update
        \\  jetzig update web
        ,
        .option_docs = .{
            .path = "Set the output path relative to the current directory (default: current directory)",
        },
    };
};

/// Run the `jetzig update` command.
pub fn run(
    allocator: std.mem.Allocator,
    options: Options,
    writer: anytype,
    positionals: [][]const u8,
    other_options: struct { help: bool },
) !void {
    _ = options;
    if (other_options.help) {
        try args.printHelp(Options, "jetzig update", writer);
        return;
    }

    if (positionals.len > 1) {
        std.debug.print("Expected at most 1 positional argument, found {}\n", .{positionals.len});
        return error.JetzigCommandError;
    }

    const name = if (positionals.len > 0) positionals[0] else "jetzig";

    const github_url = try util.githubUrl(allocator);
    defer allocator.free(github_url);

    const save_arg = try std.mem.concat(allocator, u8, &[_][]const u8{ "--save=", name });
    defer allocator.free(save_arg);

    var cwd = try util.detectJetzigProjectDir();
    defer cwd.close();

    const realpath = try std.fs.realpathAlloc(allocator, ".");
    defer allocator.free(realpath);

    try util.runCommand(allocator, realpath, &[_][]const u8{
        "zig",
        "fetch",
        save_arg,
        github_url,
    });

    std.debug.print(
        \\Update complete.
        \\
    , .{});
}
