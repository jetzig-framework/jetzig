const std = @import("std");
const jetzig = @import("../../jetzig.zig");

const server_options = jetzig.http.Server.jetzig_server_options;

const middlewares: []const type = if (@hasDecl(server_options, "middleware"))
    server_options.middleware
else
    &.{};

const MiddlewareData = std.BoundedArray(*anyopaque, middlewares.len);

pub fn beforeMiddleware(request: *jetzig.http.Request) !MiddlewareData {
    var middleware_data = MiddlewareData.init(0) catch unreachable;

    inline for (middlewares, 0..) |middleware, index| {
        if (comptime !@hasDecl(middleware, "init")) continue;
        const data = try @call(.always_inline, middleware.init, .{request});
        // We cannot overflow here because we know the length of the array
        middleware_data.insert(index, data) catch unreachable;
    }

    inline for (middlewares, 0..) |middleware, index| {
        if (comptime !@hasDecl(middleware, "beforeRequest")) continue;
        if (comptime @hasDecl(middleware, "init")) {
            const data = middleware_data.get(index);
            try @call(
                .always_inline,
                middleware.beforeRequest,
                .{ @as(*middleware, @ptrCast(@alignCast(data))), request },
            );
        } else {
            try @call(.always_inline, middleware.beforeRequest, .{request});
        }
    }

    return middleware_data;
}

pub fn afterMiddleware(
    middleware_data: *MiddlewareData,
    request: *jetzig.http.Request,
) !void {
    inline for (middlewares, 0..) |middleware, index| {
        if (comptime !@hasDecl(middleware, "afterRequest")) continue;
        if (comptime @hasDecl(middleware, "init")) {
            const data = middleware_data.get(index);
            try @call(
                .always_inline,
                middleware.afterRequest,
                .{ @as(*middleware, @ptrCast(@alignCast(data))), request, request.response },
            );
        } else {
            try @call(.always_inline, middleware.afterRequest, .{ request, request.response });
        }
    }
}

pub fn deinit(middleware_data: *MiddlewareData, request: *jetzig.http.Request) void {
    inline for (middlewares, 0..) |middleware, index| {
        if (comptime @hasDecl(middleware, "init")) {
            if (comptime @hasDecl(middleware, "deinit")) {
                const data = middleware_data.get(index);
                @call(
                    .always_inline,
                    middleware.deinit,
                    .{ @as(*middleware, @ptrCast(@alignCast(data))), request },
                );
            }
        }
    }
}
