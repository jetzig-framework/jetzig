const std = @import("std");

pub const zmpl = @import("zmpl").zmpl;

pub const http = @import("jetzig/http.zig");
pub const loggers = @import("jetzig/loggers.zig");
pub const data = @import("jetzig/data.zig");
pub const views = @import("jetzig/views.zig");
pub const colors = @import("jetzig/colors.zig");
pub const middleware = @import("jetzig/middleware.zig");
pub const util = @import("jetzig/util.zig");
pub const types = @import("jetzig/types.zig");

/// The primary interface for a Jetzig application. Create an `App` in your application's
/// `src/main.zig` and call `start` to launch the application.
pub const App = @import("jetzig/App.zig");

/// Configuration options for the application server with command-line argument parsing.
pub const Environment = @import("jetzig/Environment.zig");

/// An HTTP request which is passed to (dynamic) view functions and provides access to params,
/// headers, and functions to render a response.
pub const Request = http.Request;

/// A build-time request. Provides a similar interface to a `Request` but outputs are generated
/// when building the application and then returned immediately to the client for matching
/// requests.
pub const StaticRequest = http.StaticRequest;

/// Generic, JSON-compatible data type. Provides `Value` which in turn provides `Object`,
/// `Array`, `String`, `Integer`, `Float`, `Boolean`, and `NullType`.
pub const Data = data.Data;

/// The return value of all view functions. Call `request.render(.ok)` in a view function to
/// generate a `View`.
pub const View = views.View;

const root = @import("root");

/// Global configuration. Override these values by defining in `src/main.zig` with:
/// ```zig
/// pub const jetzig_options = struct {
///    // ...
/// }
/// ```
/// All constants defined below can be overridden.
pub const config = struct {
    /// Maximum bytes to allow in request body.
    pub const max_bytes_request_body: usize = std.math.pow(usize, 2, 16);

    /// Maximum filesize for `public/` content.
    pub const max_bytes_public_content: usize = std.math.pow(usize, 2, 20);

    /// Maximum filesize for `static/` content (applies only to apps using `jetzig.http.StaticRequest`).
    pub const max_bytes_static_content: usize = std.math.pow(usize, 2, 18);

    /// Path relative to cwd() to serve public content from. Symlinks are not followed.
    pub const public_content_path = "public";

    /// Middleware chain. Add any custom middleware here, or use middleware provided in
    /// `jetzig.middleware` (e.g. `jetzig.middleware.HtmxMiddleware`).
    pub const middleware = &.{};

    /// HTTP buffer. Must be large enough to store all headers. This should typically not be
    /// modified.
    pub const http_buffer_size: usize = std.math.pow(usize, 2, 16);

    /// Reconciles a configuration value from user-defined values and defaults provided by Jetzig.
    pub fn get(T: type, comptime key: []const u8) T {
        const self = @This();
        if (!@hasDecl(self, key)) @panic("Unknown config option: " ++ key);

        if (@hasDecl(root, "jetzig_options") and @hasDecl(root.jetzig_options, key)) {
            return @field(root.jetzig_options, key);
        } else {
            return @field(self, key);
        }
    }
};

/// Initialize a new Jetzig app. Call this from `src/main.zig` and then call
/// `start(@import("routes").routes)` on the returned value.
pub fn init(allocator: std.mem.Allocator) !App {
    const args = try std.process.argsAlloc(allocator);
    defer std.process.argsFree(allocator, args);

    const environment = Environment.init(allocator);

    return .{
        .server_options = try environment.getServerOptions(),
        .allocator = allocator,
    };
}

// Receives an array of imported modules and detects functions defined on them.
// Each detected function is stored as a Route which can be accessed at runtime to route requests
// to the appropriate View.
pub fn route(comptime routes: anytype) []views.Route {
    var size: usize = 0;

    for (routes.dynamic) |_| {
        size += 1;
    }

    for (routes.static) |_| {
        size += 1;
    }

    var detected: [size]views.Route = undefined;
    var index: usize = 0;

    for (routes.dynamic) |dynamic_route| {
        const view = views.Route.ViewType{
            .dynamic = @unionInit(
                views.Route.DynamicViewType,
                dynamic_route.action,
                dynamic_route.function,
            ),
        };

        const layout: ?[]const u8 = if (@hasDecl(dynamic_route.module, "layout"))
            dynamic_route.module.layout
        else
            null;

        detected[index] = .{
            .name = dynamic_route.name,
            .action = @field(views.Route.Action, dynamic_route.action),
            .view = view,
            .static = false,
            .uri_path = dynamic_route.uri_path,
            .layout = layout,
            .template = dynamic_route.template,
            .json_params = &.{},
        };
        index += 1;
    }

    for (routes.static) |static_route| {
        const view = views.Route.ViewType{
            .static = @unionInit(
                views.Route.StaticViewType,
                static_route.action,
                static_route.function,
            ),
        };

        comptime var params_size = 0;
        inline for (static_route.params) |_| params_size += 1;
        comptime var static_params: [params_size][]const u8 = undefined;
        inline for (static_route.params, 0..) |json, params_index| static_params[params_index] = json;

        const layout: ?[]const u8 = if (@hasDecl(static_route.module, "layout"))
            static_route.module.layout
        else
            null;

        detected[index] = .{
            .name = static_route.name,
            .action = @field(views.Route.Action, static_route.action),
            .view = view,
            .static = true,
            .uri_path = static_route.uri_path,
            .layout = layout,
            .template = static_route.template,
            .json_params = &static_params,
        };
        index += 1;
    }

    return &detected;
}
