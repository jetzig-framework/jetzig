const std = @import("std");

pub const zmpl = @import("zmpl").zmpl;
pub const zmd = @import("zmd").zmd;

pub const http = @import("jetzig/http.zig");
pub const loggers = @import("jetzig/loggers.zig");
pub const data = @import("jetzig/data.zig");
pub const views = @import("jetzig/views.zig");
pub const colors = @import("jetzig/colors.zig");
pub const middleware = @import("jetzig/middleware.zig");
pub const util = @import("jetzig/util.zig");
pub const types = @import("jetzig/types.zig");
pub const markdown = @import("jetzig/markdown.zig");

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

    /// A struct of fragments to use when rendering Markdown templates.
    pub const markdown_fragments = zmd.html.DefaultFragments;

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
