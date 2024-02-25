const std = @import("std");

const jetzig = @import("../../jetzig.zig");

const root_file = @import("root");

pub const jetzig_server_options = if (@hasDecl(root_file, "jetzig_options"))
    root_file.jetzig_options
else
    struct {};

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
        var std_response = try self.server.accept(.{ .allocator = self.allocator });

        var response = try jetzig.http.Response.init(
            self.allocator,
            &std_response,
        );
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

fn processNextRequest(self: *Self, response: *jetzig.http.Response) !void {
    try response.wait();

    self.start_time = std.time.nanoTimestamp();

    const body = try response.read();
    defer self.allocator.free(body);

    var arena = std.heap.ArenaAllocator.init(self.allocator);
    defer arena.deinit();

    var request = try jetzig.http.Request.init(arena.allocator(), self, response, body);
    defer request.deinit();

    var middleware_data = try jetzig.http.middleware.beforeMiddleware(&request);

    try self.renderResponse(&request, response);

    try jetzig.http.middleware.afterMiddleware(&middleware_data, &request, response);

    response.setTransferEncoding(.{ .content_length = response.content.len });

    var cookie_it = request.cookies.headerIterator();
    while (try cookie_it.next()) |header| {
        // FIXME: Skip setting cookies that are already present ?
        try response.headers.append("Set-Cookie", header);
    }

    try response.headers.append("Content-Type", response.content_type);

    try response.finish();

    const log_message = try self.requestLogMessage(&request, response);
    defer self.allocator.free(log_message);
    self.logger.debug("{s}", .{log_message});

    jetzig.http.middleware.deinit(&middleware_data, &request);
}

fn renderResponse(self: *Self, request: *jetzig.http.Request, response: *jetzig.http.Response) !void {
    const static = self.matchStaticResource(request) catch |err| {
        if (isUnhandledError(err)) return err;

        const rendered = try self.renderInternalServerError(request, err);

        response.content = rendered.content;
        response.status_code = .internal_server_error;
        response.content_type = "text/html";

        return;
    };

    if (static) |resource| {
        try renderStatic(resource, response);
        return;
    }

    const route = try self.matchRoute(request, false);

    switch (request.requestFormat()) {
        .HTML => try self.renderHTML(request, response, route),
        .JSON => try self.renderJSON(request, response, route),
        .UNKNOWN => try self.renderHTML(request, response, route),
    }
}

fn renderStatic(resource: StaticResource, response: *jetzig.http.Response) !void {
    response.status_code = .ok;
    response.content = resource.content;
    response.content_type = resource.mime_type;
}

fn renderHTML(
    self: *Self,
    request: *jetzig.http.Request,
    response: *jetzig.http.Response,
    route: ?jetzig.views.Route,
) !void {
    if (route) |matched_route| {
        for (self.templates) |template| {
            // TODO: Use a hashmap to avoid O(n)
            if (std.mem.eql(u8, matched_route.template, template.name)) {
                const rendered = try self.renderView(matched_route, request, template);
                response.content = rendered.content;
                response.status_code = rendered.view.status_code;
                response.content_type = "text/html";
                return;
            }
        }

        response.content = "";
        response.status_code = .not_found;
        response.content_type = "text/html";
        return;
    } else {
        response.content = "";
        response.status_code = .not_found;
        response.content_type = "text/html";
    }
}

fn renderJSON(
    self: *Self,
    request: *jetzig.http.Request,
    response: *jetzig.http.Response,
    route: ?jetzig.views.Route,
) !void {
    if (route) |matched_route| {
        const rendered = try self.renderView(matched_route, request, null);
        var data = rendered.view.data;

        if (data.value) |_| {} else _ = try data.object();
        try request.headers.append("Content-Type", "application/json");

        response.content = try data.toJson();
        response.status_code = rendered.view.status_code;
        response.content_type = "application/json";
    } else {
        response.content = "";
        response.status_code = .not_found;
        response.content_type = "application/json";
    }
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
        if (isBadRequest(err)) return try self.renderBadRequest(request);
        return try self.renderInternalServerError(request, err);
    };
    const content = if (template) |capture| try capture.render(view.data) else "";

    return .{ .view = view, .content = content };
}

