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
            \\Set up a database: create a database, run migrations, reflect schema.
            \\
            \\Convenience wrapper for:
            \\
            \\* jetzig database create
            \\* jetzig database update
            \\
            \\Example:
            \\
            \\  jetzig database setup
            \\  jetzig --environment=testing setup
            \\
        , .{});

        return if (main_options.options.help) {} else error.JetzigCommandError;
    }

    const env = main_options.options.environment;
    try runCommand(allocator, env, "create");
    try runCommand(allocator, env, "migrate");
    try runCommand(allocator, env, "reflect");

    try util.print(
        .success,
        "Database created, migrations applied, and Schema generated successfully.",
        .{},
    );
}

fn runCommand(allocator: std.mem.Allocator, environment: anytype, comptime action: []const u8) !void {
    try util.runCommand(allocator, &.{
        "zig",
        "build",
        util.environmentBuildOption(environment),
        "jetzig:database:" ++ action,
    });
}
