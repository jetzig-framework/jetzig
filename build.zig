const std = @import("std");

pub fn build(b: *std.Build) !void {
    const target = b.standardTargetOptions(.{});
    const optimize = b.standardOptimizeOption(.{});
    const template_path = b.option([]const u8, "zmpl_templates_path", "Path to templates") orelse "src/app/views/";
    const manifest: []const u8 = b.pathJoin(&.{ template_path, "zmpl.manifest.zig" });

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

    const jetzig_module = b.addModule("jetzig", .{ .root_source_file = .{ .path = "src/jetzig.zig" } });
    exe.root_module.addImport("jetzig", jetzig_module);
    lib.root_module.addImport("jetzig", jetzig_module);

    const zmpl_dep = b.dependency(
        "zmpl",
        .{ .target = target, .optimize = optimize, .zmpl_templates_path = template_path, .zmpl_manifest_path = manifest },
    );

    lib.root_module.addImport("zmpl", zmpl_dep.module("zmpl"));
    exe.root_module.addImport("zmpl", zmpl_dep.module("zmpl"));
    jetzig_module.addImport("zmpl", zmpl_dep.module("zmpl"));

    // This is the way to make it look nice in the zig build script
    // If we would do it the other way around, we would have to do b.dependency("jetzig",.{}).builder.dependency("zmpl",.{}).module("zmpl");
    b.modules.put("zmpl", zmpl_dep.module("zmpl")) catch @panic("Out of memory");

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

    main_tests.root_module.addImport("zmpl", zmpl_dep.module("zmpl"));
    const run_main_tests = b.addRunArtifact(main_tests);

    const test_step = b.step("test", "Run library tests");
    test_step.dependOn(&run_main_tests.step);
}

const ViewItem = struct {
    path: []const u8,
    name: []const u8,
};

pub const CompileViewsStepOptions = struct {
    template_path: []const u8 = "src/app/views/",
    max_rss: usize = 0,
};
pub const CompileViewsStep = struct {
    step: std.Build.Step,
    template_path: []const u8,

    fn make(step: *std.Build.Step, prog_node: *std.Progress.Node) !void {
        const self = @fieldParentPtr(CompileViewsStep, "step", step);
        try compileViews(step.owner, self.template_path);
        prog_node.completeOne();
    }

    pub fn create(owner: *std.Build, options: CompileViewsStepOptions) *CompileViewsStep {
        const step = std.Build.Step.init(.{
            .id = std.Build.Step.Id.custom,
            .name = "Compile views",
            .owner = owner,
            .max_rss = options.max_rss,
            .makeFn = &make,
        });
        const compile_step_view = owner.allocator.create(CompileViewsStep) catch @panic("Out of memory");
        compile_step_view.* = .{
            .step = step,
            .template_path = options.template_path,
        };
        return compile_step_view;
    }

    fn findViews(allocator: std.mem.Allocator, template_path: []const u8) !std.ArrayList(*ViewItem) {
        var array = std.ArrayList(*ViewItem).init(allocator);
        const dir = try std.fs.cwd().openDir(template_path, .{ .iterate = true });
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

    fn compileViews(b: *std.Build, template_path: []const u8) !void {
        var dir = b.build_root.handle;
        var views_dir = try dir.makeOpenPath(template_path, .{});
        var file = try views_dir.createFile("routes.zig", .{ .truncate = true });
        try file.writeAll("pub const routes = .{\n");
        const views = try findViews(b.allocator, template_path);
        for (views.items) |view| {
            try file.writeAll(try std.fmt.allocPrint(b.allocator, "  @import(\"{s}\"),\n", .{view.path}));
            std.debug.print("[jetzig] Imported view: {s}\n", .{view.path});
        }

        try file.writeAll("};\n");
        file.close();
    }
};
