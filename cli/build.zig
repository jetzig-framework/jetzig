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
    const jetquery_dep = b.dependency("jetquery", .{
        .target = target,
        .optimize = optimize,
        .jetquery_migrations_path = @as([]const u8, "src/app/database/migrations"),
        .jetquery_seeders_path = @as([]const u8, "src/app/database/seeders"),
    });
    exe.root_module.addImport("jetquery", jetquery_dep.module("jetquery"));
    exe.root_module.addImport("args", zig_args_dep.module("args"));
    exe.root_module.addImport("init_data", try compile.initDataModule(b));

    b.installArtifact(exe);

    const run_cmd = b.addRunArtifact(exe);
    run_cmd.step.dependOn(b.getInstallStep());
    if (b.args) |args| {
        run_cmd.addArgs(args);
    }
    const run_step = b.step("run", "Run the app");
    run_step.dependOn(&run_cmd.step);
}
