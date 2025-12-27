const std = @import("std");

const Zmd = @import("zmd").Zmd;

const jetzig = @import("../jetzig.zig");

const ArrayList = std.ArrayList;

pub const MarkdownRenderOptions = struct {
    fragments: ?type = null,
};

pub fn render(
    allocator: std.mem.Allocator,
    content: []const u8,
    comptime options: MarkdownRenderOptions,
) ![]const u8 {
    const fragments = options.fragments orelse jetzig.config.get(type, "markdown_fragments");

    var zmd = Zmd.init(allocator);
    defer zmd.deinit();

    try zmd.parse(content);
    return try zmd.toHtml(fragments);
}

pub fn renderFile(
    allocator: std.mem.Allocator,
    path: []const u8,
    comptime options: MarkdownRenderOptions,
) !?[]const u8 {
    var path_buf: ArrayList([]const u8) = .empty;
    defer path_buf.deinit(allocator);

    try path_buf.appendSlice(allocator, &[_][]const u8{ "src", "app", "views" });

    var it = std.mem.splitScalar(u8, path, '/');
    while (it.next()) |segment| {
        try path_buf.append(allocator, segment);
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
    const content = std.fs.cwd().readFileAlloc(allocator, full_path, @intCast(stat.size)) catch |err| {
        switch (err) {
            error.FileNotFound => return null,
            else => return err,
        }
    };

    return try render(allocator, content, options);
}
