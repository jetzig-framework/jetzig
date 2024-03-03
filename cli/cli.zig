const std = @import("std");
const args = @import("args");
const init = @import("init.zig");

const Options = struct {
    help: bool = false,

    pub const shorthands = .{
        .h = "help",
    };

    pub const meta = .{
        .option_docs = .{
            .init = "Initialize a new project",
            .help = "Print help and exit",
        },
    };
};

const Verb = union(enum) {
    init: init.Options,
};

/// Main entrypoint for `jetzig` executable. Parses command line args and generates a new
/// project, scaffolding, etc.
pub fn main() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    const allocator = gpa.allocator();
    defer std.debug.assert(gpa.deinit() == .ok);

    const options = try args.parseWithVerbForCurrentProcess(Options, Verb, allocator, .print);
    defer options.deinit();

    const writer = std.io.getStdErr().writer();

    if (options.verb) |verb| {
        switch (verb) {
            .init => |opts| return init.run(
                allocator,
                opts,
                writer,
                options.positionals,
                .{ .help = options.options.help },
            ),
        }
    }

    if (options.options.help) {
        try args.printHelp(Options, "jetzig", writer);
        try writer.writeAll(
            \\
            \\Commands:
            \\
            \\  init         Initialize a new project.
            \\
            \\ Pass --help to any command for more information, e.g. `jetzig init --help`
            \\
        );
    }
}
