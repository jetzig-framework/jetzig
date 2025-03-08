const std = @import("std");
const builtin = @import("builtin");

const jetzig = @import("jetzig");
const zmd = @import("zmd");

pub const routes = @import("routes");
pub const static = @import("static");

// Override default settings in `jetzig.config` here:
pub const jetzig_options = struct {
    /// Middleware chain. Add any custom middleware here, or use middleware provided in
    /// `jetzig.middleware` (e.g. `jetzig.middleware.HtmxMiddleware`).
    pub const middleware: []const type = &.{
        // jetzig.middleware.AuthMiddleware,
        // jetzig.middleware.AntiCsrfMiddleware,
        // jetzig.middleware.HtmxMiddleware,
        // jetzig.middleware.CompressionMiddleware,
        // @import("app/middleware/DemoMiddleware.zig"),
    };

    // Maximum bytes to allow in request body.
    pub const max_bytes_request_body: usize = std.math.pow(usize, 2, 16);

    // Maximum filesize for `public/` content.
    pub const max_bytes_public_content: usize = std.math.pow(usize, 2, 20);

    // Maximum filesize for `static/` content (applies only to apps using `jetzig.http.StaticRequest`).
    pub const max_bytes_static_content: usize = std.math.pow(usize, 2, 18);

    // Maximum length of a header name. There is no limit imposed by the HTTP specification but
    // AWS load balancers reference 40 as a limit so we use that as a baseline:
    // https://docs.aws.amazon.com/elasticloadbalancing/latest/APIReference/API_HttpHeaderConditionConfig.html
    // This can be increased if needed.
    pub const max_bytes_header_name: u16 = 40;

    /// Maximum number of `multipart/form-data`-encoded fields to accept per request.
    pub const max_multipart_form_fields: usize = 20;

    // Log message buffer size. Log messages exceeding this size spill to heap with degraded
    // performance. Log messages should aim to fit in the message buffer.
    pub const log_message_buffer_len: usize = 4096;

    // Maximum log pool size. When a log buffer is no longer required it is returned to a pool
    // for recycling. When logging i/o is slow, a high volume of requests will result in this
    // pool growing. When the pool size reaches the maximum value defined here, log events are
    // freed instead of recycled.
    pub const max_log_pool_len: usize = 256;

    // Number of request threads. Defaults to number of detected CPUs.
    pub const thread_count: ?u16 = null;

    // Number of response worker threads.
    pub const worker_count: u16 = 4;

    // Total number of connections managed by worker threads.
    pub const max_connections: u16 = 512;

    // Per-thread stack memory to use before spilling into request arena (possibly with allocations).
    pub const buffer_size: usize = 64 * 1024;

    // The size of each item in the available memory pool used by requests for rendering.
    // Total retained allocation: `worker_count * max_connections`.
    pub const arena_size: usize = 1024 * 1024;

    // Path relative to cwd() to serve public content from. Symlinks are not followed.
    pub const public_content_path = "public";

    // HTTP buffer. Must be large enough to store all headers. This should typically not be modified.
    pub const http_buffer_size: usize = std.math.pow(usize, 2, 16);

    // The number of worker threads to spawn on startup for processing Jobs (NOT the number of
    // HTTP server worker threads).
    pub const job_worker_threads: usize = 4;

    // Duration before looking for more Jobs when the queue is found to be empty, in
    // milliseconds.
    pub const job_worker_sleep_interval_ms: usize = 10;

    /// Database Schema. Set to `@import("Schema")` to load `src/app/database/Schema.zig`.
    pub const Schema = @import("Schema");

    /// HTTP cookie configuration
    pub const cookies: jetzig.http.Cookies.CookieOptions = switch (jetzig.environment) {
        .development, .testing => .{
            .domain = "localhost",
            .path = "/",
        },
        .production => .{
            .same_site = .lax,
            .secure = true,
            .http_only = true,
            .path = "/",
        },
    };

    /// Key-value store options.
    /// Available backends:
    /// * memory: Simple, in-memory hashmap-backed store.
    /// * file: Rudimentary file-backed store.
    /// * valkey: Valkey-backed store with connection pool.
    ///
    /// When using `.file` or `.valkey` backend, you must also set `.file_options` or
    /// `.valkey_options` respectively.
    ///
    /// ## File backend:
    // .backend = .file,
    // .file_options = .{
    //     .path = "/path/to/jetkv-store.db",
    //     .truncate = false, // Set to `true` to clear the store on each server launch.
    //     .address_space_size = jetzig.jetkv.JetKV.FileBackend.addressSpace(4096),
    // },
    //
    // ## Valkey backend
    // .backend = .valkey,
    // .valkey_options = .{
    //     .host = "localhost",
    //     .port = 6379,
    //     .timeout = 1000, // in milliseconds, i.e. 1 second.
    //     .connect = .lazy, // Connect on first use, or `auto` to connect on server startup.
    //     .buffer_size = 8192,
    //     .pool_size = 8,
    // },
    /// Available configuration options for `store`, `job_queue`, and `cache` are identical.
    ///
    /// For production deployment, the `valkey` backend is recommended for all use cases.
    ///
    /// The general-purpose key-value store is exposed as `request.store` in views and is also
    /// available in as `env.store` in all jobs/mailers.
    pub const store: jetzig.kv.Store.Options = .{
        .backend = .memory,
    };

    /// Job queue options. Identical to `store` options, but allows using different
    /// backends (e.g. `.memory` for key-value store, `.file` for jobs queue.
    /// The job queue is managed internally by Jetzig.
    pub const job_queue: jetzig.kv.Store.Options = .{
        .backend = .memory,
    };

    /// Cache options. Identical to `store` options, but allows using different
    /// backends (e.g. `.memory` for key-value store, `.file` for cache.
    pub const cache: jetzig.kv.Store.Options = .{
        .backend = .memory,
    };

    /// SMTP configuration for Jetzig Mail. It is recommended to use a local SMTP relay,
    /// e.g.: https://github.com/juanluisbaptiste/docker-postfix
    ///
    /// Each configuration option can be overridden with environment variables:
    /// `JETZIG_SMTP_PORT`
    /// `JETZIG_SMTP_ENCRYPTION`
    /// `JETZIG_SMTP_HOST`
    /// `JETZIG_SMTP_USERNAME`
    /// `JETZIG_SMTP_PASSWORD`
    // pub const smtp: jetzig.mail.SMTPConfig = .{
    //     .port = 25,
    //     .encryption = .none, // .insecure, .none, .tls, .start_tls
    //     .host = "localhost",
    //     .username = null,
    //     .password = null,
    // };

    /// Force email delivery in development mode (instead of printing email body to logger).
    pub const force_development_email_delivery = false;

    // Set custom fragments for rendering markdown templates. Any values will fall back to
    // defaults provided by Zmd (https://github.com/jetzig-framework/zmd/blob/main/src/zmd/html.zig).
    pub const markdown_fragments = struct {
        pub const root = .{
            "<div class='p-5'>",
            "</div>",
        };
        pub const h1 = .{
            "<h1 class='text-2xl mb-3 text-green font-bold'>",
            "</h1>",
        };
        pub const h2 = .{
            "<h2 class='text-xl mb-3 font-bold'>",
            "</h2>",
        };
        pub const h3 = .{
            "<h3 class='text-lg mb-3 font-bold'>",
            "</h3>",
        };
        pub const paragraph = .{
            "<p class='p-3'>",
            "</p>",
        };
        pub const code = .{
            "<span class='font-mono bg-gray-900 p-2 text-white'>",
            "</span>",
        };

        pub const unordered_list = .{
            "<ul class='list-disc ms-8 leading-8'>",
            "</ul>",
        };

        pub const ordered_list = .{
            "<ul class='list-decimal ms-8 leading-8'>",
            "</ul>",
        };

        pub fn block(allocator: std.mem.Allocator, node: zmd.Node) ![]const u8 {
            return try std.fmt.allocPrint(allocator,
                \\<pre class="w-1/2 font-mono mt-4 ms-3 bg-gray-900 p-2 text-white"><code class="language-{?s}">{s}</code></pre>
            , .{ node.meta, node.content });
        }

        pub fn link(allocator: std.mem.Allocator, node: zmd.Node) ![]const u8 {
            return try std.fmt.allocPrint(allocator,
                \\<a class="underline decoration-sky-500" href="{0s}" title={1s}>{1s}</a>
            , .{ node.href.?, node.title.? });
        }
    };
};

pub fn init(app: *jetzig.App) !void {
    _ = app;
    // Example custom route:
    // app.route(.GET, "/custom/:id/foo/bar", @import("app/views/custom/foo.zig"), .bar);
}

pub fn main() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    const allocator = if (builtin.mode == .Debug) gpa.allocator() else std.heap.c_allocator;
    defer if (builtin.mode == .Debug) std.debug.assert(gpa.deinit() == .ok);

    var app = try jetzig.init(allocator);
    defer app.deinit();

    try app.start(routes, .{});
}
