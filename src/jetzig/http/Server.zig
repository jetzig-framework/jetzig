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
    log_queue: *jetzig.loggers.LogQueue,
};

allocator: std.mem.Allocator,
logger: jetzig.loggers.Logger,
options: ServerOptions,
routes: []*jetzig.views.Route,
custom_routes: []jetzig.views.Route,
job_definitions: []const jetzig.JobDefinition,
mailer_definitions: []const jetzig.MailerDefinition,
mime_map: *jetzig.http.mime.MimeMap,
std_net_server: std.net.Server = undefined,
initialized: bool = false,
store: *jetzig.kv.Store,
job_queue: *jetzig.kv.Store,
cache: *jetzig.kv.Store,
decoded_static_route_params: []*jetzig.data.Value = &.{},
state: *anyopaque,

const Server = @This();

pub fn init(
    allocator: std.mem.Allocator,
    options: ServerOptions,
    routes: []*jetzig.views.Route,
    custom_routes: []jetzig.views.Route,
    job_definitions: []const jetzig.JobDefinition,
    mailer_definitions: []const jetzig.MailerDefinition,
    mime_map: *jetzig.http.mime.MimeMap,
    store: *jetzig.kv.Store,
    job_queue: *jetzig.kv.Store,
    cache: *jetzig.kv.Store,
    state: *anyopaque,
) Server {
    return .{
        .allocator = allocator,
        .logger = options.logger,
        .options = options,
        .routes = routes,
        .custom_routes = custom_routes,
        .job_definitions = job_definitions,
        .mailer_definitions = mailer_definitions,
        .mime_map = mime_map,
        .store = store,
        .job_queue = job_queue,
        .cache = cache,
        .state = state,
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
            self.server.errorHandlerFn(request, response, err) catch {};
        };
    }
};

