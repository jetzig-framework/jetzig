const std = @import("std");
const args = @import("args");

pub const init = @import("commands/init.zig");
pub const update = @import("commands/update.zig");
pub const generate = @import("commands/generate.zig");
pub const server = @import("commands/server.zig");
pub const routes = @import("commands/routes.zig");
pub const bundle = @import("commands/bundle.zig");
pub const tests = @import("commands/tests.zig");
pub const database = @import("commands/database.zig");
pub const auth = @import("commands/auth.zig");
pub const version = @import("commands/version.zig");
pub const completion = @import("commands/completion.zig");

pub const Environment = enum { development, testing, production };

pub const Options = struct {
    help: bool = false,
    environment: Environment = .development,

    pub const shorthands = .{
        .h = "help",
        .e = "environment",
    };

    pub const meta = .{
        .usage_summary = "[COMMAND]",
        .option_docs = .{
            .init = "Initialize a new project",
            .update = "Update current project to latest version of Jetzig",
            .generate = "Generate scaffolding",
            .server = "Run a development server",
            .routes = "List all routes in your app",
            .bundle = "Create a deployment bundle",
            .@"test" = "Run app tests",
            .database = "Manage the application's database",
            .help = "Print help and exit",
            .environment = "Jetzig environment.",
            .completion = "Provide shell-completion.",
        },
    };
};

const Verb = union(enum) {
    init: init.Options,
    update: update.Options,
    generate: generate.Options,
    server: server.Options,
    routes: routes.Options,
    bundle: bundle.Options,
    @"test": tests.Options,
    database: database.Options,
    auth: auth.Options,
    version: version.Options,
    completion: completion.Options,
    g: generate.Options,
    s: server.Options,
    r: routes.Options,
    b: bundle.Options,
    t: tests.Options,
    d: database.Options,
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
    const stdout_writer = std.io.getStdOut().writer();

    run(allocator, options, stdout_writer, writer) catch |err| {
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
            \\  routes       List all routes in your app.
            \\  bundle       Create a deployment bundle.
            \\  database     Manage the application's database.
            \\  auth         Utilities for Jetzig authentication.
            \\  test         Run app tests.
            \\  completion   Provide shell-completion.
            \\  version      Print Jetzig version.
            \\
            \\ Pass --help to any command for more information, e.g. `jetzig init --help`
            \\
        );
    }
}

fn run(allocator: std.mem.Allocator, options: args.ParseArgsResult(Options, Verb), stdout_writer: anytype, writer: anytype) !void {
    const OptionsType = args.ParseArgsResult(Options, Verb);

    if (options.verb) |verb| {
        return switch (verb) {
            .init => |opts| init.run(
                allocator,
                opts,
                writer,
                OptionsType,
                options,
            ),
            .g, .generate => |opts| generate.run(
                allocator,
                opts,
                writer,
                OptionsType,
                options,
            ),
            .update => |opts| update.run(
                allocator,
                opts,
                writer,
                OptionsType,
                options,
            ),
            .version => |opts| version.run(
                allocator,
                opts,
                writer,
                OptionsType,
                options,
            ),
            .s, .server => |opts| server.run(
                allocator,
                opts,
                writer,
                OptionsType,
                options,
            ),
            .r, .routes => |opts| routes.run(
                allocator,
                opts,
                writer,
                OptionsType,
                options,
            ),
            .b, .bundle => |opts| bundle.run(
                allocator,
                opts,
                writer,
                OptionsType,
                options,
            ),
            .t, .@"test" => |opts| tests.run(
                allocator,
                opts,
                writer,
                OptionsType,
                options,
            ),
            .d, .database => |opts| database.run(
                allocator,
                opts,
                writer,
                OptionsType,
                options,
            ),
            .auth => |opts| auth.run(
                allocator,
                opts,
                writer,
                OptionsType,
                options,
            ),
            .completion => |opts| completion.run(
                allocator,
                opts,
                stdout_writer,
                writer,
                OptionsType,
                options,
            ),
        };
    }
}
