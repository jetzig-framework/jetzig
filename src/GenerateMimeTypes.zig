const std = @import("std");

const JsonMimeType = struct {
    name: []const u8,
    fileTypes: [][]const u8,
};

/// Invoked at build time to parse mimeData.json into an array of `MimeType` which can then be
/// written out as a Zig struct and imported at runtime.
pub fn generateMimeModule(build: *std.Build) !*std.Build.Module {
    const file = try std.fs.openFileAbsolute(build.pathFromRoot("src/jetzig/http/mime/mimeData.json"), .{});
    const stat = try file.stat();
    const json = try file.readToEndAlloc(build.allocator, @intCast(stat.size));
    defer build.allocator.free(json);

    const parsed_mime_types = try std.json.parseFromSlice(
        []JsonMimeType,
        build.allocator,
        json,
        .{ .ignore_unknown_fields = true },
    );

    var buf = std.array_list.Managed(u8).init(build.allocator);
    defer buf.deinit();

    const writer = buf.writer();

    try writer.writeAll("pub const MimeType = struct { name: []const u8, file_type: []const u8 };");
    try writer.writeAll("pub const mime_types = [_]MimeType{\n");
    for (parsed_mime_types.value) |mime_type| {
        for (mime_type.fileTypes) |file_type| {
            const entry = try std.fmt.allocPrint(
                build.allocator,
                \\.{{ .name = "{s}", .file_type = "{s}" }},
                \\
            ,
                .{ mime_type.name, file_type },
            );
            try writer.writeAll(entry);
        }
    }
    try writer.writeAll("};\n");

    const write_files = build.addWriteFiles();
    const generated_file = write_files.add("mime_types.zig", buf.items);
    return build.createModule(.{ .root_source_file = generated_file });
}
