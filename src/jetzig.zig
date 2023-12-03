const std = @import("std");

pub const zmpl = @import("zmpl");

pub const http = @import("jetzig/http.zig");
pub const loggers = @import("jetzig/loggers.zig");
pub const caches = @import("jetzig/caches.zig");
pub const views = @import("jetzig/views.zig");
pub const colors = @import("jetzig/colors.zig");
pub const App = @import("jetzig/App.zig");
pub const DefaultAllocator = std.heap.GeneralPurposeAllocator(.{});

pub fn init(allocator: std.mem.Allocator) !App {
    const args = try std.process.argsAlloc(allocator);
    defer std.process.argsFree(allocator, args);

    const host: []const u8 = if (args.len > 1)
        try allocator.dupe(u8, args[1])
    else
        try allocator.dupe(u8, "127.0.0.1");

    // TODO: Fix this up with proper arg parsing
    const port: u16 = if (args.len > 2) try std.fmt.parseInt(u16, args[2], 10) else 8080;
    const use_cache: bool = args.len > 3 and std.mem.eql(u8, args[3], "--cache");
    var debug: bool = args.len > 3 and std.mem.eql(u8, args[3], "--debug");
    debug = debug or (args.len > 4 and std.mem.eql(u8, args[4], "--debug"));
    const server_cache = switch (use_cache) {
        true => caches.Cache{ .memory_cache = caches.MemoryCache.init(allocator) },
        false => caches.Cache{ .null_cache = caches.NullCache.init(allocator) },
    };
    const root_path = std.fs.cwd().realpathAlloc(allocator, "src/app") catch |err| {
        switch (err) {
            error.FileNotFound => {
                std.debug.print("Unable to find base directory: ./app\nExiting.\n", .{});
                std.os.exit(1);
            },
            else => return err,
        }
    };

    const logger = loggers.Logger{ .development_logger = loggers.DevelopmentLogger.init(allocator, debug) };
    const server_options = http.Server.ServerOptions{
        .cache = server_cache,
        .logger = logger,
        .root_path = root_path,
    };

    return .{
        .server_options = server_options,
        .allocator = allocator,
        .host = host,
        .port = port,
        .root_path = root_path,
    };
}

// Receives an array of imported modules and detects functions defined on them.
// Each detected function is stored as a Route which can be accessed at runtime to route requests
// to the appropriate View.
pub fn route(comptime modules: anytype) []views.Route {
    var size: u16 = 0;

    for (modules) |module| {
        const decls = @typeInfo(module).Struct.decls;

        for (decls) |_| size += 1;
    }

    var detected: [size]views.Route = undefined;

    for (modules, 1..) |module, module_index| {
        const decls = @typeInfo(module).Struct.decls;

        for (decls, 1..) |decl, decl_index| {
            const view = @unionInit(views.Route.ViewType, decl.name, @field(module, decl.name));

            detected[module_index * decl_index - 1] = .{
                .name = @typeName(module),
                .action = @field(views.Route.Action, decl.name),
                .view = view,
            };
        }
    }

    return &detected;
}

// Receives a type (an imported module). All pub const declarations are considered as compiled
// Zmpl templates, each implementing a `render` function.
pub fn loadTemplates(comptime module: type) []TemplateFn {
    var size: u16 = 0;
    const decls = @typeInfo(module).Struct.decls;

    for (decls) |_| size += 1;

    var detected: [size]TemplateFn = undefined;

    for (decls, 0..) |decl, decl_index| {
        detected[decl_index] = .{
            .render = @field(module, decl.name).render,
            .name = decl.name,
        };
    }

    return &detected;
}

pub const TemplateFn = struct {
    name: []const u8,
    render: *const fn (*zmpl.Data) anyerror![]const u8,
};
