const std = @import("std");

const jetquery = @import("jetquery");

/// Run the seeder generator. Create a seed in `src/app/database/seeders/`
pub fn run(allocator: std.mem.Allocator, cwd: std.fs.Dir, args: [][]const u8, help: bool) !void {
    if (help or args.len < 1) {
        std.debug.print(
            \\Generate a new Seeder. Seeders is a way to set up some inital data for your application.
            \\
            \\Example:
            \\
            \\  jetzig generate seeder iguana
            \\
            \\  More information: https://www.jetzig.dev/documentation/sections/database/command_line_tools
            \\
        , .{});

        if (help) return;

        return error.JetzigCommandError;
    }

    const name = args[0];
    const command = if (args.len > 1)
        try std.mem.join(allocator, " ", args[1..])
    else
        null;

    const seeders_dir = try cwd.makeOpenPath(
        try std.fs.path.join(allocator, &.{ "src", "app", "database", "seeders" }),
        .{},
    );
    const seed = jetquery.Seeder.init(
        allocator,
        name,
        .{
            .seeders_path = try seeders_dir.realpathAlloc(allocator, "."),
            .command = command,
        },
    );
    const path = try seed.save();

    std.log.info("Saved seed: {s}", .{path});
}
