const std = @import("std");

const jetzig = @import("../jetzig.zig");
const mime_types = @import("mime_types").mime_types; // Generated at build time.

const Self = @This();

server_options: jetzig.http.Server.ServerOptions,
allocator: std.mem.Allocator,
host: []const u8,
port: u16,

pub fn deinit(self: Self) void {
    _ = self;
}

/// Starts an application. `routes` should be `@import("routes").routes`, a generated file
/// automatically created at build time. `templates` should be
/// `@import("src/app/views/zmpl.manifest.zig").templates`, created by Zmpl at compile time.
pub fn start(self: Self, comptime_routes: []jetzig.views.Route) !void {
    var mime_map = jetzig.http.mime.MimeMap.init(self.allocator);
    defer mime_map.deinit();
    try mime_map.build();

    var routes = std.ArrayList(*jetzig.views.Route).init(self.allocator);

    for (comptime_routes) |*comptime_route| {
        var route = try self.allocator.create(jetzig.views.Route);
        route.* = jetzig.views.Route{
            .name = comptime_route.name,
            .action = comptime_route.action,
            .uri_path = comptime_route.uri_path,
            .view = comptime_route.view,
            .static_view = comptime_route.static_view,
            .static = comptime_route.static,
            .render = comptime_route.render,
            .renderStatic = comptime_route.renderStatic,
            .layout = comptime_route.layout,
            .template = comptime_route.template,
            .json_params = comptime_route.json_params,
        };
        try route.initParams(self.allocator);
        try routes.append(route);
    }
    defer routes.deinit();
    defer for (routes.items) |route| {
        route.deinitParams();
        self.allocator.destroy(route);
    };

    var server = jetzig.http.Server.init(
        self.allocator,
        self.host,
        self.port,
        self.server_options,
        routes.items,
        &mime_map,
    );

    defer server.deinit();
    defer self.allocator.free(self.host);
    defer self.allocator.free(server.options.secret);

    server.listen() catch |err| {
        switch (err) {
            error.AddressInUse => {
                server.logger.debug(
                    "Socket unavailable: {s}:{} - unable to start server.\n",
                    .{ self.host, self.port },
                );
                return;
            },
            else => {
                server.logger.debug("Encountered error: {}\nExiting.\n", .{err});
                return err;
            },
        }
    };
}
