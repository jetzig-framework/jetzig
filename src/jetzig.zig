const std = @import("std");

pub const zmpl = @import("zmpl").zmpl;
pub const zmd = @import("zmd").zmd;
pub const jetkv = @import("jetkv");

pub const http = @import("jetzig/http.zig");
pub const loggers = @import("jetzig/loggers.zig");
pub const data = @import("jetzig/data.zig");
pub const views = @import("jetzig/views.zig");
pub const colors = @import("jetzig/colors.zig");
pub const middleware = @import("jetzig/middleware.zig");
pub const util = @import("jetzig/util.zig");
pub const types = @import("jetzig/types.zig");
pub const markdown = @import("jetzig/markdown.zig");
pub const jobs = @import("jetzig/jobs.zig");
pub const mail = @import("jetzig/mail.zig");

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

/// A route definition. Generated at build type by `Routes.zig`.
pub const Route = views.Route;

const root = @import("root");

/// An asynchronous job that runs outside of the request/response flow. Create via `Request.job`
/// and set params with `Job.put`, then call `Job.schedule()` to add to the
/// job queue.
pub const Job = jobs.Job;

/// A container for a job definition, includes the job name and run function.
pub const JobDefinition = jobs.Job.JobDefinition;

/// A container for a mailer definition, includes mailer name and mail function.
pub const MailerDefinition = mail.MailerDefinition;

/// A generic logger type. Provides all standard log levels as functions (`INFO`, `WARN`,
/// `ERROR`, etc.). Note that all log functions are CAPITALIZED.
pub const Logger = loggers.Logger;

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

    /// The number of worker threads to spawn on startup for processing Jobs (NOT the number of
    /// HTTP server worker threads).
    pub const job_worker_threads: usize = 1;

    /// Duration before looking for more Jobs when the queue is found to be empty, in
    /// milliseconds.
    pub const job_worker_sleep_interval_ms: usize = 10;

    /// SMTP configuration for Jetzig Mail.
    pub const smtp: mail.SMTPConfig = .{
        .port = 25,
        .encryption = .none, // .insecure, .none, .tls, .start_tls
        .host = "localhost",
        .username = null,
        .password = null,
    };

    /// Force email delivery in development mode (instead of printing email body to logger).
    pub const force_development_email_delivery = false;

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
