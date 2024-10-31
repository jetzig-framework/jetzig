const std = @import("std");

const cli = @import("../../cli.zig");
const util = @import("../../util.zig");

pub fn run(
    allocator: std.mem.Allocator,
    cwd: std.fs.Dir,
    args: []const []const u8,
    options: cli.database.Options,
    T: type,
    main_options: T,
) !void {
    _ = cwd;
    _ = options;
    if (main_options.options.help or args.len != 0) {
        std.debug.print(
            \\Create a database.
            \\
            \\Example:
            \\
            \\  jetzig database create
            \\  jetzig --environment testing database create
            \\
        , .{});

        return if (main_options.options.help) {} else error.JetzigCommandError;
    }

    try util.execCommand(allocator, &.{
        "zig",
        "build",
        util.environmentBuildOption(main_options.options.environment),
        "jetzig:database:create",
    });
}
