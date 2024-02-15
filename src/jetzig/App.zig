const std = @import("std");

const jetzig = @import("../jetzig.zig");

const Self = @This();

server_options: jetzig.http.Server.ServerOptions,
allocator: std.mem.Allocator,
host: []const u8,
port: u16,
root_path: []const u8,

pub fn deinit(self: Self) void {
    _ = self;
}

pub fn start(self: Self, routes: []jetzig.views.Route, templates: []jetzig.TemplateFn) !void {
    var server = jetzig.http.Server.init(
        self.allocator,
        self.host,
        self.port,
        self.server_options,
        routes,
        templates,
    );

    for (routes) |*route| {
        var mutable = @constCast(route); // FIXME
        try mutable.initParams(self.allocator);
    }
    defer for (routes) |*route| {
        var mutable = @constCast(route); // FIXME
        mutable.deinitParams();
    };

    defer server.deinit();
    defer self.allocator.free(self.root_path);
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
