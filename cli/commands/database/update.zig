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
            \\Update a database: run migrations and reflect schema.
            \\
            \\Convenience wrapper for `jetzig database migrate` and `jetzig database reflect`.
            \\
            \\Example:
            \\
            \\  jetzig database update
            \\  jetzig --environment=testing update
            \\
        , .{});

        return if (main_options.options.help) {} else error.JetzigCommandError;
    }

    try util.runCommand(allocator, &.{
        "zig",
        "build",
        util.environmentBuildOption(main_options.options.environment),
        "jetzig:database:migrate",
    });

    try util.runCommand(allocator, &.{
        "zig",
        "build",
        util.environmentBuildOption(main_options.options.environment),
        "jetzig:database:reflect",
    });
}
