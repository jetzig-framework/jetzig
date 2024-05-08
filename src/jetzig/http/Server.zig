const std = @import("std");
const builtin = @import("builtin");

const jetzig = @import("../../jetzig.zig");
const zmpl = @import("zmpl");
const zmd = @import("zmd");
const httpz = @import("httpz");

pub const ServerOptions = struct {
    logger: jetzig.loggers.Logger,
    bind: []const u8,
    port: u16,
    secret: []const u8,
    detach: bool,
    environment: jetzig.Environment.EnvironmentName,
};

allocator: std.mem.Allocator,
logger: jetzig.loggers.Logger,
options: ServerOptions,
routes: []*jetzig.views.Route,
job_definitions: []const jetzig.JobDefinition,
mailer_definitions: []const jetzig.MailerDefinition,
mime_map: *jetzig.http.mime.MimeMap,
std_net_server: std.net.Server = undefined,
initialized: bool = false,
store: *jetzig.kv.Store,
job_queue: *jetzig.kv.Store,
cache: *jetzig.kv.Store,

const Server = @This();

pub fn init(
    allocator: std.mem.Allocator,
    options: ServerOptions,
    routes: []*jetzig.views.Route,
    job_definitions: []const jetzig.JobDefinition,
    mailer_definitions: []const jetzig.MailerDefinition,
    mime_map: *jetzig.http.mime.MimeMap,
    store: *jetzig.kv.Store,
    job_queue: *jetzig.kv.Store,
    cache: *jetzig.kv.Store,
) Server {
    return .{
        .allocator = allocator,
        .logger = options.logger,
        .options = options,
        .routes = routes,
        .job_definitions = job_definitions,
        .mailer_definitions = mailer_definitions,
        .mime_map = mime_map,
        .store = store,
        .job_queue = job_queue,
        .cache = cache,
    };
}

pub fn deinit(self: *Server) void {
    if (self.initialized) self.std_net_server.deinit();
    self.allocator.free(self.options.secret);
    self.allocator.free(self.options.bind);
}

const Dispatcher = struct {
    server: *Server,

    pub fn handle(self: Dispatcher, request: *httpz.Request, response: *httpz.Response) void {
        self.server.processNextRequest(request, response) catch |err| {
            self.server.errorHandlerFn(request, response, err);
        };
    }
};

pub fn listen(self: *Server) !void {
    var httpz_server = try httpz.ServerCtx(Dispatcher, Dispatcher).init(
        self.allocator,
        .{
            .port = self.options.port,
            .address = self.options.bind,
            .thread_pool = .{ .count = @intCast(try std.Thread.getCpuCount()) },
        },
        Dispatcher{ .server = self },
    );
    defer httpz_server.deinit();

    try self.logger.INFO("Listening on http://{s}:{} [{s}]", .{
        self.options.bind,
        self.options.port,
        @tagName(self.options.environment),
    });

    self.initialized = true;

    return try httpz_server.listen();
}

pub fn errorHandlerFn(self: *Server, request: *httpz.Request, response: *httpz.Response, err: anyerror) void {
    if (isBadHttpError(err)) return;

    self.logger.ERROR("Encountered error: {s} {s}", .{ @errorName(err), request.url.raw }) catch {};
    response.body = "500 Internal Server Error";
}

fn processNextRequest(
    self: *Server,
    httpz_request: *httpz.Request,
    httpz_response: *httpz.Response,
) !void {
    const state = try self.allocator.create(jetzig.http.Request.CallbackState);
    const arena = try self.allocator.create(std.heap.ArenaAllocator);
    arena.* = std.heap.ArenaAllocator.init(self.allocator);
    state.* = .{
        .arena = arena,
        .allocator = self.allocator,
    };

    // Regular arena deinit occurs in jetzig.http.Request.responseCompletCallback
    errdefer state.arena.deinit();

    const allocator = state.arena.allocator();

    const start_time = std.time.nanoTimestamp();

    var response = try jetzig.http.Response.init(allocator);
    var request = try jetzig.http.Request.init(
        allocator,
        self,
        start_time,
        httpz_request,
        httpz_response,
        &response,
    );

    try request.process();

    var middleware_data = try jetzig.http.middleware.afterRequest(&request);

    try self.renderResponse(&request);
    try request.response.headers.append("content-type", response.content_type);

    try jetzig.http.middleware.beforeResponse(&middleware_data, &request);

    try request.respond(state);

    try jetzig.http.middleware.afterResponse(&middleware_data, &request);
    jetzig.http.middleware.deinit(&middleware_data, &request);

    try self.logger.logRequest(&request);
}

