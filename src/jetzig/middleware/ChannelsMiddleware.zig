const std = @import("std");
const jetzig = @import("../../jetzig.zig");

const ChannelsMiddleware = @This();

pub fn setup(app: *jetzig.App) !void {
    app.route(.GET, "/_channels.js", ChannelsMiddleware, .renderChannels);
}

pub const Blocks = struct {
    pub fn header(_: jetzig.TemplateContext, writer: anytype) !void {
        try writer.writeAll(
            \\<script src="/_channels.js"></script>
        );
    }

    pub fn footer(context: jetzig.TemplateContext, writer: anytype) !void {
        const route = context.route orelse return;
        const request = context.request orelse return;
        const host = request.headers.getLower("host") orelse return;
        try writer.print(
            \\<script>
            \\    (() => {{
            \\        window.addEventListener('DOMContentLoaded', () => {{
            \\            Jetzig.channel.init("{s}", "/{s}");
            \\        }});
            \\    }})();
            \\</script>
            \\
        , .{ host, route.view_name });
    }
};

pub fn renderChannels(request: *jetzig.Request) !jetzig.View {
    return request.renderContent(.ok, @embedFile("channels/channels.js"));
}
