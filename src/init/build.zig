const std = @import("std");

pub fn build(b: *std.Build) !void {
    const target = b.standardTargetOptions(.{});

    const optimize = b.standardOptimizeOption(.{});

    const exe = b.addExecutable(.{
        .name = "%%project_name%%",
        .root_source_file = .{ .path = "src/main.zig" },
        .target = target,
        .optimize = optimize,
    });

    b.installArtifact(exe);

    const jetzig = b.dependency("jetzig", .{ .optimize = optimize, .target = target });
    exe.addModule("jetzig", jetzig.module("jetzig"));
    try b.modules.put("jetzig", jetzig.module("jetzig"));

    const zmpl_dep = b.dependency(
        "zmpl",
        .{
            .target = target,
            .optimize = optimize,
            .zmpl_templates_path = @as([]const u8, "src/app/views/"),
            .zmpl_manifest_path = @as([]const u8, "src/app/views/zmpl.manifest.zig"),
        },
    );

    exe.addModule("zmpl", zmpl_dep.module("zmpl"));
    try b.modules.put("zmpl", zmpl_dep.module("zmpl"));

    const run_cmd = b.addRunArtifact(exe);
    run_cmd.step.dependOn(b.getInstallStep());

    if (b.args) |args| {
        run_cmd.addArgs(args);
    }

    const run_step = b.step("run", "Run the app");
    run_step.dependOn(&run_cmd.step);

    const unit_tests = b.addTest(.{
        .root_source_file = .{ .path = "src/main.zig" },
        .target = target,
        .optimize = optimize,
    });

    const run_unit_tests = b.addRunArtifact(unit_tests);

    const test_step = b.step("test", "Run unit tests");
    test_step.dependOn(&run_unit_tests.step);
}
