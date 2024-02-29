const std = @import("std");

pub const zmpl = @import("zmpl").zmpl;

pub const http = @import("jetzig/http.zig");
pub const loggers = @import("jetzig/loggers.zig");
pub const data = @import("jetzig/data.zig");
pub const caches = @import("jetzig/caches.zig");
pub const views = @import("jetzig/views.zig");
pub const colors = @import("jetzig/colors.zig");

/// The primary interface for a Jetzig application. Create an `App` in your application's
/// `src/main.zig` and call `start` to launch the application.
pub const App = @import("jetzig/App.zig");

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

pub const config = struct {
    pub const max_bytes_request_body: usize = std.math.pow(usize, 2, 16);
    pub const max_bytes_static_content: usize = std.math.pow(usize, 2, 16);
    pub const http_buffer_size: usize = std.math.pow(usize, 2, 16);
    pub const public_content = .{ .path = "public" };
};

pub fn init(allocator: std.mem.Allocator) !App {
    const args = try std.process.argsAlloc(allocator);
    defer std.process.argsFree(allocator, args);

    const host: []const u8 = if (args.len > 1)
        try allocator.dupe(u8, args[1])
    else
        try allocator.dupe(u8, "127.0.0.1");

    // TODO: Fix this up with proper arg parsing
    const port: u16 = if (args.len > 2) try std.fmt.parseInt(u16, args[2], 10) else 8080;
    const use_cache: bool = args.len > 3 and std.mem.eql(u8, args[3], "--cache");
    const server_cache = switch (use_cache) {
        true => caches.Cache{ .memory_cache = caches.MemoryCache.init(allocator) },
        false => caches.Cache{ .null_cache = caches.NullCache.init(allocator) },
    };
    const root_path = std.fs.cwd().realpathAlloc(allocator, "src/app") catch |err| {
        switch (err) {
            error.FileNotFound => {
                std.debug.print("Unable to find base directory: ./app\nExiting.\n", .{});
                std.os.exit(1);
            },
            else => return err,
        }
    };

    var logger = loggers.Logger{ .development_logger = loggers.DevelopmentLogger.init(allocator) };
    const secret = try generateSecret(allocator);
    logger.debug(
        "Running in development mode, using auto-generated cookie encryption key:\n  {s}",
        .{secret},
    );

    const server_options = http.Server.ServerOptions{
        .cache = server_cache,
        .logger = logger,
        .root_path = root_path,
        .secret = secret,
    };

    return .{
        .server_options = server_options,
        .allocator = allocator,
        .host = host,
        .port = port,
        .root_path = root_path,
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

        detected[index] = .{
            .name = dynamic_route.name,
            .action = @field(views.Route.Action, dynamic_route.action),
            .view = view,
            .static = false,
            .uri_path = dynamic_route.uri_path,
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

        detected[index] = .{
            .name = static_route.name,
            .action = @field(views.Route.Action, static_route.action),
            .view = view,
            .static = true,
            .uri_path = static_route.uri_path,
            .template = static_route.template,
            .json_params = &static_params,
        };
        index += 1;
    }

    return &detected;
}

// Receives a type (an imported module). All pub const declarations are considered as compiled
// Zmpl templates, each implementing a `render` function.
pub fn loadTemplates(comptime module: type) []TemplateFn {
    var size: u16 = 0;
    const decls = @typeInfo(module).Struct.decls;

    for (decls) |_| size += 1;

    var detected: [size]TemplateFn = undefined;

    for (decls, 0..) |decl, decl_index| {
        detected[decl_index] = .{
            .render = @field(module, decl.name).render,
            .name = decl.name,
        };
    }

    return &detected;
}

pub const TemplateFn = struct {
    name: []const u8,
    render: *const fn (*zmpl.Data) anyerror![]const u8,
};

pub fn generateSecret(allocator: std.mem.Allocator) ![]const u8 {
    const chars = "abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789";
    var secret: [64]u8 = undefined;

    for (0..64) |index| {
        secret[index] = chars[std.crypto.random.intRangeAtMost(u8, 0, chars.len)];
    }

    return try allocator.dupe(u8, &secret);
}

pub fn base64Encode(allocator: std.mem.Allocator, string: []const u8) ![]const u8 {
    const encoder = std.base64.Base64Encoder.init(
        std.base64.url_safe_no_pad.alphabet_chars,
        std.base64.url_safe_no_pad.pad_char,
    );
    const size = encoder.calcSize(string.len);
    const ptr = try allocator.alloc(u8, size);
    _ = encoder.encode(ptr, string);
    return ptr;
}

pub fn base64Decode(allocator: std.mem.Allocator, string: []const u8) ![]const u8 {
    const decoder = std.base64.Base64Decoder.init(
        std.base64.url_safe_no_pad.alphabet_chars,
        std.base64.url_safe_no_pad.pad_char,
    );
    const size = try decoder.calcSizeForSlice(string);
    const ptr = try allocator.alloc(u8, size);
    try decoder.decode(ptr, string);
    return ptr;
}

test {
    @import("std").testing.refAllDecls(@This());
}
