const std = @import("std");

pub const zmpl = @import("zmpl").zmpl;
pub const zmd = @import("zmd");
pub const jetkv = @import("jetkv").jetkv;
pub const jetquery = @import("jetquery");

pub const http = @import("http.zig");
pub const loggers = @import("loggers.zig");
pub const data = @import("data.zig");
pub const views = @import("views.zig");
pub const colors = @import("colors.zig");
pub const util = @import("util.zig");
pub const types = @import("types.zig");
pub const markdown = @import("markdown.zig");
pub const jobs = @import("jobs.zig");
pub const mail = @import("mail.zig");
pub const kv = @import("kv.zig");
pub const db = @import("database.zig");
pub const Environment = @import("Environment.zig");
pub const environment = @field(
    Environment.EnvironmentName,
    @tagName(build_options.environment),
);
pub const build_options = @import("build_options");

const root = @import("root");

/// Global configuration. Override these values by defining in `src/main.zig` with:
/// ```zig
/// pub const jetzig_options = struct {
///    // ...
/// }
/// ```
/// All constants defined below can be overridden.
const config = @This();

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

/// Request path to map to public directory, e.g. if `public_routing_path` is `"/foo"` then a
/// request to `/foo/bar.png` will serve static content found in `public/bar.png`
pub const public_routing_path = "/";

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

/// Database Schema. Set to `@import("Schema")` to load `src/app/database/Schema.zig`.
pub const Schema: type = struct {};

/// Key-value store options. Set backend to `.file` to use a file-based store.
/// When using `.file` backend, you must also set `.file_options`.
/// The key-value store is exposed as `request.store` in views and is also available in as
/// `env.store` in all jobs/mailers.
pub const store: kv.Store.Options = .{
    .backend = .memory,
    // .backend = .file,
    // .file_options = .{
    //     .path = "/path/to/jetkv-store.db",
    //     .truncate = false, // Set to `true` to clear the store on each server launch.
    //     .address_space_size = jetzig.jetkv.FileBackend.addressSpace(4096),
    // },
};

/// Job queue options. Identical to `store` options, but allows using different
/// backends (e.g. `.memory` for key-value store, `.file` for jobs queue.
/// The job queue is managed internally by Jetzig.
pub const job_queue: kv.Store.Options = .{
    .backend = .memory,
    // .backend = .file,
    // .file_options = .{
    //     .path = "/path/to/jetkv-queue.db",
    //     .truncate = false, // Set to `true` to clear the store on each server launch.
    //     .address_space_size = jetzig.jetkv.JetKV.addressSpace(4096),
    // },
};

/// Cache. Identical to `store` options, but allows using different
/// backends (e.g. `.memory` for key-value store, `.file` for cache.
pub const cache: kv.Store.Options = .{
    .backend = .memory,
    // .backend = .file,
    // .file_options = .{
    //     .path = "/path/to/jetkv-cache.db",
    //     .truncate = false, // Set to `true` to clear the store on each server launch.
    //     .address_space_size = jetzig.jetkv.JetKV.addressSpace(4096),
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
pub const cookies: http.Cookies.Cookie.Options = switch (environment) {
    .development, .testing => .{
        .domain = "localhost",
        .path = "/",
    },
    .production => .{
        .secure = true,
        .httponly = true,
        .samesite = .lax,
        .path = "/",
    },
};

/// Override the default anti-CSRF authenticity token name that is stored in the encrypted
/// session. This value is also used by `context.authenticityFormElement()` to render an HTML
/// element: the element's `name` attribute is set to this value.
pub const authenticity_token_name: []const u8 = "_jetzig_authenticity_token";

/// When using `AuthMiddleware`, set this value to override the default JetQuery model name that
/// maps the users table.
pub const auth: @import("auth.zig").AuthOptions = .{
    .user_model = "User",
};

/// Force email delivery in development mode (instead of printing email body to logger).
pub const force_development_email_delivery = false;

/// Reconciles a configuration value from user-defined values and defaults provided by Jetzig.
pub fn get(comptime T: type, comptime key: []const u8) T {
    const self = @This();
    if (!@hasDecl(self, key)) @compileError("Unknown config option: " ++ key);

    if (@hasDecl(root, "jetzig_options") and @hasDecl(root.jetzig_options, key)) {
        return @field(root.jetzig_options, key);
    } else {
        return @field(self, key);
    }
}
