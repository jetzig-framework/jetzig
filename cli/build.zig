const std = @import("std");

const compile = @import("compile.zig");

pub fn build(b: *std.Build) !void {
    const target = b.standardTargetOptions(.{});
    const optimize = b.standardOptimizeOption(.{});

    const exe = b.addExecutable(.{
        .name = "jetzig",
        .root_source_file = b.path("cli.zig"),
        .target = target,
        .optimize = optimize,
    });

    const zig_args_dep = b.dependency("args", .{ .target = target, .optimize = optimize });

    exe.root_module.addImport("args", zig_args_dep.module("args"));
    exe.root_module.addImport(
        "init_data",
        try compile.initDataModule(b),
    );

    b.installArtifact(exe);

    const run_cmd = b.addRunArtifact(exe);
    run_cmd.step.dependOn(b.getInstallStep());
    if (b.args) |args| {
        run_cmd.addArgs(args);
    }
    const run_step = b.step("run", "Run the app");
    run_step.dependOn(&run_cmd.step);
}
