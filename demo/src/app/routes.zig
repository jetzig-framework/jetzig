pub const routes = struct {
    pub const static = .{
        .{
            .name = "root_index",
            .action = "index",
            .uri_path = "/",
            .template = "root_index",
            .function = @import("root.zig").index,
        },
    };

    pub const dynamic = .{
        .{
            .name = "quotes_get",
            .action = "get",
            .uri_path = "/quotes",
            .template = "quotes_get",
            .function = @import("quotes.zig").get,
        },
    };
};