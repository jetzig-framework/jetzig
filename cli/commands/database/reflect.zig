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
            \\Generate a JetQuery schema file and save to `src/app/database/Schema.zig`.
            \\
            \\Example:
            \\
            \\  jetzig database reflect
            \\
        , .{});

        return if (main_options.options.help) {} else error.JetzigCommandError;
    }

    try util.execCommand(allocator, &.{
        "zig",
        "build",
        util.environmentBuildOption(main_options.options.environment),
        "jetzig:database:reflect",
    });
}
