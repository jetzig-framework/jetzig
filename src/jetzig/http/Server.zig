const std = @import("std");

const jetzig = @import("../../jetzig.zig");

const root_file = @import("root");
const jetzig_server_options = if (@hasDecl(root_file, "jetzig_options")) root_file.jetzig_options else struct {};
const middlewares: []const type = if (@hasDecl(jetzig_server_options, "middlewares")) jetzig_server_options.middlewares else &.{};

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
    const server = std.http.Server.init(.{ .reuse_address = true });

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
        errdefer response.deinit();

        try response.headers.append("Connection", "close");

        while (response.reset() != .closing) {
            self.processNextRequest(&response) catch |err| {
                switch (err) {
                    error.EndOfStream, error.ConnectionResetByPeer => continue,
                    error.UnknownHttpMethod => continue, // TODO: Render 400 Bad Request here ?
                    else => return err,
                }
            };
        }

        response.deinit();
    }
}

fn processNextRequest(self: *Self, response: *std.http.Server.Response) !void {
    try response.wait();

    self.start_time = std.time.nanoTimestamp();

    const body = try response.reader().readAllAlloc(self.allocator, jetzig.config.max_bytes_request_body);
    defer self.allocator.free(body);

    var arena = std.heap.ArenaAllocator.init(self.allocator);
    defer arena.deinit();

    var request = try jetzig.http.Request.init(arena.allocator(), self, response);
    defer request.deinit();

    var middleware_data = std.BoundedArray(*anyopaque, middlewares.len).init(0) catch unreachable;
    inline for (middlewares, 0..) |middleware, index| {
        if (comptime !@hasDecl(middleware, "init")) continue;
        const data = try @call(.always_inline, middleware.init, .{&request});
        middleware_data.insert(index, data) catch unreachable; // We cannot overflow here because we know the length of the array
    }

    inline for (middlewares, 0..) |middleware, index| {
        if (comptime !@hasDecl(middleware, "beforeRequest")) continue;
        if (comptime @hasDecl(middleware, "init")) {
            const data = middleware_data.get(index);
            try @call(.always_inline, middleware.beforeRequest, .{ @as(*middleware, @ptrCast(@alignCast(data))), &request });
        } else {
            try @call(.always_inline, middleware.beforeRequest, .{&request});
        }
    }

    var result = try self.pageContent(&request);
    defer result.deinit();

    inline for (middlewares, 0..) |middleware, index| {
        if (comptime !@hasDecl(middleware, "afterRequest")) continue;
        if (comptime @hasDecl(middleware, "init")) {
            const data = middleware_data.get(index);
            try @call(.always_inline, middleware.afterRequest, .{ @as(*middleware, @ptrCast(@alignCast(data))), &request, &result });
        } else {
            try @call(.always_inline, middleware.afterRequest, .{ &request, &result });
        }
    }

    response.transfer_encoding = .{ .content_length = result.value.content.len };
    var cookie_it = request.cookies.headerIterator();
    while (try cookie_it.next()) |header| {
        // FIXME: Skip setting cookies that are already present ?
        try response.headers.append("Set-Cookie", header);
    }
    try response.headers.append("Content-Type", result.value.content_type);
    response.status = switch (result.value.status_code) {
        inline else => |status_code| @field(std.http.Status, @tagName(status_code)),
    };

    try response.send();
    try response.writeAll(result.value.content);

    try response.finish();

    const log_message = try self.requestLogMessage(&request, result);
    defer self.allocator.free(log_message);
    self.logger.debug("{s}", .{log_message});

    inline for (middlewares, 0..) |middleware, index| {
        if (comptime @hasDecl(middleware, "init")) {
            if (comptime @hasDecl(middleware, "deinit")) {
                const data = middleware_data.get(index);
                @call(.always_inline, middleware.deinit, .{ @as(*middleware, @ptrCast(@alignCast(data))), &request });
            }
        }
    }
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
    const static = self.matchStaticResource(request) catch |err| {
        if (isUnhandledError(err)) return err;
        const rendered = try self.internalServerError(request, err);
        return .{
            .allocator = self.allocator,
            .status_code = .internal_server_error,
            .content = rendered.content,
            .content_type = "text/html",
        };
    };

    if (static) |resource| return try self.renderStatic(request, resource);

    const route = try self.matchRoute(request);

    switch (request.requestFormat()) {
        .HTML => return self.renderHTML(request, route),
        .JSON => return self.renderJSON(request, route),
        .UNKNOWN => return self.renderHTML(request, route),
    }
}

fn renderStatic(self: *Self, request: *jetzig.http.Request, resource: StaticResource) !jetzig.http.Response {
    _ = request;
    return .{
        .allocator = self.allocator,
        .status_code = .ok,
        .content = resource.content,
        .content_type = resource.mime_type,
    };
}

fn renderHTML(
    self: *Self,
    request: *jetzig.http.Request,
    route: ?jetzig.views.Route,
) !jetzig.http.Response {
    if (route) |matched_route| {
        for (self.templates) |template| {
            // TODO: Use a hashmap to avoid O(n)
            if (std.mem.eql(u8, matched_route.template, template.name)) {
                const rendered = try self.renderView(matched_route, request, template);
                return .{
                    .allocator = self.allocator,
                    .content = rendered.content,
                    .status_code = rendered.view.status_code,
                    .content_type = "text/html",
                };
            }
        }

        return .{
            .allocator = self.allocator,
            .content = "",
            .status_code = .not_found,
            .content_type = "text/html",
        };
    } else {
        return .{
            .allocator = self.allocator,
            .content = "",
            .status_code = .not_found,
            .content_type = "text/html",
        };
    }
}

