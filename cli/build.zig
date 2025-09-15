const std = @import("std");

const compile = @import("compile.zig");

fn getGitHash(allocator: std.mem.Allocator) ![]const u8 {
    const args = &[_][]const u8{ "git", "rev-parse", "--short=10", "HEAD" };
    const proc = try std.process.Child.run(.{
        .allocator = allocator,
        .argv = args,
    });
    defer allocator.free(proc.stderr);

    const trimmed = std.mem.trim(u8, proc.stdout, &std.ascii.whitespace);
    const hash = try allocator.alloc(u8, trimmed.len);
    std.mem.copyForwards(u8, hash, trimmed);
    allocator.free(proc.stdout);
    return hash;
}

pub fn build(b: *std.Build) !void {
    const target = b.standardTargetOptions(.{});
    const optimize = b.standardOptimizeOption(.{});

    const version_config = .{ .version = "0.1.0" };

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

    const version_str = version_config.version;
    const raw_hash = try getGitHash(b.allocator);
    defer b.allocator.free(raw_hash);
    const hash = std.mem.trim(u8, raw_hash, &std.ascii.whitespace);
    var content = std.ArrayList(u8).init(b.allocator);
    defer content.deinit();
    try content.appendSlice("pub const version = \"");
    try content.appendSlice(version_str);
    try content.appendSlice("\";\n");
    try content.appendSlice("pub const commit_hash = \"");
    try content.appendSlice(hash);
    try content.appendSlice("\";\n");
    const write_files = b.addWriteFiles();
    const version_src = write_files.add("version.zig", content.items);
    const version_module = b.createModule(.{ .root_source_file = version_src });
    exe.root_module.addImport("version", version_module);

    b.installArtifact(exe);

    const run_cmd = b.addRunArtifact(exe);
    run_cmd.step.dependOn(b.getInstallStep());
    if (b.args) |args| {
        run_cmd.addArgs(args);
    }
    const run_step = b.step("run", "Run the app");
    run_step.dependOn(&run_cmd.step);
}
