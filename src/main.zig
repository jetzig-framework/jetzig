const std = @import("std");

pub const jetzig = @import("jetzig.zig");
pub const templates = @import("app/views/zmpl.manifest.zig").templates;
pub const routes = @import("app/views/routes.zig").routes;

pub const jetzig_options = struct {
    pub const middleware: []const type = &.{ TestMiddleware, IncompleteMiddleware, IncompleteMiddleware2 };
};

pub fn main() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer std.debug.assert(gpa.deinit() == .ok);
    const allocator = gpa.allocator();

    const app = try jetzig.init(allocator);
    defer app.deinit();

    try app.start(
        comptime jetzig.route(routes),
        comptime jetzig.loadTemplates(templates),
    );
}

const TestMiddleware = struct {
    my_data: u8,
    pub fn init(request: *jetzig.http.Request) !*TestMiddleware {
        var mw = try request.allocator.create(TestMiddleware);
        mw.my_data = 42;
        return mw;
    }

    pub fn beforeRequest(middleware: *TestMiddleware, request: *jetzig.http.Request) !void {
        request.server.logger.debug("Before request, custom data: {d}", .{middleware.my_data});
        middleware.my_data = 43;
    }

    pub fn afterRequest(middleware: *TestMiddleware, request: *jetzig.http.Request, result: *jetzig.caches.Result) !void {
        request.server.logger.debug("After request, custom data: {d}", .{middleware.my_data});
        request.server.logger.debug("{s}", .{result.value.content_type});
    }

    pub fn deinit(middleware: *TestMiddleware, request: *jetzig.http.Request) void {
        request.allocator.destroy(middleware);
    }
};

const IncompleteMiddleware = struct {
    pub fn beforeRequest(request: *jetzig.http.Request) !void {
        request.server.logger.debug("Before request", .{});
    }
};

const IncompleteMiddleware2 = struct {
    pub fn afterRequest(request: *jetzig.http.Request, result: *jetzig.caches.Result) !void {
        request.server.logger.debug("After request", .{});
        _ = result;
    }
};
