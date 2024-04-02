const std = @import("std");

const args = @import("args");

const jetzig = @import("../jetzig.zig");
const mime_types = @import("mime_types").mime_types; // Generated at build time.

const Self = @This();

server_options: jetzig.http.Server.ServerOptions,
allocator: std.mem.Allocator,

pub fn deinit(self: Self) void {
    _ = self;
}

// Not used yet, but allows us to add new options to `start()` without breaking
// backward-compatibility.
const AppOptions = struct {};

/// Starts an application. `routes` should be `@import("routes").routes`, a generated file
/// automatically created at build time. `templates` should be
/// `@import("src/app/views/zmpl.manifest.zig").templates`, created by Zmpl at compile time.
pub fn start(self: Self, routes_module: type, options: AppOptions) !void {
    _ = options; // See `AppOptions`

    var mime_map = jetzig.http.mime.MimeMap.init(self.allocator);
    defer mime_map.deinit();
    try mime_map.build();

    var routes = std.ArrayList(*jetzig.views.Route).init(self.allocator);

    for (routes_module.routes) |const_route| {
        var route = try self.allocator.create(jetzig.views.Route);
        route.* = .{
            .name = const_route.name,
            .action = const_route.action,
            .view_name = const_route.view_name,
            .uri_path = const_route.uri_path,
            .view = const_route.view,
            .static_view = const_route.static_view,
            .static = const_route.static,
            .render = const_route.render,
            .renderStatic = const_route.renderStatic,
            .layout = const_route.layout,
            .template = const_route.template,
            .json_params = const_route.json_params,
        };

        try route.initParams(self.allocator);
        try routes.append(route);
    }

    defer routes.deinit();
    defer for (routes.items) |route| {
        route.deinitParams();
        self.allocator.destroy(route);
    };

    if (self.server_options.detach) {
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
        self.server_options,
        routes.items,
        &mime_map,
    );
    defer server.deinit();

    server.listen() catch |err| {
        switch (err) {
            error.AddressInUse => {
                try server.logger.ERROR(
                    "Socket unavailable: {s}:{} - unable to start server.\n",
                    .{ self.server_options.bind, self.server_options.port },
                );
                return;
            },
            else => {
                try server.logger.ERROR("Encountered error: {}\nExiting.\n", .{err});
                return err;
            },
        }
    };
}
