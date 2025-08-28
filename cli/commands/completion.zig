const std = @import("std");
const args = @import("args");
const fish = struct {};

pub const Options = struct {
    pub const meta = .{
        .usage_summary = "[fish]",
        .full_text =
        \\Provides shell-completion for jetzig cli tool
        \\
        \\add `eval "$(jetzig completion SHELL_NAME)"` to your shell config
        \\
        \\we currently support : fish
        \\
        ,
    };
};

/// Run the `jetzig generate` command.
pub fn run(
    allocator: std.mem.Allocator,
    options: Options,
    stdout_writer: anytype,
    stderr_writer: anytype,
    T: type,
    main_options: T,
) !void {
    _ = options;

    const Shells = enum {
        fish,
    };
    var sub_args = std.array_list.Managed([]const u8).init(allocator);
    defer sub_args.deinit();

    var available_buf = std.array_list.Managed([]const u8).init(allocator);
    defer available_buf.deinit();

    const map = std.StaticStringMap(Shells).initComptime(.{
        .{ "fish", .fish },
    });
    for (map.keys()) |key| try available_buf.append(key);

    const available_help = try std.mem.join(allocator, "|", available_buf.items);
    defer allocator.free(available_help);

    const generate_type: ?Shells = if (main_options.positionals.len > 0)
        map.get(main_options.positionals[0])
    else
        null;

    if (main_options.positionals.len > 1) {
        for (main_options.positionals[1..]) |arg| try sub_args.append(arg);
    }

    if (main_options.options.help and generate_type == null) {
        try args.printHelp(Options, "jetzig generate", stderr_writer);
        return;
    } else if (generate_type == null) {
        std.debug.print("Missing sub-command. Expected: [{s}]\n", .{available_help});
        return error.JetzigCommandError;
    }

    if (generate_type) |capture| {
        return switch (capture) {
            .fish => stdout_writer.print(
                \\complete -c jetzig -e ## clear previous jetzig completion
                \\{s}
                \\
            , .{@embedFile("../jetzig.fish")}),
        };
    }
}
