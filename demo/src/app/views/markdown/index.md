# Markdown Example

![jetzig logo](https://www.jetzig.dev/jetzig.png)

_Markdown_ is rendered by _[zmd](https://github.com/jetzig-framework/zmd)_.

You can use a `StaticRequest` in your view if you prefer to render your _Markdown_ at build time, or use `Request` in development to render at run time without a server restart.

Simply create a `.md` file instead of a `.zmpl` file, e.g. `src/app/views/iguanas/index.md` and _Markdown_ will be rendered.

## An _ordered_ list

1. List item with a [link](https://ziglang.org/)
1. List item with some **bold** and _italic_ text
1. List item 3

## An _unordered_ list

* List item 1
* List item 2
* List item 3

## Define your own formatters in `src/main.zig`

```zig
pub const jetzig_options = struct {
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

        pub fn block(allocator: std.mem.Allocator, node: jetzig.zmd.Node) ![]const u8 {
            return try std.fmt.allocPrint(allocator,
                \\<pre class="w-1/2 font-mono mt-4 ms-3 bg-gray-900 p-2 text-white"><code>{s}</code></pre>
            , .{try jetzig.zmd.html.escape(allocator, node.content)});
        }

        pub fn link(allocator: std.mem.Allocator, node: jetzig.zmd.Node) ![]const u8 {
            return try std.fmt.allocPrint(allocator,
                \\<a class="underline decoration-sky-500" href="{0s}" title={1s}>{1s}</a>
            , .{ node.href.?, node.title.? });
        }
    };
}
```
