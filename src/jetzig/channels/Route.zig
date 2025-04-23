const jetzig = @import("../../jetzig.zig");

const Route = @This();

receiveMessageFn: ?*const fn (jetzig.channels.Message) anyerror!void = null,
openConnectionFn: ?*const fn (jetzig.channels.Channel) anyerror!void = null,
path: []const u8,

pub fn receiveMessage(route: Route, message: jetzig.channels.Message) !void {
    if (route.receiveMessageFn) |func| try func(message);
}

pub fn initComptime(T: type, path: []const u8) Route {
    comptime {
        if (!@hasDecl(T, "Channel")) return .{};
        const openConnectionFn = if (@hasDecl(T.Channel, "open")) T.Channel.open else null;
        const receiveMessageFn = if (@hasDecl(T.Channel, "receive")) T.Channel.receive else null;

        return .{
            .openConnectionFn = openConnectionFn,
            .receiveMessageFn = receiveMessageFn,
            .path = path,
        };
    }
}
