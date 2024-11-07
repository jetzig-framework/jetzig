const std = @import("std");
const args = @import("args");

/// Command line options for the `update` command.
pub const Options = struct {
    pub const meta = .{
        .usage_summary = "[password]",
        .full_text =
        \\Generates a password
        \\Example:
        \\
        \\  jetzig update
        \\  jetzig update web
        ,
        .option_docs = .{
            .path = "Set the output path relative to the current directory (default: current directory)",
        },
    };
};

/// Run the `jetzig database` command.
pub fn run(
    allocator: std.mem.Allocator,
    options: Options,
    writer: anytype,
    T: type,
    main_options: T,
) !void {
    _ = options;
    var arena = std.heap.ArenaAllocator.init(allocator);
    defer arena.deinit();
    const alloc = arena.allocator();

    const Action = enum { password };
    const map = std.StaticStringMap(Action).initComptime(.{
        .{ "password", .password },
    });

    const action = if (main_options.positionals.len > 0)
        map.get(main_options.positionals[0])
    else
        null;
    const sub_args: []const []const u8 = if (main_options.positionals.len > 1)
        main_options.positionals[1..]
    else
        &.{};

    return if (main_options.options.help and action == null) blk: {
        try args.printHelp(Options, "jetzig database", writer);
        break :blk {};
    } else if (action == null) blk: {
        const available_help = try std.mem.join(alloc, "|", map.keys());
        std.debug.print("Missing sub-command. Expected: [{s}]\n", .{available_help});
        break :blk error.JetzigCommandError;
    } else if (action) |capture|
        switch (capture) {
            .password => blk: {
                if (sub_args.len < 1) {
                    std.debug.print("Missing argument. Expected a password paramater.\n", .{});
                    break :blk error.JetzigCommandError;
                } else {
                    const hash = try hashPassword(alloc, sub_args[0]);
                    try std.io.getStdOut().writer().print("Password hash: {s}\n", .{hash});
                }
            },
        };
}

pub fn hashPassword(allocator: std.mem.Allocator, password: []const u8) ![]const u8 {
    const buf = try allocator.alloc(u8, 128);
    return try std.crypto.pwhash.argon2.strHash(
        password,
        .{
            .allocator = allocator,
            .params = .{ .t = 3, .m = 32, .p = 4 },
        },
        buf,
    );
}
