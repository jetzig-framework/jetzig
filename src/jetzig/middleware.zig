const std = @import("std");
const jetzig = @import("../jetzig.zig");

pub const HtmxMiddleware = @import("middleware/HtmxMiddleware.zig");
pub const CompressionMiddleware = @import("middleware/CompressionMiddleware.zig");

const RouteOptions = struct {
    content: ?[]const u8 = null,
    content_type: []const u8 = "text/html",
    status: jetzig.http.StatusCode = .ok,
};

pub const MiddlewareRoute = struct {
    method: jetzig.http.Request.Method,
    path: []const u8,
    content: ?[]const u8,
    content_type: []const u8,
    status: jetzig.http.StatusCode,

    pub fn match(self: MiddlewareRoute, request: *const jetzig.http.Request) bool {
        if (self.method != request.method) return false;
        if (!std.mem.eql(u8, self.path, request.path.file_path)) return false;

        return true;
    }
};

pub fn route(method: jetzig.http.Request.Method, path: []const u8, options: RouteOptions) MiddlewareRoute {
    return .{
        .method = method,
        .path = path,
        .content = options.content,
        .content_type = options.content_type,
        .status = options.status,
    };
}
