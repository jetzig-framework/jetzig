const std = @import("std");

const jetquery = @import("jetquery");

/// Run the migration generator. Create a migration in `src/app/database/migrations/`
pub fn run(allocator: std.mem.Allocator, cwd: std.fs.Dir, args: [][]const u8, help: bool) !void {
    if (help or args.len < 1) {
        std.debug.print(
            \\Generate a new Migration. Migrations modify the application's database schema.
            \\
            \\Example:
            \\
            \\  jetzig generate migration create_iguanas
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

    const migrations_dir = try cwd.makeOpenPath(
        try std.fs.path.join(allocator, &.{ "src", "app", "database", "migrations" }),
        .{},
    );
    const migration = jetquery.Migration.init(
        allocator,
        name,
        .{
            .migrations_path = try migrations_dir.realpathAlloc(allocator, "."),
            .command = command,
        },
    );
    try migration.save();
}
