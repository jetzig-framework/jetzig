const std = @import("std");

pub const zmpl = @import("zmpl").zmpl;
pub const zmd = @import("zmd").zmd;
pub const jetkv = @import("jetkv").jetkv;

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
pub const kv = @import("jetzig/kv.zig");
pub const testing = @import("jetzig/testing.zig");

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

/// A middleware route definition. Allows middleware to define custom routes in order to serve
/// content.
pub const MiddlewareRoute = middleware.MiddlewareRoute;

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

pub const root = @import("root");

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

    /// Maximum length of a header name. There is no limit imposed by the HTTP specification but
    /// AWS load balancers reference 40 as a limit so we use that as a baseline:
    /// https://docs.aws.amazon.com/elasticloadbalancing/latest/APIReference/API_HttpHeaderConditionConfig.html
    /// This can be increased if needed.
    pub const max_bytes_header_name: u16 = 40;

    /// Maximum number of `multipart/form-data`-encoded fields to accept per request.
    pub const max_multipart_form_fields: usize = 20;

    /// Log message buffer size. Log messages exceeding this size spill to heap with degraded
    /// performance. Log messages should aim to fit in the message buffer.
    pub const log_message_buffer_len: usize = 4096;

    /// Maximum log pool size. When a log buffer is no longer required it is returned to a pool
    /// for recycling. When logging i/o is slow, a high volume of requests will result in this
    /// pool growing. When the pool size reaches the maximum value defined here, log events are
    /// freed instead of recycled.
    pub const max_log_pool_len: usize = 256;

    /// Number of request threads. Defaults to number of detected CPUs.
    pub const thread_count: ?u16 = null;

    /// Per-thread stack memory to use before spilling into request arena (possibly with allocations).
    pub const buffer_size: usize = 64 * 1024;

    /// The pre-heated size of each item in the available memory pool used by requests for
    /// rendering. Total retained allocation: `worker_count * max_connections`. Requests
    /// requiring more memory will allocate per-request, leaving `arena_size` bytes pre-allocated
    /// for the next request.
    pub const arena_size: usize = 1024 * 1024;

    /// Number of response worker threads.
    pub const worker_count: u16 = 4;

    /// Total number of connections managed by worker threads.
    pub const max_connections: u16 = 512;

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

    /// Key-value store options. Set backend to `.file` to use a file-based store.
    /// When using `.file` backend, you must also set `.file_options`.
    /// The key-value store is exposed as `request.store` in views and is also available in as
    /// `env.store` in all jobs/mailers.
    pub const store: kv.Store.KVOptions = .{
        .backend = .memory,
        // .backend = .file,
        // .file_options = .{
        //     .path = "/path/to/jetkv-store.db",
        //     .truncate = false, // Set to `true` to clear the store on each server launch.
        //     .address_space_size = jetzig.jetkv.JetKV.FileBackend.addressSpace(4096),
        // },
    };

    /// Job queue options. Identical to `store` options, but allows using different
    /// backends (e.g. `.memory` for key-value store, `.file` for jobs queue.
    /// The job queue is managed internally by Jetzig.
    pub const job_queue: kv.Store.KVOptions = .{
        .backend = .memory,
        // .backend = .file,
        // .file_options = .{
        //     .path = "/path/to/jetkv-queue.db",
        //     .truncate = false, // Set to `true` to clear the store on each server launch.
        //     .address_space_size = jetzig.jetkv.JetKV.FileBackend.addressSpace(4096),
        // },
    };

    /// Cache. Identical to `store` options, but allows using different
    /// backends (e.g. `.memory` for key-value store, `.file` for cache.
    pub const cache: kv.Store.KVOptions = .{
        .backend = .memory,
        // .backend = .file,
        // .file_options = .{
        //     .path = "/path/to/jetkv-cache.db",
        //     .truncate = false, // Set to `true` to clear the store on each server launch.
        //     .address_space_size = jetzig.jetkv.JetKV.FileBackend.addressSpace(4096),
        // },
    };

    /// SMTP configuration for Jetzig Mail.
    pub const smtp: mail.SMTPConfig = .{
        .port = 25,
        .encryption = .none, // .insecure, .none, .tls, .start_tls
        .host = "localhost",
        .username = null,
        .password = null,
    };

    /// HTTP cookie configuration
    pub const cookie_options: http.Cookies.CookieOptions = .{
        .domain = "localhost",
        .path = "/",
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

pub const initHook: ?*const fn (*App) anyerror!void = if (@hasDecl(root, "init")) root.init else null;

/// Initialize a new Jetzig app. Call this from `src/main.zig` and then call
/// `start(@import("routes").routes)` on the returned value.
pub fn init(allocator: std.mem.Allocator) !App {
    const args = try std.process.argsAlloc(allocator);
    defer std.process.argsFree(allocator, args);

    const environment = Environment.init(allocator);

    return .{
        .environment = environment,
        .allocator = allocator,
        .custom_routes = std.ArrayList(views.Route).init(allocator),
        .initHook = initHook,
    };
}