fn isBadRequest(err: anyerror) bool {
    return switch (err) {
        error.JetzigBodyParseError, error.JetzigQueryParseError => true,
        else => false,
    };
}

fn isUnhandledError(err: anyerror) bool {
    return switch (err) {
        error.OutOfMemory => true,
        else => false,
    };
}

fn renderInternalServerError(self: *Self, request: *jetzig.http.Request, err: anyerror) !RenderedView {
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

fn renderBadRequest(self: *Self, request: *jetzig.http.Request) !RenderedView {
    _ = self;
    request.response_data.reset();

    var object = try request.response_data.object();
    try object.put("error", request.response_data.string("Bad Request"));

    return .{
        .view = jetzig.views.View{ .data = request.response_data, .status_code = .bad_request },
        .content = "Bad Request\n",
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

fn requestLogMessage(self: *Self, request: *jetzig.http.Request, response: *jetzig.http.Response) ![]const u8 {
    const status: jetzig.http.status_codes.TaggedStatusCode = switch (response.status_code) {
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

fn matchRoute(self: *Self, request: *jetzig.http.Request, static: bool) !?jetzig.views.Route {
    for (self.routes) |route| {
        // .index routes always take precedence.
        if (route.static == static and route.action == .index and try request.match(route)) return route;
    }

    for (self.routes) |route| {
        if (route.static == static and try request.match(route)) return route;
    }

    return null;
}

fn matchStaticParams(self: *Self, request: *jetzig.http.Request, route: jetzig.views.Route) !?usize {
    _ = self;
    const params = try request.params();

    for (route.params.items, 0..) |static_params, index| {
        if (try static_params.getValue("params")) |expected_params| {
            if (expected_params.eql(params)) return index;
        }
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
    defer iterable_dir.close();

    var walker = try iterable_dir.walk(request.allocator);
    defer walker.deinit();

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
    defer static_dir.close();

    const matched_route = try self.matchRoute(request, true);

    if (matched_route) |route| {
        const static_path = try self.staticPath(request, route);
        if (static_path) |capture| {
            return static_dir.readFileAlloc(
                request.allocator,
                capture,
                jetzig.config.max_bytes_static_content,
            ) catch |err| {
                switch (err) {
                    error.FileNotFound => return null,
                    else => return err,
                }
            };
        } else return null;
    }

    return null;
}

fn staticPath(self: *Self, request: *jetzig.http.Request, route: jetzig.views.Route) !?[]const u8 {
    _ = self;
    const params = try request.params();
    const extension = switch (request.requestFormat()) {
        .HTML, .UNKNOWN => ".html",
        .JSON => ".json",
    };

    for (route.params.items, 0..) |static_params, index| {
        if (try static_params.getValue("params")) |expected_params| {
            switch (route.action) {
                .index, .post => {},
                inline else => {
                    if (try static_params.getValue("id")) |id| {
                        switch (id.*) {
                            .string => |capture| {
                                if (!std.mem.eql(u8, capture.value, request.resourceId())) continue;
                            },
                            // Should be unreachable but we want to avoid a runtime panic.
                            inline else => continue,
                        }
                    }
                },
            }
            if (!expected_params.eql(params)) continue;

            const index_fmt = try std.fmt.allocPrint(request.allocator, "{}", .{index});
            defer request.allocator.free(index_fmt);

            return try std.mem.concat(
                request.allocator,
                u8,
                &[_][]const u8{ route.name, "_", index_fmt, extension },
            );
        }
    }

    switch (route.action) {
        .index, .post => return try std.mem.concat(
            request.allocator,
            u8,
            &[_][]const u8{ route.name, "_", extension },
        ),
        else => return null,
    }
}
