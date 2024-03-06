/// Demo middleware. Assign middleware by declaring `pub const middleware` in the
/// `jetzig_options` defined in your application's `src/main.zig`.
///
/// Middleware is called before and after the request, providing full access to the active
/// request, allowing you to execute any custom code for logging, tracking, inserting response
/// headers, etc.
///
/// This middleware is configured in the demo app's `src/main.zig`:
///
/// ```
/// pub const jetzig_options = struct {
///    pub const middleware: []const type = &.{@import("app/middleware/DemoMiddleware.zig")};
/// };
/// ```
const std = @import("std");
const jetzig = @import("jetzig");

/// Define any custom data fields you want to store here. Assigning to these fields in the `init`
/// function allows you to access them in the `beforeRequest` and `afterRequest` functions, where
/// they can also be modified.
my_custom_value: []const u8,

const Self = @This();

/// Initialize middleware.
pub fn init(request: *jetzig.http.Request) !*Self {
    var middleware = try request.allocator.create(Self);
    middleware.my_custom_value = "initial value";
    return middleware;
}

/// Invoked immediately after the request head has been processed, before relevant view function
/// is processed. This gives you access to request headers but not the request body.
pub fn beforeRequest(self: *Self, request: *jetzig.http.Request) !void {
    request.server.logger.debug("[DemoMiddleware] my_custom_value: {s}", .{self.my_custom_value});
    self.my_custom_value = @tagName(request.method);
}

/// Invoked immediately after the request has finished responding. Provides full access to the
/// response as well as the request.
pub fn afterRequest(self: *Self, request: *jetzig.http.Request, response: *jetzig.http.Response) !void {
    request.server.logger.debug(
        "[DemoMiddleware] my_custom_value: {s}, response status: {s}",
        .{ self.my_custom_value, @tagName(response.status_code) },
    );
}

/// Invoked after `afterRequest` is called, use this function to do any clean-up.
/// Note that `request.allocator` is an arena allocator, so any allocations are automatically
/// done before the next request starts processing.
pub fn deinit(self: *Self, request: *jetzig.http.Request) void {
    request.allocator.destroy(self);
}
