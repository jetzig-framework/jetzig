const std = @import("std");
const args = @import("args");
const view = @import("generate/view.zig");
const partial = @import("generate/partial.zig");
const layout = @import("generate/layout.zig");
const middleware = @import("generate/middleware.zig");
const job = @import("generate/job.zig");
const secret = @import("generate/secret.zig");
const util = @import("../util.zig");

/// Command line options for the `generate` command.
pub const Options = struct {
    pub const meta = .{
        .usage_summary = "[view|partial|layout|middleware|job|secret] [options]",
        .full_text =
        \\Generate scaffolding for views, middleware, and other objects.
        \\
        \\Pass `--help` to any generator for more information, e.g.:
        \\
        \\  jetzig generate view --help
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
    var cwd = try util.detectJetzigProjectDir();
    defer cwd.close();

    _ = options;

    var generate_type: ?enum { view, partial, layout, middleware, job, secret } = null;
    var sub_args = std.ArrayList([]const u8).init(allocator);
    defer sub_args.deinit();

    for (positionals) |arg| {
        if (generate_type == null and std.mem.eql(u8, arg, "view")) {
            generate_type = .view;
        } else if (generate_type == null and std.mem.eql(u8, arg, "partial")) {
            generate_type = .partial;
        } else if (generate_type == null and std.mem.eql(u8, arg, "layout")) {
            generate_type = .layout;
        } else if (generate_type == null and std.mem.eql(u8, arg, "job")) {
            generate_type = .job;
        } else if (generate_type == null and std.mem.eql(u8, arg, "middleware")) {
            generate_type = .middleware;
        } else if (generate_type == null and std.mem.eql(u8, arg, "secret")) {
            generate_type = .secret;
        } else if (generate_type == null) {
            std.debug.print("Unknown generator command: {s}\n", .{arg});
            return error.JetzigCommandError;
        } else {
            try sub_args.append(arg);
        }
    }

    if (other_options.help and generate_type == null) {
        try args.printHelp(Options, "jetzig generate", writer);
        return;
    }

    if (generate_type) |capture| {
        return switch (capture) {
            .view => view.run(allocator, cwd, sub_args.items, other_options.help),
            .partial => partial.run(allocator, cwd, sub_args.items, other_options.help),
            .layout => layout.run(allocator, cwd, sub_args.items, other_options.help),
            .job => job.run(allocator, cwd, sub_args.items, other_options.help),
            .middleware => middleware.run(allocator, cwd, sub_args.items, other_options.help),
            .secret => secret.run(allocator, cwd, sub_args.items, other_options.help),
        };
    } else {
        std.debug.print("Missing sub-command. Expected: [view|partial|layout|job|middleware|secret]\n", .{});
        return error.JetzigCommandError;
    }
}
