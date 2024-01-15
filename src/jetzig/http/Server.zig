const std = @import("std");

const jetzig = @import("../../jetzig.zig");

pub const ServerOptions = struct {
    cache: jetzig.caches.Cache,
    logger: jetzig.loggers.Logger,
    root_path: []const u8,
    secret: []const u8,
};

server: std.http.Server,
allocator: std.mem.Allocator,
port: u16,
host: []const u8,
cache: jetzig.caches.Cache,
logger: jetzig.loggers.Logger,
options: ServerOptions,
start_time: i128 = undefined,
routes: []jetzig.views.Route,
templates: []jetzig.TemplateFn,

const Self = @This();

pub fn init(
    allocator: std.mem.Allocator,
    host: []const u8,
    port: u16,
    options: ServerOptions,
    routes: []jetzig.views.Route,
    templates: []jetzig.TemplateFn,
) Self {
    const server = std.http.Server.init(allocator, .{ .reuse_address = true });

    return .{
        .server = server,
        .allocator = allocator,
        .host = host,
        .port = port,
        .cache = options.cache,
        .logger = options.logger,
        .options = options,
        .routes = routes,
        .templates = templates,
    };
}

pub fn deinit(self: *Self) void {
    self.server.deinit();
}

pub fn listen(self: *Self) !void {
    const address = std.net.Address.parseIp(self.host, self.port) catch unreachable;

    try self.server.listen(address);
    const cache_status = if (self.options.cache == .null_cache) "disabled" else "enabled";
    self.logger.debug("Listening on http://{s}:{} [cache:{s}]", .{ self.host, self.port, cache_status });
    try self.processRequests();
}

fn processRequests(self: *Self) !void {
    while (true) {
        var response = try self.server.accept(.{ .allocator = self.allocator });
        defer response.deinit();

        try response.headers.append("Connection", "close");

        while (response.reset() != .closing) {
            self.processNextRequest(&response) catch |err| {
                switch (err) {
                    error.EndOfStream => continue,
                    error.ConnectionResetByPeer => continue,
                    else => return err,
                }
            };
        }
    }
}

fn processNextRequest(self: *Self, response: *std.http.Server.Response) !void {
    try response.wait();

    self.start_time = std.time.nanoTimestamp();

    const body = try response.reader().readAllAlloc(self.allocator, 8192); // FIXME: Configurable max body size
    defer self.allocator.free(body);

    var arena = std.heap.ArenaAllocator.init(self.allocator);
    defer arena.deinit();

    var request = try jetzig.http.Request.init(arena.allocator(), self, response);
    defer request.deinit();

    const result = try self.pageContent(&request);
    defer result.deinit();

    response.transfer_encoding = .{ .content_length = result.value.content.len };
    var cookie_it = request.cookies.headerIterator();
    while (try cookie_it.next()) |header| {
        try response.headers.append("Set-Cookie", header);
    }
    response.status = switch (result.value.status_code) {
        .ok => .ok,
        .not_found => .not_found,
    };

    try response.do();
    try response.writeAll(result.value.content);

    try response.finish();

    const log_message = try self.requestLogMessage(&request, result);
    defer self.allocator.free(log_message);
    self.logger.debug("{s}", .{log_message});
}

fn pageContent(self: *Self, request: *jetzig.http.Request) !jetzig.caches.Result {
    const cache_key = try request.hash();

    if (self.cache.get(cache_key)) |item| {
        return item;
    } else {
        const response = try self.renderResponse(request);
        return try self.cache.put(cache_key, response);
    }
}

fn renderResponse(self: *Self, request: *jetzig.http.Request) !jetzig.http.Response {
    const view = try self.matchView(request);

    switch (request.requestFormat()) {
        .HTML => return self.renderHTML(request, view),
        .JSON => return self.renderJSON(request, view),
        .UNKNOWN => return self.renderHTML(request, view),
    }
}

fn renderHTML(
    self: *Self,
    request: *jetzig.http.Request,
    route: ?jetzig.views.Route,
) !jetzig.http.Response {
    if (route) |matched_route| {
        const expected_name = try matched_route.templateName(self.allocator);
        defer self.allocator.free(expected_name);

        for (self.templates) |template| {
            // FIXME: Tidy this up and use a hashmap for templates (or a more comprehensive
            // matching system) instead of an array.
            if (std.mem.eql(u8, expected_name, template.name)) {
                const view = try matched_route.render(matched_route, request);
                const content = try template.render(view.data);
                return .{ .allocator = self.allocator, .content = content, .status_code = .ok };
            }
        }

        return .{
            .allocator = self.allocator,
            .content = "",
            .status_code = .not_found,
        };
    } else {
        return .{
            .allocator = self.allocator,
            .content = "",
            .status_code = .not_found,
        };
    }
}

fn renderJSON(
    self: *Self,
    request: *jetzig.http.Request,
    route: ?jetzig.views.Route,
) !jetzig.http.Response {
    if (route) |matched_route| {
        const view = try matched_route.render(matched_route, request);
        var data = view.data;
        return .{
            .allocator = self.allocator,
            .content = try data.toJson(),
            .status_code = .ok,
        };
    } else return .{
        .allocator = self.allocator,
        .content = "",
        .status_code = .not_found,
    };
}

fn requestLogMessage(self: *Self, request: *jetzig.http.Request, result: jetzig.caches.Result) ![]const u8 {
    const status: jetzig.http.status_codes.TaggedStatusCode = switch (result.value.status_code) {
        .ok => .{ .ok = .{} },
        .not_found => .{ .not_found = .{} },
    };

    const formatted_duration = try jetzig.colors.duration(self.allocator, self.duration());
    defer self.allocator.free(formatted_duration);

    return try std.fmt.allocPrint(self.allocator, "[{s} {s}] {s} {s}", .{
        status.format(),
        formatted_duration,
        @tagName(request.method),
        request.path,
    });
}

fn duration(self: *Self) i64 {
    return @intCast(std.time.nanoTimestamp() - self.start_time);
}

fn matchView(self: *Self, request: *jetzig.http.Request) !?jetzig.views.Route {
    for (self.routes) |route| {
        if (route.action == .index and try request.match(route)) return route;
    }

    for (self.routes) |route| {
        if (try request.match(route)) return route;
    }

    return null;
}
