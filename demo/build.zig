const std = @import("std");
const jetzig_build = @import("jetzig");
pub const zmpl = jetzig_build.zmpl;

const GenerateRoutes = @import("jetzig").GenerateRoutes;

pub fn build(b: *std.Build) !void {
    const target = b.standardTargetOptions(.{});

    const optimize = b.standardOptimizeOption(.{});
    const jetzig_dep = b.dependency("jetzig", .{ .optimize = optimize, .target = target });

    const lib = b.addStaticLibrary(.{
        .name = "jetzig-demo",
        .root_source_file = .{ .path = "src/main.zig" },
        .target = target,
        .optimize = optimize,
    });

    b.installArtifact(lib);

    const exe = b.addExecutable(.{
        .name = "jetzig-demo",
        .root_source_file = .{ .path = "src/main.zig" },
        .target = target,
        .optimize = optimize,
    });

    const jetzig_module = jetzig_dep.module("jetzig");
    const zmpl_module = jetzig_dep.module("zmpl");

    exe.root_module.addImport("jetzig", jetzig_module);
    lib.root_module.addImport("jetzig", jetzig_module);
    exe.root_module.addImport("zmpl", zmpl_module);
    lib.root_module.addImport("zmpl", zmpl_module);

    b.installArtifact(exe);

    var generate_routes = try GenerateRoutes.init(b.allocator, "src/app/views");
    try generate_routes.generateRoutes();
    const write_files = b.addWriteFiles();
    const routes_file = write_files.add("routes.zig", generate_routes.buffer.items);
    for (generate_routes.static_routes.items) |route| _ = write_files.add(route.path, route.source);
    for (generate_routes.dynamic_routes.items) |route| _ = write_files.add(route.path, route.source);
    const routes_module = b.createModule(.{ .root_source_file = routes_file });

    const exe_static_routes = b.addExecutable(.{
        .name = "static",
        .root_source_file = jetzig_dep.path("src/compile_static_routes.zig"),
        .target = target,
        .optimize = optimize,
    });

    exe.root_module.addImport("routes", routes_module);
    lib.root_module.addImport("routes", routes_module);
    routes_module.addImport("jetzig", jetzig_module);

    exe_static_routes.root_module.addImport("routes", routes_module);
    exe_static_routes.root_module.addImport("jetzig", jetzig_module);
    exe_static_routes.root_module.addImport("zmpl", zmpl_module);

    const run_static_routes_cmd = b.addRunArtifact(exe_static_routes);
    exe.step.dependOn(&run_static_routes_cmd.step);

    const run_cmd = b.addRunArtifact(exe);
    run_cmd.step.dependOn(b.getInstallStep());

    if (b.args) |args| {
        run_cmd.addArgs(args);
    }

    const run_step = b.step("run", "Run the app");
    run_step.dependOn(&run_cmd.step);

    const lib_unit_tests = b.addTest(.{
        .root_source_file = .{ .path = "src/main.zig" },
        .target = target,
        .optimize = optimize,
    });

    const run_lib_unit_tests = b.addRunArtifact(lib_unit_tests);

    const exe_unit_tests = b.addTest(.{
        .root_source_file = .{ .path = "src/main.zig" },
        .target = target,
        .optimize = optimize,
    });

    const run_exe_unit_tests = b.addRunArtifact(exe_unit_tests);

    const test_step = b.step("test", "Run unit tests");
    test_step.dependOn(&run_lib_unit_tests.step);
    test_step.dependOn(&run_exe_unit_tests.step);
}
