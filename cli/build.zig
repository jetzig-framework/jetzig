const std = @import("std");
const compile = @import("compile.zig");

const ArrayList = std.ArrayList;
const Allocator = std.mem.Allocator;
const Writer = std.Io.Writer;

fn getGitHash(allocator: Allocator) ![]const u8 {
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

    const zig_args = b.dependency("args", .{
        .target = target,
        .optimize = optimize,
    }).module("args");

    const jetquery = b.dependency("jetquery", .{
        .target = target,
        .optimize = optimize,
        .jetquery_migrations_path = @as([]const u8, "src/app/database/migrations"),
        .jetquery_seeders_path = @as([]const u8, "src/app/database/seeders"),
    }).module("jetquery");

    const exe = b.addExecutable(.{
        .name = "jetzig",
        .root_module = b.createModule(.{
            .root_source_file = b.path("cli.zig"),
            .target = target,
            .optimize = optimize,
            .imports = &.{
                .{ .name = "jetquery", .module = jetquery },
                .{ .name = "args", .module = zig_args },
                .{ .name = "init_data", .module = try compile.initDataModule(b) },
            },
        }),
    });

    const version_config = @import("build.zig.zon");
    const version_str = version_config.version;
    const raw_hash = try getGitHash(b.allocator);
    defer b.allocator.free(raw_hash);
    const hash = std.mem.trim(u8, raw_hash, &std.ascii.whitespace);

    var buf: Writer.Allocating = .init(b.allocator);
    defer buf.deinit();
    try buf.writer.print(
        \\pub const version = "{[version]s}";
        \\pub const commit_hash = "{[hash]s}";
        \\
    , .{
        .version = version_str,
        .hash = hash,
    });
    const content = try buf.toOwnedSlice();
    const write_files = b.addWriteFiles();
    const version_src = write_files.add("version.zig", content);
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
