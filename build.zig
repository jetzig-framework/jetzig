const std = @import("std");

pub fn build(b: *std.Build) !void {
    const target = b.standardTargetOptions(.{});
    const optimize = b.standardOptimizeOption(.{});

    const lib = b.addStaticLibrary(.{
        .name = "jetzig",
        .root_source_file = .{ .path = "src/main.zig" },
        .target = target,
        .optimize = optimize,
    });

    b.installArtifact(lib);

    const exe = b.addExecutable(.{
        .name = "jetzig",
        .root_source_file = .{ .path = "src/main.zig" },
        .target = target,
        .optimize = optimize,
    });

    b.installArtifact(exe);

    const jetzig_module = b.createModule(.{ .source_file = .{ .path = "src/jetzig.zig" } });
    exe.addModule("jetzig", jetzig_module);
    lib.addModule("jetzig", jetzig_module);
    try b.modules.put("jetzig", jetzig_module);

    const zmpl_dep = b.dependency(
        "zmpl",
        .{
            .target = target,
            .optimize = optimize,
            .zmpl_templates_path = @as([]const u8, "src/app/views/"),
            .zmpl_manifest_path = @as([]const u8, "src/app/views/zmpl.manifest.zig"),
        },
    );

    lib.addModule("zmpl", zmpl_dep.module("zmpl"));
    exe.addModule("zmpl", zmpl_dep.module("zmpl"));
    try b.modules.put("zmpl", zmpl_dep.module("zmpl"));
    try jetzig_module.dependencies.put("zmpl", zmpl_dep.module("zmpl"));

    var dir = std.fs.cwd();
    var views_dir = try dir.makeOpenPath("src/app/views", .{});
    var file = try views_dir.createFile("routes.zig", .{ .truncate = true });
    try file.writeAll("pub const routes = .{\n");
    const views = try findViews(b.allocator);
    for (views.items) |view| {
        try file.writeAll(try std.fmt.allocPrint(b.allocator, "  @import(\"{s}\"),\n", .{view.path}));
        std.debug.print("[jetzig] Imported view: {s}\n", .{view.path});
    }

    try file.writeAll("};\n");
    file.close();

    const run_cmd = b.addRunArtifact(exe);

    run_cmd.step.dependOn(b.getInstallStep());
    if (b.args) |args| run_cmd.addArgs(args);

    const run_step = b.step("run", "Run the app");
    run_step.dependOn(&run_cmd.step);

    const main_tests = b.addTest(.{
        .root_source_file = .{ .path = "src/tests.zig" },
        .target = target,
        .optimize = optimize,
    });

    main_tests.addModule("zmpl", zmpl_dep.module("zmpl"));
    const run_main_tests = b.addRunArtifact(main_tests);

    const test_step = b.step("test", "Run library tests");
    test_step.dependOn(&run_main_tests.step);
}

const ViewItem = struct {
    path: []const u8,
    name: []const u8,
};

fn findViews(allocator: std.mem.Allocator) !std.ArrayList(*ViewItem) {
    var array = std.ArrayList(*ViewItem).init(allocator);
    const dir = try std.fs.cwd().openIterableDir("src/app/views", .{});
    var walker = try dir.walk(allocator);
    defer walker.deinit();
    while (try walker.next()) |entry| {
        if (entry.kind != .file) continue;
        const extension = std.fs.path.extension(entry.path);
        const basename = std.fs.path.basename(entry.path);
        if (std.mem.eql(u8, basename, "routes.zig")) continue;
        if (std.mem.eql(u8, basename, "zmpl.manifest.zig")) continue;
        if (std.mem.startsWith(u8, basename, ".")) continue;
        if (!std.mem.eql(u8, extension, ".zig")) continue;

        var sanitized_array = std.ArrayList(u8).init(allocator);
        for (entry.path) |char| {
            if (std.mem.indexOfAny(u8, &[_]u8{char}, "abcdefghijklmnopqrstuvwxyz")) |_| try sanitized_array.append(char);
        }
        const ptr = try allocator.create(ViewItem);
        ptr.* = .{
            .path = try allocator.dupe(u8, entry.path),
            .name = try allocator.dupe(u8, sanitized_array.items),
        };
        try array.append(ptr);
    }
    return array;
}
