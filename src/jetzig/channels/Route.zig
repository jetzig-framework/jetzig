const jetzig = @import("../../jetzig.zig");

const Route = @This();

receiveMessageFn: *const fn (jetzig.channels.Message) anyerror!void,

pub fn receiveMessage(route: Route, message: jetzig.channels.Message) !void {
    try route.receiveMessageFn(message);
}
