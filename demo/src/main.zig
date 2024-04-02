const std = @import("std");

pub const jetzig = @import("jetzig");

pub const routes = @import("routes");

// Override default settings in `jetzig.config` here:
pub const jetzig_options = struct {
    /// Middleware chain. Add any custom middleware here, or use middleware provided in
    /// `jetzig.middleware` (e.g. `jetzig.middleware.HtmxMiddleware`).
    pub const middleware: []const type = &.{
        // htmx middleware skips layouts when `HX-Target` header is present and issues
        // `HX-Redirect` instead of a regular HTTP redirect when `request.redirect` is called.
        jetzig.middleware.HtmxMiddleware,
        // Demo middleware included with new projects. Remove once you are familiar with Jetzig's
        // middleware system.
        @import("app/middleware/DemoMiddleware.zig"),
    };

    // Maximum bytes to allow in request body.
    // pub const max_bytes_request_body: usize = std.math.pow(usize, 2, 16);

    // Maximum filesize for `public/` content.
    // pub const max_bytes_public_content: usize = std.math.pow(usize, 2, 20);

    // Maximum filesize for `static/` content (applies only to apps using `jetzig.http.StaticRequest`).
    // pub const max_bytes_static_content: usize = std.math.pow(usize, 2, 18);

    // Path relative to cwd() to serve public content from. Symlinks are not followed.
    // pub const public_content_path = "public";

    // HTTP buffer. Must be large enough to store all headers. This should typically not be modified.
    // pub const http_buffer_size: usize = std.math.pow(usize, 2, 16);

    // Set custom fragments for rendering markdown templates. Any values will fall back to
    // defaults provided by Zmd (https://github.com/bobf/zmd/blob/main/src/zmd/html.zig).
    pub const markdown_fragments = struct {
        pub const root = .{
            "<div class='p-5'>",
            "</div>",
        };
        pub const h1 = .{
            "<h1 class='text-2xl mb-3 font-bold'>",
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

        pub fn block(allocator: std.mem.Allocator, node: jetzig.zmd.Node) ![]const u8 {
            return try std.fmt.allocPrint(allocator,
                \\<pre class="w-1/2 font-mono mt-4 ms-3 bg-gray-900 p-2 text-white"><code class="language-{?s}">{s}</code></pre>
            , .{ node.meta, node.content });
        }

        pub fn link(allocator: std.mem.Allocator, node: jetzig.zmd.Node) ![]const u8 {
            return try std.fmt.allocPrint(allocator,
                \\<a class="underline decoration-sky-500" href="{0s}" title={1s}>{1s}</a>
            , .{ node.href.?, node.title.? });
        }
    };
};

pub fn main() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer std.debug.assert(gpa.deinit() == .ok);
    const allocator = gpa.allocator();

    const app = try jetzig.init(allocator);
    defer app.deinit();

    try app.start(routes, .{});
}