fn renderResponse(self: *Server, request: *jetzig.http.Request) !void {
    const static_resource = self.matchStaticResource(request) catch |err| {
        if (isUnhandledError(err)) return err;

        const rendered = try self.renderInternalServerError(request, err);
        request.setResponse(rendered, .{});
        return;
    };

    if (static_resource) |resource| {
        try renderStatic(resource, request);
        return;
    }

    const route = try self.matchRoute(request, false);

    switch (request.requestFormat()) {
        .HTML => try self.renderHTML(request, route),
        .JSON => try self.renderJSON(request, route),
        .UNKNOWN => try self.renderHTML(request, route),
    }
}

fn renderStatic(resource: StaticResource, request: *jetzig.http.Request) !void {
    request.setResponse(
        .{ .view = .{ .data = request.response_data }, .content = resource.content },
        .{ .content_type = resource.mime_type },
    );
}

fn renderHTML(
    self: *Server,
    request: *jetzig.http.Request,
    route: ?*jetzig.views.Route,
) !void {
    if (route) |matched_route| {
        if (zmpl.findPrefixed("views", matched_route.template)) |template| {
            const rendered = self.renderView(matched_route, request, template) catch |err| {
                if (isUnhandledError(err)) return err;
                const rendered_error = try self.renderInternalServerError(request, err);
                return request.setResponse(rendered_error, .{});
            };
            return request.setResponse(rendered, .{});
        } else {
            return request.setResponse(try self.renderNotFound(request), .{});
        }
    } else {
        if (try self.renderMarkdown(request)) |rendered| {
            return request.setResponse(rendered, .{});
        } else {
            return request.setResponse(try self.renderNotFound(request), .{});
        }
    }
}

fn renderJSON(
    self: *Server,
    request: *jetzig.http.Request,
    route: ?*jetzig.views.Route,
) !void {
    if (route) |matched_route| {
        var rendered = try self.renderView(matched_route, request, null);
        var data = rendered.view.data;

        if (data.value) |_| {} else _ = try data.object();

        rendered.content = if (self.options.environment == .development)
            try data.toPrettyJson()
        else
            try data.toJson();

        request.setResponse(rendered, .{});
    } else {
        request.setResponse(try self.renderNotFound(request), .{});
    }
}

fn renderMarkdown(self: *Server, request: *jetzig.http.Request) !?RenderedView {
    _ = self;
    // No route recognized, but we can still render a static markdown file if it matches the URI:
    if (request.method != .GET) return null;
    if (try jetzig.markdown.render(request.allocator, request.path.base_path, null)) |content| {
        return .{
            .view = jetzig.views.View{ .data = request.response_data, .status_code = .ok },
            .content = content,
        };
    } else {
        return null;
    }
}

pub const RenderedView = struct { view: jetzig.views.View, content: []const u8 };

fn renderView(
    self: *Server,
    route: *jetzig.views.Route,
    request: *jetzig.http.Request,
    template: ?zmpl.Template,
) !RenderedView {
    // View functions return a `View` to encourage users to return from a view function with
    // `return request.render(.ok)`, but the actual rendered view is stored in
    // `request.rendered_view`.
    _ = route.render(route.*, request) catch |err| {
        try self.logger.ERROR("Encountered error: {s}", .{@errorName(err)});
        if (isUnhandledError(err)) return err;
        if (isBadRequest(err)) return try self.renderBadRequest(request);
        return try self.renderInternalServerError(request, err);
    };

    if (request.rendered_multiple) return error.JetzigMultipleRenderError;

    if (request.rendered_view) |rendered_view| {
        if (request.redirected) return .{ .view = rendered_view, .content = "" };

        if (template) |capture| {
            return .{
                .view = rendered_view,
                .content = try self.renderTemplateWithLayout(request, capture, rendered_view, route),
            };
        } else {
            return switch (request.requestFormat()) {
                .HTML, .UNKNOWN => try self.renderNotFound(request),
                .JSON => .{ .view = rendered_view, .content = "" },
            };
        }
    } else {
        try self.logger.WARN("`request.render` was not invoked. Rendering empty content.", .{});
        request.response_data.reset();
        return .{
            .view = .{ .data = request.response_data, .status_code = .no_content },
            .content = "",
        };
    }
}

