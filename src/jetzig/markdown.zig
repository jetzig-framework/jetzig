const std = @import("std");
const Allocator = std.mem.Allocator;
const ArrayList = std.ArrayList;

const zmd = @import("zmd");

const jetzig = @import("../jetzig.zig");

pub const MarkdownRenderOptions = struct {
    formatters: ?zmd.Formatters = null,
};

pub fn render(
    allocator: Allocator,
    content: []const u8,
    comptime options: MarkdownRenderOptions,
) ![]const u8 {
    const formatters = options.formatters orelse jetzig.config.get(zmd.Formatters, "markdown_formatters");
    return zmd.parse(allocator, content, formatters);
}

pub fn renderFile(
    allocator: Allocator,
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
