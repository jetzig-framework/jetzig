const std = @import("std");

const httpz = @import("httpz");

const jetzig = @import("../jetzig.zig");

allocator: std.mem.Allocator,
server: httpz.ServerCtx(void, void),

const HttpzServer = @This();

const DispatcherFn = *const fn (*jetzig.Server, *httpz.Request, *httpz.Response) anyerror!void;

pub fn init(allocator: std.mem.Allocator, dispatcherFn: DispatcherFn) !HttpzServer {
    return .{
        .allocator = allocator,
        .dispatcherFn = dispatcherFn,
        .server = try httpz.Server().init(allocator, .{ .port = 8080 }),
    };
}

pub fn deinit(self: *HttpzServer) void {
    self.server.deinit();
}

pub fn configure(self: *HttpzServer, dispatcherFn: DispatcherFn) void {
    // Bypass router.
    self.server.notFound(dispatcherFn);
}

// var server = ;
//
// // set a global dispatch for any routes defined from this point on
// server.dispatcher(mainDispatcher);
//
// // set a dispatcher for this route
// // note the use of "deleteC" the "C" is for Configuration and is used
// // since Zig doesn't have overloading or optional parameters.
// server.router().deleteC("/v1/session", logout, .{.dispatcher = loggedIn})
// ...
//
// fn mainDispatcher(action: httpz.Action(void), req: *httpz.Request, res: *httpz.Response) !void {
//     res.header("cors", "isslow");
//     return action(req, res);
// }
//
// fn loggedIn(action: httpz.Action(void), req: *httpz.Request, res: *httpz.Response) !void {
//     if (req.header("authorization")) |_auth| {
//         // TODO: make sure "auth" is valid!
//         return mainDispatcher(action, req, res);
//     }
//     res.status = 401;
//     res.body = "Not authorized";
// }
//
// fn logout(req: *httpz.Request, res: *httpz.Response) !void {
//     ...
// }
