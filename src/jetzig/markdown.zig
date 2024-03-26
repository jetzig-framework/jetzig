const std = @import("std");

const jetzig = @import("../jetzig.zig");

const Zmd = @import("zmd").Zmd;
pub fn render(
    allocator: std.mem.Allocator,
    route: *const jetzig.views.Route,
    custom_fragments: ?type,
) !?[]const u8 {
    const fragments = custom_fragments orelse jetzig.config.get(type, "markdown_fragments");

    var path_buf = std.ArrayList([]const u8).init(allocator);
    defer path_buf.deinit();

    try path_buf.appendSlice(&[_][]const u8{ "src", "app", "views" });

    var it = std.mem.splitScalar(u8, route.uri_path, '/');
    while (it.next()) |segment| {
        try path_buf.append(segment);
    }
    try path_buf.append(@tagName(route.action));

    const base_path = try std.fs.path.join(allocator, path_buf.items);
    defer allocator.free(base_path);

    const full_path = try std.mem.concat(allocator, u8, &[_][]const u8{ base_path, ".md" });
    defer allocator.free(full_path);

    const stat = try std.fs.cwd().statFile(full_path);
    const markdown_content = std.fs.cwd().readFileAlloc(allocator, full_path, stat.size) catch |err| {
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