fn renderTemplateWithLayout(
    self: *Server,
    request: *jetzig.http.Request,
    template: zmpl.Template,
    view: jetzig.views.View,
    route: *jetzig.views.Route,
) ![]const u8 {
    try addTemplateConstants(view, route);

    if (request.getLayout(route)) |layout_name| {
        // TODO: Allow user to configure layouts directory other than src/app/views/layouts/
        const prefixed_name = try std.mem.concat(
            self.allocator,
            u8,
            &[_][]const u8{ "layouts", "/", layout_name },
        );
        defer self.allocator.free(prefixed_name);

        if (zmpl.findPrefixed("views", prefixed_name)) |layout| {
            return try template.renderWithOptions(view.data, .{ .layout = layout });
        } else {
            try self.logger.WARN("Unknown layout: {s}", .{layout_name});
            return try template.render(view.data);
        }
    } else return try template.render(view.data);
}

fn addTemplateConstants(view: jetzig.views.View, route: *const jetzig.views.Route) !void {
    try view.data.addConst("jetzig_view", view.data.string(route.view_name));
    try view.data.addConst("jetzig_action", view.data.string(@tagName(route.action)));
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

fn isBadHttpError(err: anyerror) bool {
    return switch (err) {
        error.JetzigParseHeadError,
        error.UnknownHttpMethod,
        error.HttpHeadersInvalid,
        error.HttpHeaderContinuationsUnsupported,
        error.HttpTransferEncodingUnsupported,
        error.HttpConnectionHeaderUnsupported,
        error.InvalidContentLength,
        error.CompressionUnsupported,
        error.MissingFinalNewline,
        error.HttpConnectionClosing,
        error.ConnectionResetByPeer,
        error.BrokenPipe,
        => true,
        else => false,
    };
}

fn renderInternalServerError(self: *Server, request: *jetzig.http.Request, err: anyerror) !RenderedView {
    request.response_data.reset();

    try self.logger.ERROR("Encountered Error: {s}", .{@errorName(err)});

    const stack = @errorReturnTrace();
    if (stack) |capture| try self.logStackTrace(capture, request);

    const status = .internal_server_error;
    return try self.renderError(request, status);
}

fn renderNotFound(self: *Server, request: *jetzig.http.Request) !RenderedView {
    request.response_data.reset();

    const status: jetzig.http.StatusCode = .not_found;
    return try self.renderError(request, status);
}

fn renderBadRequest(self: *Server, request: *jetzig.http.Request) !RenderedView {
    request.response_data.reset();

    const status: jetzig.http.StatusCode = .bad_request;
    return try self.renderError(request, status);
}

fn renderError(
    self: Server,
    request: *jetzig.http.Request,
    status_code: jetzig.http.StatusCode,
) !RenderedView {
    if (try self.renderErrorView(request, status_code)) |view| return view;
    if (try renderStaticErrorPage(request, status_code)) |view| return view;

    return try renderDefaultError(request, status_code);
}

fn renderErrorView(
    self: Server,
    request: *jetzig.http.Request,
    status_code: jetzig.http.StatusCode,
) !?RenderedView {
    for (self.routes) |route| {
        if (std.mem.eql(u8, route.view_name, "errors") and route.action == .index) {
            request.response_data.reset();
            request.status_code = status_code;

            _ = route.render(route.*, request) catch |err| {
                if (isUnhandledError(err)) return err;
                try self.logger.ERROR(
                    "Unexepected error occurred while rendering error page: {s}",
                    .{@errorName(err)},
                );
                const stack = @errorReturnTrace();
                if (stack) |capture| try self.logStackTrace(capture, request);
                return try renderDefaultError(request, status_code);
            };

            if (request.rendered_view) |view| {
                switch (request.requestFormat()) {
                    .HTML, .UNKNOWN => {
                        if (zmpl.findPrefixed("views", route.template)) |template| {
                            try addTemplateConstants(view, route);
                            return .{ .view = view, .content = try template.render(request.response_data) };
                        }
                    },
                    .JSON => return .{ .view = view, .content = try request.response_data.toJson() },
                }
            }
        }
    }

    return null;
}

fn renderStaticErrorPage(request: *jetzig.http.Request, status_code: jetzig.http.StatusCode) !?RenderedView {
    if (request.requestFormat() == .JSON) return null;

    var dir = std.fs.cwd().openDir(
        jetzig.config.get([]const u8, "public_content_path"),
        .{ .iterate = false, .no_follow = true },
    ) catch |err| {
        switch (err) {
            error.FileNotFound => return null,
            else => return err,
        }
    };
    defer dir.close();

    const status = jetzig.http.status_codes.get(status_code);
    const content = dir.readFileAlloc(
        request.allocator,
        try std.mem.concat(request.allocator, u8, &.{ status.getCode(), ".html" }),
        jetzig.config.get(usize, "max_bytes_public_content"),
    ) catch |err| {
        switch (err) {
            error.FileNotFound => return null,
            else => return err,
        }
    };

    return .{
        .view = jetzig.views.View{ .data = request.response_data, .status_code = status_code },
        .content = content,
    };
}

fn renderDefaultError(
    request: *const jetzig.http.Request,
    status_code: jetzig.http.StatusCode,
) !RenderedView {
    const content = try request.formatStatus(status_code);
    return .{
        .view = jetzig.views.View{ .data = request.response_data, .status_code = status_code },
        .content = content,
    };
}

fn logStackTrace(
    self: Server,
    stack: *std.builtin.StackTrace,
    request: *jetzig.http.Request,
) !void {
    try self.logger.ERROR("\nStack Trace:\n{}", .{stack});
    var buf = std.ArrayList(u8).init(request.allocator);
    defer buf.deinit();
    const writer = buf.writer();
    try stack.format("", .{}, writer);
    try self.logger.ERROR("{s}\n", .{buf.items});
}

fn matchRoute(self: *Server, request: *jetzig.http.Request, static: bool) !?*jetzig.views.Route {
    for (self.routes) |route| {
        // .index routes always take precedence.
        if (route.static == static and route.action == .index and try request.match(route.*)) return route;
    }

    for (self.routes) |route| {
        if (route.static == static and try request.match(route.*)) return route;
    }

    return null;
}

const StaticResource = struct { content: []const u8, mime_type: []const u8 = "application/octet-stream" };

fn matchStaticResource(self: *Server, request: *jetzig.http.Request) !?StaticResource {
    // TODO: Map public and static routes at launch to avoid accessing the file system when
    // matching any route - currently every request causes file system traversal.
    const public_resource = try self.matchPublicContent(request);
    if (public_resource) |resource| return resource;

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

fn matchPublicContent(self: *Server, request: *jetzig.http.Request) !?StaticResource {
    if (request.path.file_path.len <= 1) return null;
    if (request.method != .GET) return null;

    var iterable_dir = std.fs.cwd().openDir(
        jetzig.config.get([]const u8, "public_content_path"),
        .{ .iterate = true, .no_follow = true },
    ) catch |err| {
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

        if (std.mem.eql(u8, file.path, request.path.file_path[1..])) {
            const content = try iterable_dir.readFileAlloc(
                request.allocator,
                file.path,
                jetzig.config.get(usize, "max_bytes_public_content"),
            );
            const extension = std.fs.path.extension(file.path);
            const mime_type = if (self.mime_map.get(extension)) |mime| mime else "application/octet-stream";
            return .{
                .content = content,
                .mime_type = mime_type,
            };
        }
    }

    return null;
}

fn matchStaticContent(self: *Server, request: *jetzig.http.Request) !?[]const u8 {
    var static_dir = std.fs.cwd().openDir("static", .{}) catch |err| {
        switch (err) {
            error.FileNotFound => return null,
            else => return err,
        }
    };
    defer static_dir.close();

    const matched_route = try self.matchRoute(request, true);

    if (matched_route) |route| {
        const static_path = try staticPath(request, route.*);

        if (static_path) |capture| {
            return static_dir.readFileAlloc(
                request.allocator,
                capture,
                jetzig.config.get(usize, "max_bytes_static_content"),
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

fn staticPath(request: *jetzig.http.Request, route: jetzig.views.Route) !?[]const u8 {
    const params = try request.params();
    defer params.deinit();

    const extension = switch (request.requestFormat()) {
        .HTML, .UNKNOWN => ".html",
        .JSON => ".json",
    };

    for (route.params.items, 0..) |static_params, index| {
        const expected_params = try static_params.getValue("params");
        switch (route.action) {
            .index, .post => {},
            inline else => {
                const id = try static_params.getValue("id");
                if (id == null) return error.JetzigRouteError; // `routes.zig` is incoherent.
                switch (id.?.*) {
                    .string => |capture| {
                        if (!std.mem.eql(u8, capture.value, request.path.resource_id)) continue;
                    },
                    // `routes.zig` is incoherent.
                    inline else => return error.JetzigRouteError,
                }
            },
        }
        if (expected_params != null and !expected_params.?.eql(params)) continue;

        const index_fmt = try std.fmt.allocPrint(request.allocator, "{}", .{index});
        defer request.allocator.free(index_fmt);

        return try std.mem.concat(
            request.allocator,
            u8,
            &[_][]const u8{ route.name, "_", index_fmt, extension },
        );
    }

    switch (route.action) {
        .index, .post => return try std.mem.concat(
            request.allocator,
            u8,
            &[_][]const u8{ route.name, extension },
        ),
        else => return null,
    }
}
