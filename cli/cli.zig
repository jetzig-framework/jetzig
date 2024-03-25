const std = @import("std");
const args = @import("args");
const init = @import("commands/init.zig");
const update = @import("commands/update.zig");
const generate = @import("commands/generate.zig");
const server = @import("commands/server.zig");
const bundle = @import("commands/bundle.zig");

const Options = struct {
    help: bool = false,

    pub const shorthands = .{
        .h = "help",
    };

    pub const meta = .{
        .usage_summary = "[COMMAND]",
        .option_docs = .{
            .init = "Initialize a new project",
            .update = "Update current project to latest version of Jetzig",
            .generate = "Generate scaffolding",
            .server = "Run a development server",
            .bundle = "Create a deployment bundle",
            .help = "Print help and exit",
        },
    };
};

const Verb = union(enum) {
    init: init.Options,
    update: update.Options,
    generate: generate.Options,
    server: server.Options,
    bundle: bundle.Options,
    g: generate.Options,
    s: server.Options,
    b: bundle.Options,
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

    run(allocator, options, writer) catch |err| {
        switch (err) {
            error.JetzigCommandError => std.process.exit(1),
            else => return err,
        }
    };

    if ((!options.options.help and options.verb == null) or (options.options.help and options.verb == null)) {
        try args.printHelp(Options, "jetzig", writer);
        try writer.writeAll(
            \\
            \\Commands:
            \\
            \\  init         Initialize a new project.
            \\  update       Update current project to latest version of Jetzig.
            \\  generate     Generate scaffolding.
            \\  server       Run a development server.
            \\  bundle       Create a deployment bundle.
            \\
            \\ Pass --help to any command for more information, e.g. `jetzig init --help`
            \\
        );
    }
}

fn run(allocator: std.mem.Allocator, options: args.ParseArgsResult(Options, Verb), writer: anytype) !void {
    if (options.verb) |verb| {
        return switch (verb) {
            .init => |opts| init.run(
                allocator,
                opts,
                writer,
                options.positionals,
                .{ .help = options.options.help },
            ),
            .g, .generate => |opts| generate.run(
                allocator,
                opts,
                writer,
                options.positionals,
                .{ .help = options.options.help },
            ),
            .update => |opts| update.run(
                allocator,
                opts,
                writer,
                options.positionals,
                .{ .help = options.options.help },
            ),
            .s, .server => |opts| server.run(
                allocator,
                opts,
                writer,
                options.positionals,
                .{ .help = options.options.help },
            ),
            .b, .bundle => |opts| bundle.run(
                allocator,
                opts,
                writer,
                options.positionals,
                .{ .help = options.options.help },
            ),
        };
    }
}
