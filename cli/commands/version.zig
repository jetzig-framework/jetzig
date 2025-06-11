const std = @import("std");
const args = @import("args");
const version = @import("version");

/// Command line options for the `version` command.
pub const Options = struct {
    pub const meta = .{
        .usage_summary = "",
        .full_text = "Print Jetzig version.",
    };
};

/// Run the `jetzig version` command.
pub fn run(
    _: std.mem.Allocator,
    _: Options,
    writer: anytype,
    T: type,
    main_options: T,
) !void {
    if (main_options.options.help) {
        try args.printHelp(Options, "jetzig version", writer);
        return;
    }
    std.debug.print("{s}+{s}\n", .{ version.version, version.commit_hash });
}
