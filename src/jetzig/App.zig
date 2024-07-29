const std = @import("std");

const args = @import("args");

const jetzig = @import("../jetzig.zig");
const mime_types = @import("mime_types").mime_types; // Generated at build time.

const App = @This();

environment: jetzig.Environment,
allocator: std.mem.Allocator,
custom_routes: std.ArrayList(jetzig.views.Route),
initHook: ?*const fn (*App) anyerror!void,

pub fn deinit(self: *const App) void {
    @constCast(self).custom_routes.deinit();
}

// Not used yet, but allows us to add new options to `start()` without breaking
// backward-compatibility.
pub const AppOptions = struct {
    state: *anyopaque,
};

/// Starts an application. `routes` should be `@import("routes").routes`, a generated file
/// automatically created at build time. `templates` should be
/// `@import("src/app/views/zmpl.manifest.zig").templates`, created by Zmpl at compile time.
pub fn start(self: *const App, routes_module: type, options: AppOptions) !void {
    if (self.initHook) |hook| try hook(@constCast(self));

    var mime_map = jetzig.http.mime.MimeMap.init(self.allocator);
    defer mime_map.deinit();
    try mime_map.build();

    const routes = try createRoutes(self.allocator, &routes_module.routes);
    defer for (routes) |var_route| {
        var_route.deinitParams();
        self.allocator.destroy(var_route);
    };

    defer for (self.custom_routes.items) |custom_route| {
        self.allocator.free(custom_route.view_name);
        self.allocator.free(custom_route.template);
    };

    var store = try jetzig.kv.Store.init(
        self.allocator,
        jetzig.config.get(jetzig.kv.Store.KVOptions, "store"),
    );
    defer store.deinit();

    var job_queue = try jetzig.kv.Store.init(
        self.allocator,
        jetzig.config.get(jetzig.kv.Store.KVOptions, "job_queue"),
    );
    defer job_queue.deinit();

    var cache = try jetzig.kv.Store.init(
        self.allocator,
        jetzig.config.get(jetzig.kv.Store.KVOptions, "cache"),
    );
    defer cache.deinit();

    const server_options = try self.environment.getServerOptions();
    defer self.allocator.free(server_options.bind);
    defer self.allocator.free(server_options.secret);

    var log_thread = try std.Thread.spawn(
        .{ .allocator = self.allocator },
        jetzig.loggers.LogQueue.Reader.publish,
        .{ &server_options.log_queue.reader, .{} },
    );
    defer log_thread.join();

    if (server_options.detach) {
        const argv = try std.process.argsAlloc(self.allocator);
        defer std.process.argsFree(self.allocator, argv);
        var child_argv = std.ArrayList([]const u8).init(self.allocator);
        for (argv) |arg| {
            if (!std.mem.eql(u8, "-d", arg) and !std.mem.eql(u8, "--detach", arg)) {
                try child_argv.append(arg);
            }
        }
        var child = std.process.Child.init(child_argv.items, self.allocator);
        try child.spawn();
        std.debug.print("Spawned child process. PID: {}. Exiting.\n", .{child.id});
        std.process.exit(0);
    }

    var server = jetzig.http.Server.init(
        self.allocator,
        server_options,
        routes,
        self.custom_routes.items,
        &routes_module.jobs,
        &routes_module.mailers,
        &mime_map,
        &store,
        &job_queue,
        &cache,
        options.state,
    );

    var mutex = std.Thread.Mutex{};
    var worker_pool = jetzig.jobs.Pool.init(
        self.allocator,
        &job_queue,
        .{
            .logger = server.logger,
            .environment = server.options.environment,
            .routes = routes,
            .jobs = &routes_module.jobs,
            .mailers = &routes_module.mailers,
            .store = &store,
            .cache = &cache,
            .mutex = &mutex,
        },
    );
    defer worker_pool.deinit();

    try worker_pool.work(
        jetzig.config.get(usize, "job_worker_threads"),
        jetzig.config.get(usize, "job_worker_sleep_interval_ms"),
    );

    server.listen() catch |err| {
        switch (err) {
            error.AddressInUse => {
                try server.logger.ERROR(
                    "Socket unavailable: {s}:{} - unable to start server.\n",
                    .{ server_options.bind, server_options.port },
                );
                return;
            },
            else => {
                try server.logger.ERROR("Encountered error: {}\nExiting.\n", .{err});
                std.process.exit(1);
            },
        }
    };
}

pub fn route(
    self: *App,
    comptime method: jetzig.http.Request.Method,
    comptime path: []const u8,
    comptime module: type,
    comptime action: std.meta.DeclEnum(module),
) void {
    const member = @tagName(action);
    const viewFn = @field(module, member);
    const module_name = comptime std.mem.trimLeft(u8, @typeName(module), "app.views.");

    var template: [module_name.len + 1 + member.len]u8 = undefined;
    @memcpy(&template, module_name ++ "/" ++ member);
    std.mem.replaceScalar(u8, &template, '.', '/');

    var view_name: [module_name.len]u8 = undefined;
    @memcpy(&view_name, module_name);
    std.mem.replaceScalar(u8, &view_name, '.', '/');

    self.custom_routes.append(.{
        .id = "custom",
        .name = member,
        .action = .custom,
        .method = method,
        .view_name = module_name,
        .uri_path = path,
        .layout = if (@hasDecl(module, "layout")) module.layout else null,
        .view = comptime switch (viewType(path)) {
            .with_id => .{ .custom = .{ .with_id = viewFn } },
            .with_args => .{ .custom = .{ .with_args = viewFn } },
            .without_id => .{ .custom = .{ .without_id = viewFn } },
        },
        .template = self.allocator.dupe(u8, &template) catch @panic("OOM"),
        .json_params = &.{},
    }) catch @panic("OOM");
}

inline fn viewType(path: []const u8) enum { with_id, without_id, with_args } {
    var it = std.mem.tokenizeSequence(u8, path, "/");
    while (it.next()) |segment| {
        if (std.mem.startsWith(u8, segment, ":")) {
            if (std.mem.endsWith(u8, segment, "*")) return .with_args;
            return .with_id;
        }
    }

    return .without_id;
}

pub fn createRoutes(
    allocator: std.mem.Allocator,
    comptime_routes: []const jetzig.views.Route,
) ![]*jetzig.views.Route {
    var routes = std.ArrayList(*jetzig.views.Route).init(allocator);

    for (comptime_routes) |const_route| {
        var var_route = try allocator.create(jetzig.views.Route);
        var_route.* = .{
            .id = const_route.id,
            .name = const_route.name,
            .action = const_route.action,
            .view_name = const_route.view_name,
            .uri_path = const_route.uri_path,
            .view = const_route.view,
            .static = const_route.static,
            .layout = const_route.layout,
            .template = const_route.template,
            .json_params = const_route.json_params,
        };

        try var_route.initParams(allocator);
        try routes.append(var_route);
    }

    return try routes.toOwnedSlice();
}