fn renderJSON(
    self: *Self,
    request: *jetzig.http.Request,
    route: ?jetzig.views.Route,
) !jetzig.http.Response {
    if (route) |matched_route| {
        const rendered = try self.renderView(matched_route, request, null);
        var data = rendered.view.data;

        if (data.value) |_| {} else _ = try data.object();
        try request.headers.append("Content-Type", "application/json");

        return .{
            .allocator = self.allocator,
            .content = try data.toJson(),
            .status_code = rendered.view.status_code,
            .content_type = "application/json",
        };
    } else return .{
        .allocator = self.allocator,
        .content = "",
        .status_code = .not_found,
        .content_type = "application/json",
    };
}

const RenderedView = struct { view: jetzig.views.View, content: []const u8 };

fn renderView(
    self: *Self,
    route: jetzig.views.Route,
    request: *jetzig.http.Request,
    template: ?jetzig.TemplateFn,
) !RenderedView {
    const view = route.render(route, request) catch |err| {
        self.logger.debug("Encountered error: {s}", .{@errorName(err)});
        if (isUnhandledError(err)) return err;
        return try self.internalServerError(request, err);
    };
    const content = if (template) |capture| try capture.render(view.data) else "";

    return .{ .view = view, .content = content };
}

fn isUnhandledError(err: anyerror) bool {
    return switch (err) {
        error.OutOfMemory => true,
        else => false,
    };
}

fn internalServerError(self: *Self, request: *jetzig.http.Request, err: anyerror) !RenderedView {
    request.response_data.reset();

    var object = try request.response_data.object();
    try object.put("error", request.response_data.string(@errorName(err)));

    const stack = @errorReturnTrace();
    if (stack) |capture| try self.logStackTrace(capture, request, object);

    return .{
        .view = jetzig.views.View{ .data = request.response_data, .status_code = .internal_server_error },
        .content = "Internal Server Error\n",
    };
}
fn logStackTrace(
    self: *Self,
    stack: *std.builtin.StackTrace,
    request: *jetzig.http.Request,
    object: *jetzig.data.Value,
) !void {
    _ = self;
    std.debug.print("\nStack Trace:\n{}", .{stack});
    var array = std.ArrayList(u8).init(request.allocator);
    const writer = array.writer();
    try stack.format("", .{}, writer);
    // TODO: Generate an array of objects with stack trace in useful data structure instead of
    // dumping the whole formatted backtrace as a JSON string:
    try object.put("backtrace", request.response_data.string(array.items));
}

fn requestLogMessage(self: *Self, request: *jetzig.http.Request, result: jetzig.caches.Result) ![]const u8 {
    const status: jetzig.http.status_codes.TaggedStatusCode = switch (result.value.status_code) {
        inline else => |status_code| @unionInit(
            jetzig.http.status_codes.TaggedStatusCode,
            @tagName(status_code),
            .{},
        ),
    };

    const formatted_duration = try jetzig.colors.duration(self.allocator, self.duration());
    defer self.allocator.free(formatted_duration);

    return try std.fmt.allocPrint(self.allocator, "[{s}/{s}/{s}] {s}", .{
        formatted_duration,
        request.fmtMethod(),
        status.format(),
        request.path,
    });
}

fn duration(self: *Self) i64 {
    return @intCast(std.time.nanoTimestamp() - self.start_time);
}

fn matchRoute(self: *Self, request: *jetzig.http.Request) !?jetzig.views.Route {
    for (self.routes) |route| {
        if (route.action == .index and try request.match(route)) return route;
    }

    for (self.routes) |route| {
        if (try request.match(route)) return route;
    }

    return null;
}

const StaticResource = struct { content: []const u8, mime_type: []const u8 = "application/octet-stream" };

fn matchStaticResource(self: *Self, request: *jetzig.http.Request) !?StaticResource {
    const public_content = try self.matchPublicContent(request);
    if (public_content) |content| return .{ .content = content };

    const static_content = try self.matchStaticContent(request);
    if (static_content) |content| return .{
        .content = content,
        .mime_type = switch (request.requestFormat()) {
            .HTML, .UNKNOWN => "text/html",
            .JSON => "application/json",
        },
    };

    return null;
}

fn matchPublicContent(self: *Self, request: *jetzig.http.Request) !?[]const u8 {
    _ = self;

    if (request.path.len < 2) return null;
    if (request.method != .GET) return null;

    var iterable_dir = std.fs.cwd().openDir("public", .{ .iterate = true }) catch |err| {
        switch (err) {
            error.FileNotFound => return null,
            else => return err,
        }
    };

    var walker = try iterable_dir.walk(request.allocator);

    while (try walker.next()) |file| {
        if (file.kind != .file) continue;

        if (std.mem.eql(u8, file.path, request.path[1..])) {
            return try iterable_dir.readFileAlloc(
                request.allocator,
                file.path,
                jetzig.config.max_bytes_static_content,
            );
        }
    }

    return null;
}

fn matchStaticContent(self: *Self, request: *jetzig.http.Request) !?[]const u8 {
    var static_dir = std.fs.cwd().openDir("static", .{}) catch |err| {
        switch (err) {
            error.FileNotFound => return null,
            else => return err,
        }
    };

    // TODO: Use a hashmap to avoid O(n)
    for (self.routes) |route| {
        if (route.static and try request.match(route)) {
            const extension = switch (request.requestFormat()) {
                .HTML, .UNKNOWN => ".html",
                .JSON => ".json",
            };

            const path = try std.mem.concat(request.allocator, u8, &[_][]const u8{ route.name, extension });

            return static_dir.readFileAlloc(
                request.allocator,
                path,
                jetzig.config.max_bytes_static_content,
            ) catch |err| {
                switch (err) {
                    error.FileNotFound => return null,
                    else => return err,
                }
            };
        }
    }

    return null;
}
