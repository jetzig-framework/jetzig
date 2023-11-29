const std = @import("std");

const HttpServerOptions = struct {
    use_cache: bool,
};

const HttpServer = struct {
    server: std.http.Server,
    allocator: std.mem.Allocator,
    page_cache: std.StringHashMap([]const u8),
    port: u16,
    host: []const u8,
    options: HttpServerOptions,

    const Self = @This();

    pub fn init(
        allocator: std.mem.Allocator,
        cache: std.StringHashMap([]const u8),
        host: []const u8,
        port: u16,
        options: HttpServerOptions,
    ) HttpServer {
        const server = std.http.Server.init(allocator, .{ .reuse_address = true });

        return .{
            .server = server,
            .allocator = allocator,
            .page_cache = cache,
            .host = host,
            .port = port,
            .options = options,
        };
    }

    pub fn deinit(self: *Self) void {
        self.server.deinit();
    }

    pub fn listen(self: *Self) !void {
        const address = std.net.Address.parseIp(self.host, self.port) catch unreachable;

        try self.server.listen(address);
        std.debug.print(
            "Listening on http://{s}:{} [cache:{s}]\n",
            .{ self.host, self.port, if (self.options.use_cache) "enabled" else "disabled" }
        );
        try self.processRequests();
    }

    fn processRequests(self: *Self) !void {
        while (true) {
            self.processNextRequest() catch |err| {
                switch(err) {
                    error.EndOfStream => continue,
                    error.ConnectionResetByPeer => continue,
                    else => return err,
                }
            };
        }
    }

    fn processNextRequest(self: *Self) !void {
        var response = try self.server.accept(.{ .allocator = self.allocator });
        defer response.deinit();

        try response.wait();

        const content = try self.pageContent(response.request.method, response.request.target);

        response.transfer_encoding = .{ .content_length = content.len };
        try response.send();
        try response.writeAll(content);
        try response.finish();
    }

    fn pageContent(self: *Self, method: std.http.Method, target: []const u8) ![]const u8 {
      var buffer: [1<<16]u8 = undefined;
      const method_str = switch(method) {
          .POST => "post",
          else => "get"
      };
      const path = try std.mem.concat(self.allocator, u8, &[_][]const u8{ method_str, target });

      // std.debug.print("{s} {s}\n", .{ method_str, target });

      if (self.options.use_cache and self.page_cache.contains(path)) {
        defer self.allocator.free(path);

        if (self.page_cache.get(path)) |cached_content| return cached_content;
      }

      const content = std.fs.cwd().readFile(path, &buffer) catch |err| {
        return switch(err) {
            error.FileNotFound => {
                std.debug.print("File not found: {s}", .{path});
                return "";
            },
            else => err
        };
      };

      try self.page_cache.put(path, content);

      return content;
    }
};

pub fn main() !void {
    var general_purpose_allocator = std.heap.GeneralPurposeAllocator(.{}){};
    defer std.debug.assert(general_purpose_allocator.deinit() == .ok);
    const allocator = general_purpose_allocator.allocator();
    var page_cache = std.StringHashMap([]const u8).init(allocator);
    defer page_cache.deinit();

    const args = try std.process.argsAlloc(allocator);
    defer std.process.argsFree(allocator, args);

    const host: []const u8 = if (args.len > 1) args[1] else "127.0.0.1";
    const port: u16 = if (args.len > 2) try std.fmt.parseInt(u16, args[2], 10) else 3040;

    var server: HttpServer = HttpServer.init(
        allocator,
        page_cache,
        host,
        port,
        HttpServerOptions{ .use_cache = false },
    );

    defer server.deinit();

    server.listen() catch |err| {
        std.debug.print("{}\nExiting.\n", .{err});
        return err;
    };
}
