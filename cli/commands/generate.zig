const std = @import("std");
const args = @import("args");
const view = @import("generate/view.zig");
const partial = @import("generate/partial.zig");
const middleware = @import("generate/middleware.zig");
const util = @import("../util.zig");

/// Command line options for the `generate` command.
pub const Options = struct {
    path: ?[]const u8 = null,

    pub const shorthands = .{
        .p = "path",
    };

    pub const meta = .{
        .usage_summary = "[view|middleware] [options]",
        .full_text =
        \\Generates scaffolding for views, middleware, and other objects in future.
        \\
        \\When generating a view, by default all actions will be included.
        \\Optionally pass one or more of the following arguments to specify desired actions:
        \\
        \\  index, get, post, patch, put, delete
        \\
        \\Each view action can be qualified with a `:static` option to mark the view content
        \\as statically generated at build time.
        \\
        \\e.g. generate a view named `iguanas` with a static `index` action:
        \\
        \\  jetzig generate view iguanas index:static get post delete
        ,
    };
};

/// Run the `jetzig init` command.
pub fn run(
    allocator: std.mem.Allocator,
    options: Options,
    writer: anytype,
    positionals: [][]const u8,
    other_options: struct { help: bool },
) !void {
    var cwd = try util.detectJetzigProjectDir();
    defer cwd.close();

    _ = options;
    if (other_options.help) {
        try args.printHelp(Options, "jetzig generate", writer);
        return;
    }
    var generate_type: ?enum { view, partial, middleware } = null;
    var sub_args = std.ArrayList([]const u8).init(allocator);
    defer sub_args.deinit();

    for (positionals) |arg| {
        if (generate_type == null and std.mem.eql(u8, arg, "view")) {
            generate_type = .view;
        } else if (generate_type == null and std.mem.eql(u8, arg, "partial")) {
            generate_type = .partial;
        } else if (generate_type == null and std.mem.eql(u8, arg, "middleware")) {
            generate_type = .middleware;
        } else if (generate_type == null) {
            std.debug.print("Unknown generator command: {s}\n", .{arg});
            return error.JetzigCommandError;
        } else {
            try sub_args.append(arg);
        }
    }

    if (generate_type) |capture| {
        return switch (capture) {
            .view => view.run(allocator, cwd, sub_args.items),
            .partial => partial.run(allocator, cwd, sub_args.items),
            .middleware => middleware.run(allocator, cwd, sub_args.items),
        };
    } else {
        std.debug.print("Missing sub-command. Expected: [view|middleware]\n", .{});
        return error.JetzigCommandError;
    }
}
