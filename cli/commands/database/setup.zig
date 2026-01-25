const std = @import("std");
const Allocator = std.mem.Allocator;

const cli = @import("../../cli.zig");
const util = @import("../../util.zig");

const help_msg =
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
;

pub fn run(
    allocator: Allocator,
    cwd: std.fs.Dir,
    args: []const []const u8,
    options: cli.database.Options,
    T: type,
    main_options: T,
) !void {
    _ = cwd;
    _ = options;
    if (main_options.options.help) {
        try util.stdout.print(help_msg, .{});
        return;
    }

    if (args.len != 0) {
        try util.stderr.print(help_msg, .{});
        return error.JetzigCommandError;
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

fn runCommand(allocator: Allocator, environment: anytype, comptime action: []const u8) !void {
    try util.runCommand(allocator, &.{
        "zig",
        "build",
        util.environmentBuildOption(environment),
        "jetzig:database:" ++ action,
    });
}
