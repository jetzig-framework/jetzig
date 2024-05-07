const std = @import("std");
const Server = @import("http/Server.zig");
const jetzig = @import("../jetzig.zig");

pub fn listen(self: *Server) !void {
    const address = try std.net.Address.parseIp(self.options.bind, self.options.port);
    self.std_net_server = try address.listen(.{ .reuse_port = true });

    self.initialized = true;

    try self.logger.INFO("Listening on http://{s}:{} [{s}]", .{
        self.options.bind,
        self.options.port,
        @tagName(self.options.environment),
    });
    try processRequests(self);
}

fn processRequests(self: *Server) !void {
    while (true) {
        var arena = std.heap.ArenaAllocator.init(self.allocator);
        errdefer arena.deinit();
        const allocator = arena.allocator();

        const connection = try self.std_net_server.accept();

        var buf: [jetzig.config.get(usize, "http_buffer_size")]u8 = undefined;
        var std_http_server = std.http.Server.init(connection, &buf);
        errdefer std_http_server.connection.stream.close();

        processNextRequest(self, allocator, &std_http_server) catch |err| {
            if (Server.isBadHttpError(err)) {
                std_http_server.connection.stream.close();
                continue;
            } else return err;
        };

        std_http_server.connection.stream.close();
        arena.deinit();
    }
}

fn processNextRequest(self: *Server, allocator: std.mem.Allocator, std_http_server: *std.http.Server) !void {
    const start_time = std.time.nanoTimestamp();

    const std_http_request = try std_http_server.receiveHead();
    if (std_http_server.state == .receiving_head) return error.JetzigParseHeadError;

    var response = try jetzig.http.Response.init(allocator);
    var request = try jetzig.http.Request.init(allocator, self, start_time, std_http_request, &response);

    try request.process();

    var middleware_data = try jetzig.http.middleware.afterRequest(&request);

    try self.renderResponse(&request);
    try request.response.headers.append("content-type", response.content_type);

    try jetzig.http.middleware.beforeResponse(&middleware_data, &request);

    try request.respond();

    try jetzig.http.middleware.afterResponse(&middleware_data, &request);
    jetzig.http.middleware.deinit(&middleware_data, &request);

    try self.logger.logRequest(&request);
}
