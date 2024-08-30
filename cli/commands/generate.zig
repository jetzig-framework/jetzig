const std = @import("std");
const args = @import("args");
const secret = @import("generate/secret.zig");
const util = @import("../util.zig");

const view = @import("generate/view.zig");
const partial = @import("generate/partial.zig");
const layout = @import("generate/layout.zig");
const middleware = @import("generate/middleware.zig");
const job = @import("generate/job.zig");
const mailer = @import("generate/mailer.zig");
const migration = @import("generate/migration.zig");

/// Command line options for the `generate` command.
pub const Options = struct {
    pub const meta = .{
        .usage_summary = "[view|partial|layout|mailer|middleware|job|secret|migration] [options]",
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

    const Generator = enum { view, partial, layout, mailer, middleware, job, secret, migration };
    var sub_args = std.ArrayList([]const u8).init(allocator);
    defer sub_args.deinit();

    var available_buf = std.ArrayList([]const u8).init(allocator);
    defer available_buf.deinit();

    // XXX: 0.12 Compatibility
    const map = if (@hasDecl(std, "ComptimeStringMap")) blk: {
        const inner_map = std.ComptimeStringMap(Generator, .{
            .{ "view", .view },
            .{ "partial", .partial },
            .{ "layout", .layout },
            .{ "job", .job },
            .{ "mailer", .mailer },
            .{ "middleware", .middleware },
            .{ "secret", .secret },
            .{ "migration", .migration },
        });
        for (inner_map.kvs) |kv| try available_buf.append(kv.key);
        break :blk inner_map;
    } else if (@hasDecl(std, "StaticStringMap")) blk: {
        const inner_map = std.StaticStringMap(Generator).initComptime(.{
            .{ "view", .view },
            .{ "partial", .partial },
            .{ "layout", .layout },
            .{ "job", .job },
            .{ "mailer", .mailer },
            .{ "middleware", .middleware },
            .{ "secret", .secret },
            .{ "migration", .migration },
        });
        for (inner_map.keys()) |key| try available_buf.append(key);
        break :blk inner_map;
    } else unreachable;

    const available_help = try std.mem.join(allocator, "|", available_buf.items);
    defer allocator.free(available_help);

    var arena_allocator = std.heap.ArenaAllocator.init(allocator);
    defer arena_allocator.deinit();
    const arena = arena_allocator.allocator();

    const generate_type: ?Generator = if (positionals.len > 0) map.get(positionals[0]) else null;

    if (positionals.len > 1) {
        for (positionals[1..]) |arg| try sub_args.append(arg);
    }

    if (other_options.help and generate_type == null) {
        try args.printHelp(Options, "jetzig generate", writer);
        return;
    } else if (generate_type == null) {
        std.debug.print("Missing sub-command. Expected: [{s}]\n", .{available_help});
        return error.JetzigCommandError;
    }

    if (generate_type) |capture| {
        return switch (capture) {
            .view => view.run(arena, cwd, sub_args.items, other_options.help),
            .partial => partial.run(arena, cwd, sub_args.items, other_options.help),
            .layout => layout.run(arena, cwd, sub_args.items, other_options.help),
            .mailer => mailer.run(arena, cwd, sub_args.items, other_options.help),
            .job => job.run(arena, cwd, sub_args.items, other_options.help),
            .middleware => middleware.run(arena, cwd, sub_args.items, other_options.help),
            .secret => secret.run(arena, cwd, sub_args.items, other_options.help),
            .migration => migration.run(arena, cwd, sub_args.items, other_options.help),
        };
    }
}
