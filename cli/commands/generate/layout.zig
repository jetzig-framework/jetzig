const std = @import("std");

/// Run the layout generator. Create a layout template in `src/app/views/layouts`
pub fn run(allocator: std.mem.Allocator, cwd: std.fs.Dir, args: [][]const u8, help: bool) !void {
    if (help or args.len != 1) {
        std.debug.print(
            \\Generate a layout. Layouts encapsulate common boilerplate mark-up.
            \\
            \\Specify a layout name to create a new Zmpl template in src/app/views/layouts/
            \\
            \\Example:
            \\
            \\  jetzig generate layout standard
            \\
        , .{});

        if (help) return;

        return error.JetzigCommandError;
    }

    const dir_path = try std.fs.path.join(
        allocator,
        &[_][]const u8{ "src", "app", "views", "layouts" },
    );
    defer allocator.free(dir_path);

    var dir = try cwd.makeOpenPath(dir_path, .{});
    defer dir.close();

    const filename = try std.mem.concat(allocator, u8, &[_][]const u8{ args[0], ".zmpl" });
    defer allocator.free(filename);

    const file = dir.createFile(filename, .{ .exclusive = true }) catch |err| {
        switch (err) {
            error.PathAlreadyExists => {
                std.debug.print("Layout already exists: {s}\n", .{filename});
                return error.JetzigCommandError;
            },
            else => return err,
        }
    };

    try file.writeAll(
        \\<html>
        \\  <head></head>
        \\  <body>
        \\    <main>{zmpl.content}</main>
        \\  </body>
        \\</html>
        \\
    );

    file.close();

    const realpath = try dir.realpathAlloc(allocator, filename);
    defer allocator.free(realpath);
    std.debug.print("Generated layout: {s}\n", .{realpath});
}
