const std = @import("std");
const args = @import("args");
const util = @import("../util.zig");

/// Command line options for the `routes` command.
pub const Options = struct {
    pub const meta = .{
        .usage_summary = "",
        .full_text =
        \\Output all available routes for this app.
        \\
        \\Example:
        \\
        \\  jetzig routes
        ,
    };
};

/// Run the `jetzig routes` command.
pub fn run(
    allocator: std.mem.Allocator,
    options: Options,
    writer: anytype,
    T: type,
    main_options: T,
) !void {
    _ = options;
    if (main_options.options.help) {
        try args.printHelp(Options, "jetzig routes", writer);
        return;
    }

    var cwd = try util.detectJetzigProjectDir();
    defer cwd.close();

    const realpath = try std.fs.realpathAlloc(allocator, ".");
    defer allocator.free(realpath);

    try util.runCommandStreaming(allocator, realpath, &[_][]const u8{
        "zig",
        "build",
        "jetzig:routes",
    });
}
