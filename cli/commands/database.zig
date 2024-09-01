const std = @import("std");
const args = @import("args");
const util = @import("../util.zig");
const jetquery = @import("jetquery");
const Migrate = @import("jetquery_migrate");

/// Command line options for the `database` command.
pub const Options = struct {
    pub const meta = .{
        .usage_summary = "[migrate]",
        .full_text =
        \\Manage the application's database.
        \\
        \\Pass `--help` to any command for more information, e.g.:
        \\
        \\  jetzig database migrate --help
        \\
        ,
    };
};

/// Run the `jetzig generate` command.
pub fn run(
    allocator: std.mem.Allocator,
    options: Options,
    writer: anytype,
    positionals: [][]const u8,
    other_options: struct { help: bool },
) !void {
    _ = options;
    _ = writer;
    _ = positionals;
    _ = other_options;
    try util.execCommand(allocator, &.{
        "zig",
        "build",
        "jetzig:migrate",
    });
}
