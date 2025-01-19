const std = @import("std");
const websocket = @import("httpz").websocket;

pub fn main() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    const allocator = gpa.allocator();

    var server = try Server.init(allocator);
    defer server.deinit();

    try server.listen();
}

const Server = struct {
    allocator: std.mem.Allocator,
    websocket_server: websocket.Server(Handler),
    sessions: std.ArrayList(Stream),

    const Stream = struct {
        key: []const u8,
        connection: *websocket.Conn,
    };

    pub const App = struct {
        streams: std.ArrayList(Stream),
    };

    pub fn init(allocator: std.mem.Allocator) !Server {
        return .{
            .allocator = allocator,
            .websocket_server = try websocket.Server(Handler).init(allocator, .{
                .port = 9224,
                .address = "127.0.0.1",
                .handshake = .{
                    .timeout = 3,
                    .max_size = 1024,
                    .max_headers = 0,
                },
            }),
            .sessions = std.ArrayList(Stream).init(allocator),
        };
    }

    pub fn deinit(self: *Server) void {
        self.websocket_server.deinit();
        self.sessions.deinit();
    }

    pub fn listen(self: *Server) !void {
        var app: App = .{ .streams = std.ArrayList(Stream).init(self.allocator) };
        try self.websocket_server.listen(&app);
    }
};

const Handler = struct {
    app: *Server.App,
    connection: *websocket.Conn,

    pub fn init(handshake: websocket.Handshake, connection: *websocket.Conn, app: *Server.App) !Handler {
        std.debug.print("handshake: {any}\n", .{handshake});
        try app.streams.append(.{ .key = handshake.key, .connection = connection });

        return .{
            .app = app,
            .connection = connection,
        };
    }

    // You must defined a public clientMessage method
    pub fn clientMessage(self: *Handler, data: []const u8) !void {
        std.debug.print("message: {s}\n", .{data});
        try self.connection.write(data); // echo the message back
    }
};
