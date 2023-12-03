const std = @import("std");

const root = @import("root");

const Self = @This();

server_options: root.jetzig.http.Server.ServerOptions,
allocator: std.mem.Allocator,
host: []const u8,
port: u16,
root_path: []const u8,

pub fn render(self: *const Self, data: anytype) root.views.View {
    _ = self;
    return .{ .data = data };
}

pub fn deinit(self: Self) void {
    _ = self;
}

pub fn start(self: Self, views: []root.jetzig.views.Route, templates: []root.jetzig.TemplateFn) !void {
    var server = root.jetzig.http.Server.init(
        self.allocator,
        self.host,
        self.port,
        self.server_options,
        views,
        templates,
    );

    defer server.deinit();
    defer self.allocator.free(self.root_path);
    defer self.allocator.free(self.host);

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
