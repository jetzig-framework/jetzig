const std = @import("std");
const jetzig = @import("../../jetzig.zig");

pub const middlewares: []const type = jetzig.config.get([]const type, "middleware");
pub const MiddlewareData = std.BoundedArray(?*anyopaque, middlewares.len);
pub const Enum = MiddlewareEnum();

fn MiddlewareEnum() type {
    comptime {
        var size: usize = 0;
        for (middlewares) |middleware_type| {
            if (@hasDecl(middleware_type, "middleware_name")) size += 1;
        }
        var fields: [size]std.builtin.Type.EnumField = undefined;
        var index: usize = 0;
        for (middlewares) |middleware_type| {
            if (@hasDecl(middleware_type, "middleware_name")) {
                fields[index] = .{ .name = middleware_type.middleware_name, .value = index };
                index += 1;
            }
        }
        return @Type(.{
            .@"enum" = .{
                .tag_type = std.math.IntFittingRange(0, if (size == 0) 0 else size - 1),
                .fields = &fields,
                .decls = &.{},
                .is_exhaustive = true,
            },
        });
    }
}

pub fn Type(comptime name: MiddlewareEnum()) type {
    comptime {
        for (middlewares) |middleware_type| {
            if (@hasDecl(
                middleware_type,
                "middleware_name",
            ) and std.mem.eql(
                u8,
                middleware_type.middleware_name,
                @tagName(name),
            )) {
                return middleware_type;
            }
        }
        unreachable;
    }
}

pub fn afterLaunch(server: *jetzig.http.Server) !void {
    inline for (middlewares) |middleware| {
        if (comptime @hasDecl(middleware, "afterLaunch")) {
            try middleware.afterLaunch(server);
        }
    }
}

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

    request.state = .after_request;

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

        if (request.state != .after_request) {
            request.middleware_rendered = .{ .name = @typeName(middleware), .action = "afterRequest" };
            break;
        }
    }

    request.middleware_data = middleware_data;
    return middleware_data;
}

pub fn beforeResponse(
    middleware_data: *MiddlewareData,
    request: *jetzig.http.Request,
) !void {
    request.state = .before_response;

    inline for (middlewares, 0..) |middleware, index| {
        if (comptime !@hasDecl(middleware, "beforeResponse")) continue;
        if (request.state == .before_response) {
            if (comptime @hasDecl(middleware, "init")) {
                const data = middleware_data.get(index).?;
                try @call(
                    .always_inline,
                    middleware.beforeResponse,
                    .{ @as(*middleware, @ptrCast(@alignCast(data))), request, request.response },
                );
            } else {
                try @call(
                    .always_inline,
                    middleware.beforeResponse,
                    .{ request, request.response },
                );
            }
        }

        if (request.state != .before_response) {
            request.middleware_rendered = .{
                .name = @typeName(middleware),
                .action = "beforeResponse",
            };
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
