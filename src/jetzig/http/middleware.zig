const std = @import("std");
const jetzig = @import("../../jetzig.zig");

const middlewares: []const type = jetzig.config.get([]const type, "middleware");

const MiddlewareData = std.BoundedArray(?*anyopaque, middlewares.len);

pub fn afterRequest(request: *jetzig.http.Request) !MiddlewareData {
    var middleware_data = MiddlewareData.init(0) catch unreachable;

    inline for (middlewares, 0..) |middleware, index| {
        if (comptime !@hasDecl(middleware, "init")) {
            try middleware_data.insert(index, null);
        } else {
            const data = try @call(.always_inline, middleware.init, .{request});
            try middleware_data.insert(index, data);
        }
    }

    inline for (middlewares, 0..) |middleware, index| {
        if (comptime !@hasDecl(middleware, "afterRequest")) continue;
        if (comptime @hasDecl(middleware, "init")) {
            const data = middleware_data.get(index).?;
            try @call(
                .always_inline,
                middleware.afterRequest,
                .{ @as(*middleware, @ptrCast(@alignCast(data))), request },
            );
        } else {
            try @call(.always_inline, middleware.afterRequest, .{request});
        }
        if (request.rendered or request.redirected) {
            request.middleware_rendered = .{ .name = @typeName(middleware), .action = "afterRequest" };
            break;
        }
    }

    return middleware_data;
}

pub fn beforeResponse(
    middleware_data: *MiddlewareData,
    request: *jetzig.http.Request,
) !void {
    request.response_started = true;

    inline for (middlewares, 0..) |middleware, index| {
        if (comptime !@hasDecl(middleware, "beforeResponse")) continue;
        if (!request.middleware_rendered_during_response) {
            if (comptime @hasDecl(middleware, "init")) {
                const data = middleware_data.get(index).?;
                try @call(
                    .always_inline,
                    middleware.beforeResponse,
                    .{ @as(*middleware, @ptrCast(@alignCast(data))), request, request.response },
                );
            } else {
                try @call(.always_inline, middleware.beforeResponse, .{ request, request.response });
            }
        }
        if (request.middleware_rendered_during_response) {
            request.middleware_rendered = .{ .name = @typeName(middleware), .action = "beforeResponse" };
            break;
        }
    }
}

pub fn afterResponse(
    middleware_data: *MiddlewareData,
    request: *jetzig.http.Request,
) !void {
    inline for (middlewares, 0..) |middleware, index| {
        if (comptime !@hasDecl(middleware, "afterResponse")) continue;
        if (comptime @hasDecl(middleware, "init")) {
            const data = middleware_data.get(index).?;
            try @call(
                .always_inline,
                middleware.afterResponse,
                .{ @as(*middleware, @ptrCast(@alignCast(data))), request, request.response },
            );
        } else {
            try @call(.always_inline, middleware.afterResponse, .{ request, request.response });
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
