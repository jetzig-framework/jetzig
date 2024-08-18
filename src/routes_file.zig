const std = @import("std");
const Routes = @import("Routes.zig");

pub fn main() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer std.debug.assert(gpa.deinit() == .ok);
    const gpa_allocator = gpa.allocator();

    var arena = std.heap.ArenaAllocator.init(gpa_allocator);
    const allocator = arena.allocator();
    defer arena.deinit();

    var it = try std.process.argsWithAllocator(allocator);
    _ = it.next().?;
    const output_path = it.next().?;
    const root_path = it.next().?;
    const src_path = it.next().?;
    const templates_path = it.next().?;
    const views_path = it.next().?;
    const jobs_path = it.next().?;
    const mailers_path = it.next().?;

    var routes = try Routes.init(
        allocator,
        root_path,
        templates_path,
        views_path,
        jobs_path,
        mailers_path,
    );
    const generated_routes = try routes.generateRoutes();
    var src_dir = try std.fs.openDirAbsolute(src_path, .{ .iterate = true });
    defer src_dir.close();
    var walker = try src_dir.walk(allocator);
    defer walker.deinit();

    while (try walker.next()) |entry| {
        if (entry.kind == .file) {
            const stat = try src_dir.statFile(entry.path);
            const src_data = try src_dir.readFileAlloc(allocator, entry.path, @intCast(stat.size));
            const relpath = try std.fs.path.join(allocator, &[_][]const u8{ "src", entry.path });
            var dir = try std.fs.openDirAbsolute(std.fs.path.dirname(output_path).?, .{});
            const dest_dir = try dir.makeOpenPath(std.fs.path.dirname(relpath).?, .{});
            const src_file = try dest_dir.createFile(std.fs.path.basename(relpath), .{});
            try src_file.writeAll(src_data);
            src_file.close();
        }
    }

    const file = try std.fs.createFileAbsolute(output_path, .{ .truncate = true });
    try file.writeAll(generated_routes);
    file.close();
}