pub fn listen(self: *Server) !void {
    try self.decodeStaticParams();

    var httpz_server = try httpz.ServerCtx(Dispatcher, Dispatcher).init(
        self.allocator,
        .{
            .port = self.options.port,
            .address = self.options.bind,
            .thread_pool = .{
                .count = jetzig.config.get(?u16, "thread_count") orelse @intCast(try std.Thread.getCpuCount()),
                .buffer_size = jetzig.config.get(usize, "buffer_size"),
            },
            .workers = .{
                .count = jetzig.config.get(u16, "worker_count"),
                .max_conn = jetzig.config.get(u16, "max_connections"),
                .retain_allocated_bytes = jetzig.config.get(usize, "arena_size"),
            },
            .request = .{
                .max_multiform_count = jetzig.config.get(usize, "max_multipart_form_fields"),
            },
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

pub fn errorHandlerFn(self: *Server, request: *httpz.Request, response: *httpz.Response, err: anyerror) !void {
    if (isBadHttpError(err)) return;

    self.logger.ERROR("Encountered error: {s} {s}", .{ @errorName(err), request.url.raw }) catch {};
    const stack = @errorReturnTrace();
    if (stack) |capture| self.logStackTrace(capture, request.arena) catch {};

    response.body = "500 Internal Server Error";
}

pub fn processNextRequest(
    self: *Server,
    httpz_request: *httpz.Request,
    httpz_response: *httpz.Response,
) !void {
    const start_time = std.time.nanoTimestamp();

    var response = try jetzig.http.Response.init(httpz_response.arena, httpz_response);
    var request = try jetzig.http.Request.init(
        httpz_response.arena,
        self,
        start_time,
        httpz_request,
        httpz_response,
        &response,
        self.state,
    );

    try request.process();

    var middleware_data = try jetzig.http.middleware.afterRequest(&request);

    if (request.middleware_rendered) |_| { // Request processing ends when a middleware renders or redirects.
        if (request.redirect_state) |state| {
            try request.renderRedirect(state);
        } else if (request.rendered_view) |rendered| {
            // TODO: Allow middleware to set content
            request.setResponse(.{ .view = rendered, .content = "" }, .{});
        }
        try request.response.headers.append("Content-Type", response.content_type);
        try request.respond();
    } else {
        try self.renderResponse(&request);
        try request.response.headers.append("Content-Type", response.content_type);
        try jetzig.http.middleware.beforeResponse(&middleware_data, &request);
        jetzig.http.middleware.deinit(&middleware_data, &request);

        try jetzig.http.middleware.afterResponse(&middleware_data, &request);
        try request.respond();
    }

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

    if (matchMiddlewareRoute(request)) |route| {
        if (route.content) |content| {
            const rendered: RenderedView = .{
                .view = .{ .data = request.response_data, .status_code = route.status },
                .content = content,
            };
            request.setResponse(rendered, .{ .content_type = route.content_type });
            return;
        } else unreachable; // In future a MiddlewareRoute might provide a render function etc.
    }

    const route = self.matchCustomRoute(request) orelse try self.matchRoute(request, false);

    switch (request.requestFormat()) {
        .HTML => try self.renderHTML(request, route),
        .JSON => try self.renderJSON(request, route),
        .UNKNOWN => try self.renderHTML(request, route),
    }

    if (request.redirect_state) |state| return try request.renderRedirect(state);
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
    route: ?jetzig.views.Route,
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
            // Try rendering without a template to see if we get a redirect or a template
            // assigned in a view.
            const rendered = self.renderView(matched_route, request, null) catch |err| {
                if (isUnhandledError(err)) return err;
                const rendered_error = try self.renderInternalServerError(request, err);
                return request.setResponse(rendered_error, .{});
            };

            return if (request.redirected or request.dynamic_assigned_template != null)
                request.setResponse(rendered, .{})
            else
                request.setResponse(try self.renderNotFound(request), .{});
        }
    } else {
        // If no matching route found, try to render a Markdown file in views directory.
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
    route: ?jetzig.views.Route,
) !void {
    if (route) |matched_route| {
        var rendered = try self.renderView(matched_route, request, null);
        var data = rendered.view.data;

        if (data.value) |_| {} else _ = try data.object();

        rendered.content = if (self.options.environment == .development)
            try data.toJsonOptions(.{ .pretty = true, .color = false })
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
    route: jetzig.views.Route,
    request: *jetzig.http.Request,
    maybe_template: ?zmpl.Template,
) !RenderedView {
    // View functions return a `View` to encourage users to return from a view function with
    // `return request.render(.ok)`, but the actual rendered view is stored in
    // `request.rendered_view`.
    _ = route.render(route, request) catch |err| {
        try self.logger.ERROR("Encountered error: {s}", .{@errorName(err)});
        if (isUnhandledError(err)) return err;
        if (isBadRequest(err)) return try self.renderBadRequest(request);
        return try self.renderInternalServerError(request, err);
    };

    const template: ?zmpl.Template = if (request.dynamic_assigned_template) |request_template|
        zmpl.findPrefixed("views", request_template) orelse maybe_template
    else
        maybe_template;

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
    route: jetzig.views.Route,
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

fn addTemplateConstants(view: jetzig.views.View, route: jetzig.views.Route) !void {
    try view.data.addConst("jetzig_view", view.data.string(route.view_name));

    const action = switch (route.action) {
        .custom => route.name,
        else => |tag| @tagName(tag),
    };

    try view.data.addConst("jetzig_action", view.data.string(action));
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

    try self.logger.logError(err);

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
                try self.logger.logError(err);
                try self.logger.ERROR(
                    "Unexepected error occurred while rendering error page: {s}",
                    .{@errorName(err)},
                );
                const stack = @errorReturnTrace();
                if (stack) |capture| try self.logStackTrace(capture, request.allocator);
                return try renderDefaultError(request, status_code);
            };

            if (request.rendered_view) |view| {
                switch (request.requestFormat()) {
                    .HTML, .UNKNOWN => {
                        if (zmpl.findPrefixed("views", route.template)) |template| {
                            try addTemplateConstants(view, route.*);
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
    allocator: std.mem.Allocator,
) !void {
    var buf = std.ArrayList(u8).init(allocator);
    defer buf.deinit();
    const writer = buf.writer();
    try stack.format("", .{}, writer);
    if (buf.items.len > 0) try self.logger.ERROR("{s}\n", .{buf.items});
}

fn matchCustomRoute(self: Server, request: *const jetzig.http.Request) ?jetzig.views.Route {
    for (self.custom_routes) |custom_route| {
        if (custom_route.match(request)) return custom_route;
    }

    return null;
}

fn matchMiddlewareRoute(request: *const jetzig.http.Request) ?jetzig.middleware.MiddlewareRoute {
    const middlewares = jetzig.config.get([]const type, "middleware");

    inline for (middlewares) |middleware| {
        if (@hasDecl(middleware, "routes")) {
            inline for (middleware.routes) |route| {
                if (route.match(request)) return route;
            }
        }
    }

    return null;
}

fn matchRoute(self: *Server, request: *jetzig.http.Request, static: bool) !?jetzig.views.Route {
    for (self.routes) |route| {
        // .index routes always take precedence.
        if (route.static == static and route.action == .index and try request.match(route.*)) return route.*;
    }

    for (self.routes) |route| {
        if (route.static == static and try request.match(route.*)) return route.*;
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
    var path_buffer: [256]u8 = undefined;
    while (try walker.next()) |file| {
        if (file.kind != .file) continue;
        const file_path = if (builtin.os.tag == .windows) blk: {
            _ = std.mem.replace(u8, file.path, std.fs.path.sep_str_windows, std.fs.path.sep_str_posix, &path_buffer);
            break :blk path_buffer[0..file.path.len];
        } else file.path;
        if (std.mem.eql(u8, file_path, request.path.file_path[1..])) {
            const content = try iterable_dir.readFileAlloc(
                request.allocator,
                file_path,
                jetzig.config.get(usize, "max_bytes_public_content"),
            );
            const extension = std.fs.path.extension(file_path);
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
    const request_format = request.requestFormat();
    const matched_route = try self.matchRoute(request, true);

    if (matched_route) |route| {
        if (@hasDecl(jetzig.root, "static")) {
            inline for (jetzig.root.static.compiled, 0..) |static_output, index| {
                if (!@hasField(@TypeOf(static_output), "route_id")) continue;

                if (std.mem.eql(u8, static_output.route_id, route.id)) {
                    const params = try request.params();

                    if (index < self.decoded_static_route_params.len) {
                        if (matchStaticOutput(
                            self.decoded_static_route_params[index].getT(.string, "id"),
                            self.decoded_static_route_params[index].get("params"),
                            route,
                            request,
                            params,
                        )) return switch (request_format) {
                            .HTML, .UNKNOWN => static_output.output.html,
                            .JSON => static_output.output.json,
                        };
                    }
                }
            }
        } else {
            return null;
        }
    }

    return null;
}

pub fn decodeStaticParams(self: *Server) !void {
    if (!@hasDecl(jetzig.root, "static")) return;

    // Store decoded static params (i.e. declared in views) for faster comparison at request time.
    var decoded = std.ArrayList(*jetzig.data.Value).init(self.allocator);
    for (jetzig.root.static.compiled) |compiled| {
        const data = try self.allocator.create(jetzig.data.Data);
        data.* = jetzig.data.Data.init(self.allocator);
        try data.fromJson(compiled.output.params orelse "{}");
        try decoded.append(data.value.?);
    }

    self.decoded_static_route_params = try decoded.toOwnedSlice();
}

fn matchStaticOutput(
    maybe_expected_id: ?[]const u8,
    maybe_expected_params: ?*jetzig.data.Value,
    route: jetzig.views.Route,
    request: *const jetzig.http.Request,
    params: *jetzig.data.Value,
) bool {
    return if (maybe_expected_params) |expected_params| blk: {
        const params_match = expected_params.count() == 0 or expected_params.eql(params);
        break :blk switch (route.action) {
            .index, .post => params_match,
            inline else => if (maybe_expected_id) |expected_id|
                std.mem.eql(u8, expected_id, request.path.resource_id) and params_match
            else
                false,
        };
    } else if (maybe_expected_id) |id|
        std.mem.eql(u8, id, request.path.resource_id)
    else
        true; // We reached a params filter (possibly the default catch-all) with no params set.
}
