const std = @import("std");

const Zmd = @import("zmd").Zmd;

const jetzig = @import("../jetzig.zig");

pub fn render(
    allocator: std.mem.Allocator,
    path: []const u8,
    custom_fragments: ?type,
) !?[]const u8 {
    const fragments = custom_fragments orelse jetzig.config.get(type, "markdown_fragments");

    var path_buf = std.ArrayList([]const u8).init(allocator);
    defer path_buf.deinit();

    try path_buf.appendSlice(&[_][]const u8{ "src", "app", "views" });

    var it = std.mem.splitScalar(u8, path, '/');
    while (it.next()) |segment| {
        try path_buf.append(segment);
    }

    const base_path = try std.fs.path.join(allocator, path_buf.items);
    defer allocator.free(base_path);

    const full_path = try std.mem.concat(allocator, u8, &[_][]const u8{ base_path, ".md" });
    defer allocator.free(full_path);

    const stat = std.fs.cwd().statFile(full_path) catch |err| {
        return switch (err) {
            error.FileNotFound => null,
            else => err,
        };
    };
    const markdown_content = std.fs.cwd().readFileAlloc(allocator, full_path, @intCast(stat.size)) catch |err| {
        switch (err) {
            error.FileNotFound => return null,
            else => return err,
        }
    };

    var zmd = Zmd.init(allocator);
    defer zmd.deinit();

    try zmd.parse(markdown_content);
    return try zmd.toHtml(fragments);
}
