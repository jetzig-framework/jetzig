const std = @import("std");

const args = @import("args");

const jetzig = @import("../jetzig.zig");
const mime_types = @import("mime_types").mime_types; // Generated at build time.

const App = @This();

env: jetzig.Environment,
allocator: std.mem.Allocator,
custom_routes: std.ArrayList(jetzig.views.Route),
initHook: ?*const fn (*App) anyerror!void,
server: *jetzig.http.Server = undefined,

pub fn deinit(self: *const App) void {
    @constCast(self).custom_routes.deinit();
}

/// Specify a global value accessible as `request.server.global`.
/// Must specify type by defining `pub const Global` in your app's `src/main.zig`.
const AppOptions = struct {
    global: *anyopaque = undefined,
};

/// Starts an application. `routes` should be `@import("routes").routes`, a generated file
/// automatically created at build time.
pub fn start(self: *const App, routes_module: type, options: AppOptions) !void {
    defer self.env.deinit();

    if (self.initHook) |hook| try hook(@constCast(self));

    var mime_map = jetzig.http.mime.MimeMap.init(self.allocator);
    defer mime_map.deinit();
    try mime_map.build();

    const routes = try createRoutes(self.allocator, if (@hasDecl(routes_module, "routes")) &routes_module.routes else &.{});
    defer {
        for (routes) |var_route| {
            var_route.deinitParams();
            self.allocator.destroy(var_route);
        }
        self.allocator.free(routes);
    }

    defer for (self.custom_routes.items) |custom_route| {
        self.allocator.free(custom_route.template);
    };

    var store = try jetzig.kv.Store.GeneralStore.init(self.allocator, self.env.logger, .general);
    defer store.deinit();

    var job_queue = try jetzig.kv.Store.JobQueueStore.init(self.allocator, self.env.logger, .jobs);
    defer job_queue.deinit();

    var cache = try jetzig.kv.Store.CacheStore.init(self.allocator, self.env.logger, .cache);
    defer cache.deinit();

    var repo = try jetzig.database.repo(self.allocator, self);
    defer repo.deinit();

    var log_thread = try std.Thread.spawn(
        .{ .allocator = self.allocator },
        jetzig.loggers.LogQueue.Reader.publish,
        .{ &self.env.log_queue.reader, jetzig.loggers.LogQueue.Reader.PublishOptions{} },
    );
    defer log_thread.join();

    if (self.env.detach) {
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
        self.env,
        routes,
        self.custom_routes.items,
        if (@hasDecl(routes_module, "jobs")) &routes_module.jobs else &.{},
        if (@hasDecl(routes_module, "jobs")) &routes_module.mailers else &.{},
        &mime_map,
        &store,
        &job_queue,
        &cache,
        &repo,
        options.global,
    );
    @constCast(self).server = &server;

    var mutex = std.Thread.Mutex{};
    var worker_pool = jetzig.jobs.Pool.init(
        self.allocator,
        &job_queue,
        .{
            .logger = server.logger,
            .vars = self.env.vars,
            .environment = self.env.environment,
            .routes = routes,
            .jobs = if (@hasDecl(routes_module, "jobs")) &routes_module.jobs else &.{},
            .mailers = if (@hasDecl(routes_module, "jobs")) &routes_module.mailers else &.{},
            .store = &store,
            .cache = &cache,
            .repo = &repo,
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
                    .{ self.env.bind, self.env.port },
                );
                return;
            },
            else => {
                try server.logger.ERROR("Encountered error at server launch: {}\nExiting.\n", .{err});
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
    const module_name = @typeName(module)["app.views.".len..@typeName(module).len];

    var template: [module_name.len + 1 + member.len]u8 = undefined;
    @memcpy(&template, module_name ++ "/" ++ member);
    std.mem.replaceScalar(u8, &template, '.', '/');

    var view_name: [module_name.len]u8 = undefined;
    @memcpy(&view_name, module_name);
    std.mem.replaceScalar(u8, &view_name, '.', '/');

    const args_fields = std.meta.fields(std.meta.ArgsTuple(@TypeOf(viewFn)));
    const legacy = args_fields.len > 0 and args_fields[args_fields.len - 1].type == *jetzig.Data;

    self.custom_routes.append(.{
        .id = "custom",
        .name = member,
        .action = .custom,
        .method = method,
        .view_name = module_name,
        .uri_path = path,
        .layout = if (@hasDecl(module, "layout")) module.layout else null,
        .view = comptime switch (viewType(path)) {
            .with_id => if (legacy)
                .{ .legacy_with_id = viewFn }
            else
                .{ .with_id = viewFn },
            .without_id => if (legacy)
                .{ .legacy_without_id = viewFn }
            else
                .{ .without_id = viewFn },
            .with_args => if (legacy)
                .{ .legacy_with_args = viewFn }
            else
                .{ .with_args = viewFn },
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
) ![]const *const jetzig.views.Route {
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
            .formats = const_route.formats,
            .before_callbacks = const_route.before_callbacks,
            .after_callbacks = const_route.after_callbacks,
        };

        try var_route.initParams(allocator);
        try routes.append(var_route);
    }

    return try routes.toOwnedSlice();
}
