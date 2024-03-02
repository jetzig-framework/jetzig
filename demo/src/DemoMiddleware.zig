const std = @import("std");
const jetzig = @import("jetzig");

my_data: u8,

const Self = @This();

pub fn init(request: *jetzig.http.Request) !*Self {
    var middleware = try request.allocator.create(Self);
    middleware.my_data = 42;
    return middleware;
}

pub fn beforeRequest(self: *Self, request: *jetzig.http.Request) !void {
    request.server.logger.debug("[DemoMiddleware] Before request, custom data: {d}", .{self.my_data});
    self.my_data = 43;
}

pub fn afterRequest(self: *Self, request: *jetzig.http.Request, response: *jetzig.http.Response) !void {
    request.server.logger.debug("[DemoMiddleware] After request, custom data: {d}", .{self.my_data});
    request.server.logger.debug("[DemoMiddleware] content-type: {s}", .{response.content_type});
}

pub fn deinit(self: *Self, request: *jetzig.http.Request) void {
    request.allocator.destroy(self);
}
