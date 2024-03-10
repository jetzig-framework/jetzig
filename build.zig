const std = @import("std");

pub const GenerateRoutes = @import("src/GenerateRoutes.zig");
pub const GenerateMimeTypes = @import("src/GenerateMimeTypes.zig");
pub const TemplateFn = @import("src/jetzig.zig").TemplateFn;
pub const StaticRequest = @import("src/jetzig.zig").StaticRequest;
pub const http = @import("src/jetzig/http.zig");
pub const data = @import("src/jetzig/data.zig");
pub const views = @import("src/jetzig/views.zig");

pub fn build(b: *std.Build) !void {
    const target = b.standardTargetOptions(.{});
    const optimize = b.standardOptimizeOption(.{});
    const template_path = b.option([]const u8, "zmpl_templates_path", "Path to templates") orelse "src/app/views/";

    const lib = b.addStaticLibrary(.{
        .name = "jetzig",
        .root_source_file = .{ .path = "src/jetzig.zig" },
        .target = target,
        .optimize = optimize,
    });

    const mime_module = try GenerateMimeTypes.generateMimeModule(b);

    const zig_args_dep = b.dependency("args", .{ .target = target, .optimize = optimize });

    const jetzig_module = b.addModule("jetzig", .{ .root_source_file = .{ .path = "src/jetzig.zig" } });
    jetzig_module.addImport("mime_types", mime_module);
    lib.root_module.addImport("jetzig", jetzig_module);

    const zmpl_dep = b.dependency(
        "zmpl",
        .{
            .target = target,
            .optimize = optimize,
            .zmpl_templates_path = template_path,
        },
    );

    lib.root_module.addImport("zmpl", zmpl_dep.module("zmpl"));
    jetzig_module.addImport("zmpl", zmpl_dep.module("zmpl"));
    lib.root_module.addImport("args", zig_args_dep.module("args"));

    // This is the way to make it look nice in the zig build script
    // If we would do it the other way around, we would have to do
    // b.dependency("jetzig",.{}).builder.dependency("zmpl",.{}).module("zmpl");
    b.modules.put("zmpl", zmpl_dep.module("zmpl")) catch @panic("Out of memory");

    const main_tests = b.addTest(.{
        .root_source_file = .{ .path = "src/tests.zig" },
        .target = target,
        .optimize = optimize,
    });

    const docs_step = b.step("docs", "Generate documentation");
    const docs_install = b.addInstallDirectory(.{
        .source_dir = lib.getEmittedDocs(),
        .install_dir = .prefix,
        .install_subdir = "docs",
    });

    docs_step.dependOn(&docs_install.step);

    main_tests.root_module.addImport("zmpl", zmpl_dep.module("zmpl"));
    const run_main_tests = b.addRunArtifact(main_tests);

    const test_step = b.step("test", "Run library tests");
    test_step.dependOn(&run_main_tests.step);
}

/// Placeholder for potential options we may add in future without breaking
/// backward-compatibility.
pub const JetzigInitOptions = struct {};

pub fn jetzigInit(b: *std.Build, exe: *std.Build.Step.Compile, options: JetzigInitOptions) !void {
    _ = options;
    const target = b.host;
    const optimize = exe.root_module.optimize orelse .Debug;
    const jetzig_dep = b.dependency(
        "jetzig",
        .{ .optimize = optimize, .target = b.host },
    );
    const jetzig_module = jetzig_dep.module("jetzig");
    const zmpl_module = jetzig_dep.module("zmpl");

    exe.root_module.addImport("jetzig", jetzig_module);
    exe.root_module.addImport("zmpl", zmpl_module);

    var generate_routes = try GenerateRoutes.init(b.allocator, "src/app/views");
    try generate_routes.generateRoutes();
    const write_files = b.addWriteFiles();
    const routes_file = write_files.add("routes.zig", generate_routes.buffer.items);
    const routes_module = b.createModule(.{ .root_source_file = routes_file });

    var src_dir = try std.fs.openDirAbsolute(b.pathFromRoot("src"), .{ .iterate = true });
    defer src_dir.close();
    var walker = try src_dir.walk(b.allocator);
    defer walker.deinit();

    while (try walker.next()) |entry| {
        if (entry.kind == .file) {
            if (!std.mem.eql(u8, ".zig", std.fs.path.extension(entry.path))) continue;

            const stat = try src_dir.statFile(entry.path);
            const src_data = try src_dir.readFileAlloc(b.allocator, entry.path, stat.size);
            defer b.allocator.free(src_data);

            const relpath = try std.fs.path.join(b.allocator, &[_][]const u8{ "src", entry.path });
            defer b.allocator.free(relpath);

            _ = write_files.add(relpath, src_data);
        }
    }

    const exe_static_routes = b.addExecutable(.{
        .name = "static",
        .root_source_file = jetzig_dep.path("src/compile_static_routes.zig"),
        .target = target,
        .optimize = optimize,
    });

    exe.root_module.addImport("routes", routes_module);
    routes_module.addImport("jetzig", jetzig_module);

    exe_static_routes.root_module.addImport("routes", routes_module);
    exe_static_routes.root_module.addImport("jetzig", jetzig_module);
    exe_static_routes.root_module.addImport("zmpl", zmpl_module);

    const run_static_routes_cmd = b.addRunArtifact(exe_static_routes);
    exe.step.dependOn(&run_static_routes_cmd.step);
}
