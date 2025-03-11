const std = @import("std");

fn base64Encode(allocator: std.mem.Allocator, input: []const u8) []const u8 {
    const encoder = std.base64.Base64Encoder.init(
        std.base64.url_safe_no_pad.alphabet_chars,
        std.base64.url_safe_no_pad.pad_char,
    );
    const size = encoder.calcSize(input.len);
    const ptr = allocator.alloc(u8, size) catch @panic("OOM");
    _ = encoder.encode(ptr, input);
    return ptr;
}

pub fn initDataModule(build: *std.Build) !*std.Build.Module {
    const root_path = build.pathFromRoot("..");

    var buf = std.ArrayList(u8).init(build.allocator);
    defer buf.deinit();

    const writer = buf.writer();

    const paths = .{
        "demo/build.zig",
        "demo/src/main.zig",
        "demo/src/app/middleware/DemoMiddleware.zig",
        "demo/src/app/views/init.zig",
        "demo/src/app/views/init/index.zmpl",
        "demo/src/app/views/init/_content.zmpl",
        "demo/public/jetzig.png",
        "demo/public/zmpl.png",
        "demo/public/favicon.ico",
        "demo/public/styles.css",
        "demo/config/database_template.zig",
        ".gitignore",
    };

    try writer.writeAll(
        \\pub const init_data = .{
        \\
    );

    var dir = try std.fs.openDirAbsolute(root_path, .{});
    defer dir.close();

    inline for (paths) |path| {
        const stat = try dir.statFile(path);
        const encoded = base64Encode(
            build.allocator,
            try dir.readFileAlloc(build.allocator, path, @intCast(stat.size)),
        );
        defer build.allocator.free(encoded);

        const output = try std.fmt.allocPrint(
            build.allocator,
            \\.{{ .path = "{s}", .data = "{s}" }},
        ,
            .{ path, encoded },
        );
        defer build.allocator.free(output);

        try writer.writeAll(output);
    }

    try writer.writeAll(
        \\};
        \\
    );

    const write_files = build.addWriteFiles();
    const init_data_source = write_files.add("init_data.zig", buf.items);
    return build.createModule(.{ .root_source_file = init_data_source });
}
