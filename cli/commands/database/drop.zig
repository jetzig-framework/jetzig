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
            \\Drop database.
            \\
            \\Example:
            \\
            \\  jetzig database drop
            \\  jetzig --environment=testing database drop
            \\
            \\To drop a production database, set the environment variable `{s}` to the name of the database you want to drop, e.g.:
            \\
            \\  {0s}=my_production_production jetzig --environment=production database drop
            \\
        , .{cli.database.confirm_drop_env});

        return if (main_options.options.help) {} else error.JetzigCommandError;
    }

    try util.execCommand(allocator, &.{
        "zig",
        "build",
        util.environmentBuildOption(main_options.options.environment),
        "jetzig:database:drop",
    });
}
