const std = @import("std");

/// Run the partial generator. Create a partial template in `src/app/views/`
pub fn run(allocator: std.mem.Allocator, cwd: std.fs.Dir, args: [][]const u8) !void {
    if (args.len != 2) {
        std.debug.print(
            \\Expected a view name and a name for a partial.
            \\
            \\Example:
            \\
            \\  jetzig generate partial iguanas ziglet
            \\
        , .{});
        return error.JetzigCommandError;
    }

    const dir_path = try std.fs.path.join(allocator, &[_][]const u8{ "src", "app", "views", args[0] });
    defer allocator.free(dir_path);

    var dir = try cwd.makeOpenPath(dir_path, .{});
    defer dir.close();

    const filename = try std.mem.concat(allocator, u8, &[_][]const u8{ "_", args[1], ".zmpl" });
    defer allocator.free(filename);

    const file = dir.createFile(filename, .{ .exclusive = true }) catch |err| {
        switch (err) {
            error.PathAlreadyExists => {
                std.debug.print("Partial already exists: {s}\n", .{filename});
                return error.JetzigCommandError;
            },
            else => return err,
        }
    };

    try file.writeAll(
        \\<div>Partial content goes here.</div>
        \\
    );

    file.close();

    const realpath = try dir.realpathAlloc(allocator, filename);
    defer allocator.free(realpath);
    std.debug.print("Generated partial template: {s}\n", .{realpath});
}
