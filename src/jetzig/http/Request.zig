const std = @import("std");

const httpz = @import("httpz");

const jetzig = @import("../../jetzig.zig");

const Request = @This();
const default_content_type = "text/html";

pub const Method = enum { DELETE, GET, PATCH, POST, HEAD, PUT, CONNECT, OPTIONS, TRACE };
pub const Modifier = enum { edit, new };
pub const Format = enum { HTML, JSON, UNKNOWN };

allocator: std.mem.Allocator,
path: jetzig.http.Path,
method: Method,
headers: jetzig.http.Headers,
server: *jetzig.http.Server,
httpz_request: *httpz.Request,
httpz_response: *httpz.Response,
response: *jetzig.http.Response,
status_code: jetzig.http.status_codes.StatusCode = .not_found,
response_data: *jetzig.data.Data,
query_params: ?*jetzig.http.Query = null,
query_body: ?*jetzig.http.Query = null,
multipart: ?jetzig.http.MultipartQuery = null,
parsed_multipart: ?*jetzig.data.Data = null,
_cookies: ?*jetzig.http.Cookies = null,
_session: ?*jetzig.http.Session = null,
body: []const u8 = undefined,
state: enum { initial, processed } = .initial,
response_started: bool = false,
dynamic_assigned_template: ?[]const u8 = null,
layout: ?[]const u8 = null,
layout_disabled: bool = false,
rendered: bool = false,
redirected: bool = false,
failed: bool = false,
redirect_state: ?RedirectState = null,
middleware_rendered: ?struct { name: []const u8, action: []const u8 } = null,
middleware_rendered_during_response: bool = false,
middleware_data: jetzig.http.middleware.MiddlewareData = undefined,
rendered_multiple: bool = false,
rendered_view: ?jetzig.views.View = null,
start_time: i128,
store: RequestStore,
cache: RequestStore,
repo: *jetzig.database.Repo,
global: *jetzig.Global,

/// Wrapper for KV store that uses the request's arena allocator for fetching values.
pub const RequestStore = struct {
    allocator: std.mem.Allocator,
    store: *jetzig.kv.Store,

    /// Put a String or into the key-value store.
    pub fn get(self: RequestStore, key: []const u8) !?*jetzig.data.Value {
        return try self.store.get(try self.data(), key);
    }

    /// Get a String from the store.
    pub fn put(self: RequestStore, key: []const u8, value: *jetzig.data.Value) !void {
        try self.store.put(key, value);
    }

    /// Remove a String to from the key-value store and return it if found.
    pub fn fetchRemove(self: RequestStore, key: []const u8) !?*jetzig.data.Value {
        return try self.store.fetchRemove(try self.data(), key);
    }

    /// Remove a String to from the key-value store.
    pub fn remove(self: RequestStore, key: []const u8) !void {
        try self.store.remove(key);
    }

    /// Append a Value to the end of an Array in the key-value store.
    pub fn append(self: RequestStore, key: []const u8, value: *jetzig.data.Value) !void {
        try self.store.append(key, value);
    }

    /// Prepend a Value to the start of an Array in the key-value store.
    pub fn prepend(self: RequestStore, key: []const u8, value: *jetzig.data.Value) !void {
        try self.store.prepend(key, value);
    }

    /// Pop a String from an Array in the key-value store.
    pub fn pop(self: RequestStore, key: []const u8) !?*jetzig.data.Value {
        return try self.store.pop(try self.data(), key);
    }

    /// Left-pop a String from an Array in the key-value store.
    pub fn popFirst(self: RequestStore, key: []const u8) !?*jetzig.data.Value {
        return try self.store.popFirst(try self.data(), key);
    }

    fn data(self: RequestStore) !*jetzig.data.Data {
        const arena_data = try self.allocator.create(jetzig.data.Data);
        arena_data.* = jetzig.data.Data.init(self.allocator);
        return arena_data;
    }
};

pub fn init(
    allocator: std.mem.Allocator,
    server: *jetzig.http.Server,
    start_time: i128,
    httpz_request: *httpz.Request,
    httpz_response: *httpz.Response,
    response: *jetzig.http.Response,
    repo: *jetzig.database.Repo,
) !Request {
    const method = switch (httpz_request.method) {
        .DELETE => Method.DELETE,
        .GET => Method.GET,
        .PATCH => Method.PATCH,
        .POST => Method.POST,
        .HEAD => Method.HEAD,
        .PUT => Method.PUT,
        .OPTIONS => Method.OPTIONS,
    };

    const response_data = try allocator.create(jetzig.data.Data);
    response_data.* = jetzig.data.Data.init(allocator);

    return .{
        .allocator = allocator,
        .path = jetzig.http.Path.init(httpz_request.url.raw),
        .method = method,
        .headers = jetzig.http.Headers.init(allocator, httpz_request.headers),
        .server = server,
        .response = response,
        .response_data = response_data,
        .httpz_request = httpz_request,
        .httpz_response = httpz_response,
        .start_time = start_time,
        .store = .{ .store = server.store, .allocator = allocator },
        .cache = .{ .store = server.cache, .allocator = allocator },
        .repo = repo,
        .global = if (@hasField(jetzig.Global, "__jetzig_default"))
            undefined
        else
            @ptrCast(@alignCast(server.global)),
    };
}

pub fn deinit(self: *Request) void {
    if (self._session) |*capture| {
        capture.*.deinit();
        self.allocator.destroy(capture.*);
    }
    if (self._cookies) |*capture| {
        capture.*.deinit();
        self.allocator.destroy(capture.*);
    }
    if (self.state != .initial) self.allocator.free(self.body);
}

/// Process request, read body if present.
pub fn process(self: *Request) !void {
    self.body = self.httpz_request.body() orelse "";
    self.state = .processed;
}

/// Set response headers, write response payload, and finalize the response.
pub fn respond(self: *Request) !void {
    if (self.state == .initial) unreachable;

    try self.setCookieHeaders();

    const status = jetzig.http.status_codes.get(self.response.status_code);
    self.httpz_response.status = try status.getCodeInt();
    self.httpz_response.body = self.response.content;
}

/// Render a response. This function can only be called once per request (repeat calls will
/// trigger an error).
pub fn render(self: *Request, status_code: jetzig.http.status_codes.StatusCode) jetzig.views.View {
    if (self.rendered or self.failed) self.rendered_multiple = true;

    self.rendered = true;
    if (self.response_started) self.middleware_rendered_during_response = true;
    self.rendered_view = .{ .data = self.response_data, .status_code = status_code };
    return self.rendered_view.?;
}

/// Render an error. This function can only be called once per request (repeat calls will
/// trigger an error).
pub fn fail(self: *Request, status_code: jetzig.http.status_codes.StatusCode) jetzig.views.View {
    if (self.rendered or self.redirected) self.rendered_multiple = true;

    self.rendered = true;
    self.failed = true;
    if (self.response_started) self.middleware_rendered_during_response = true;
    self.rendered_view = .{ .data = self.response_data, .status_code = status_code };
    return self.rendered_view.?;
}

/// Issue a redirect to a new location.
/// ```zig
/// return request.redirect("https://www.example.com/", .moved_permanently);
/// ```
/// ```zig
/// return request.redirect("https://www.example.com/", .found);
/// ```
/// The second argument must be `moved_permanently` or `found`.
pub fn redirect(
    self: *Request,
    location: []const u8,
    redirect_status: enum { moved_permanently, found },
) jetzig.views.View {
    if (self.rendered or self.failed) self.rendered_multiple = true;

    self.rendered = true;
    self.redirected = true;
    if (self.response_started) self.middleware_rendered_during_response = true;

    const status_code = switch (redirect_status) {
        .moved_permanently => jetzig.http.status_codes.StatusCode.moved_permanently,
        .found => jetzig.http.status_codes.StatusCode.found,
    };

    self.redirect_state = .{ .location = location, .status_code = status_code };
    return .{ .data = self.response_data, .status_code = status_code };
}

pub fn middleware(
    self: *const Request,
    comptime name: jetzig.http.middleware.Enum,
) jetzig.http.middleware.Type(name) {
    inline for (jetzig.http.middleware.middlewares, 0..) |T, index| {
        if (@hasDecl(T, "middleware_name") and std.mem.eql(u8, @tagName(name), T.middleware_name)) {
            const middleware_data = self.middleware_data.get(index);
            return @as(*jetzig.http.middleware.Type(name), @ptrCast(@alignCast(middleware_data))).*;
        }
    }
    unreachable;
}

const RedirectState = struct { location: []const u8, status_code: jetzig.http.status_codes.StatusCode };

pub fn renderRedirect(self: *Request, state: RedirectState) !void {
    self.response_data.reset();

    self.response.headers.append("Location", state.location) catch |err| {
        switch (err) {
            error.JetzigTooManyHeaders => std.debug.print(
                "Header limit reached. Unable to add redirect header.\n",
                .{},
            ),
            else => @panic("OOM"),
        }
    };

    const view = jetzig.views.View{ .data = self.response_data, .status_code = state.status_code };
    const status = jetzig.http.status_codes.get(state.status_code);
    const maybe_template = jetzig.zmpl.findPrefixed("views", status.getCode());
    self.rendered_view = view;

    var root = try self.response_data.root(.object);
    try root.put("location", self.response_data.string(state.location));
    const content = switch (self.requestFormat()) {
        .HTML, .UNKNOWN => if (maybe_template) |template| blk: {
            try view.data.addConst("jetzig_view", view.data.string("internal"));
            try view.data.addConst("jetzig_action", view.data.string(@tagName(state.status_code)));
            break :blk try template.render(self.response_data);
        } else try std.fmt.allocPrint(self.allocator, "Redirecting to {s}", .{state.location}),
        .JSON => blk: {
            break :blk try std.json.stringifyAlloc(
                self.allocator,
                .{ .location = state.location, .status = .{
                    .message = status.getMessage(),
                    .code = status.getCode(),
                } },
                .{},
            );
        },
    };

    self.setResponse(.{ .view = view, .content = content }, .{});
}

/// Infer the current format (JSON or HTML) from the request in this order:
/// * Extension (path ends in `.json` or `.html`)
/// * `Accept` header (`application/json` or `text/html`)
/// * `Content-Type` header (`application/json` or `text/html`)
/// * Fall back to default: HTML
pub fn requestFormat(self: *const Request) jetzig.http.Request.Format {
    return self.extensionFormat() orelse
        self.acceptHeaderFormat() orelse
        self.contentTypeHeaderFormat() orelse
        .UNKNOWN;
}

/// Set the layout for the current request/response. Use this to override a `pub const layout`
/// declaration in a view, either in middleware or in a view function itself.
pub fn setLayout(self: *Request, layout: ?[]const u8) void {
    if (layout) |layout_name| {
        self.layout = layout_name;
        self.layout_disabled = false;
    } else {
        self.layout_disabled = true;
    }
}

/// Derive a layout name from the current request if defined, otherwise from the route (if
/// defined).
pub fn getLayout(self: *Request, route: jetzig.views.Route) ?[]const u8 {
    if (self.layout_disabled) return null;
    if (self.layout) |capture| return capture;
    if (route.layout) |capture| return capture;

    return null;
}

/// Shortcut for `request.headers.getFirstValue`. Returns the first matching value for a given
/// header name or `null` if not found. Header names are case-insensitive.
pub fn getHeader(self: *const Request, key: []const u8) ?[]const u8 {
    return self.headers.getFirstValue(key);
}

/// Return a `Value` representing request parameters. Parameters are normalized, meaning that
/// both the JSON request body and query parameters are accessed via the same interface.
/// Note that query parameters are supported for JSON requests if no request body is present,
/// otherwise the parsed JSON request body will take precedence and query parameters will be
/// ignored.
pub fn params(self: *Request) !*jetzig.data.Value {
    if (self.state == .initial) unreachable;

    switch (self.requestFormat()) {
        .JSON => {
            if (self.body.len == 0) return self.queryParams();

            var data = try self.allocator.create(jetzig.data.Data);
            data.* = jetzig.data.Data.init(self.allocator);
            data.fromJson(self.body) catch |err| {
                switch (err) {
                    error.SyntaxError, error.UnexpectedEndOfInput => return error.JetzigBodyParseError,
                    else => return err,
                }
            };
            return data.value.?;
        },
        .HTML, .UNKNOWN => return self.parseQuery(),
    }
}

/// Retrieve a file from a `multipart/form-data`-encoded request body, if present.
pub fn file(self: *Request, name: []const u8) !?jetzig.http.File {
    _ = try self.parseQuery();
    if (self.multipart) |multipart| {
        return multipart.getFile(name);
    } else {
        return null;
    }
}

/// Return a `*Value` representing request parameters. This function **always** returns the
/// parsed query string and never the request body.
pub fn queryParams(self: *Request) !*jetzig.data.Value {
    if (self.query_params) |parsed| return parsed.data.value.?;

    const data = try self.allocator.create(jetzig.data.Data);
    data.* = jetzig.data.Data.init(self.allocator);
    self.query_params = try self.allocator.create(jetzig.http.Query);
    self.query_params.?.* = jetzig.http.Query.init(
        self.allocator,
        self.path.query orelse "",
        data,
    );
    try self.query_params.?.parse();
    return self.query_params.?.data.value.?;
}

// Parse request body as params if present, otherwise delegate to `queryParams`.
fn parseQuery(self: *Request) !*jetzig.data.Value {
    if (self.body.len == 0) return try self.queryParams();
    if (self.query_body) |parsed| return parsed.data.value.?;
    if (self.parsed_multipart) |parsed| return parsed.value.?;

    const maybe_multipart = self.httpz_request.multiFormData() catch |err| blk: {
        switch (err) {
            error.NotMultipartForm => break :blk null,
            else => return err,
        }
    };

    if (maybe_multipart) |multipart| {
        self.multipart = jetzig.http.MultipartQuery{ .allocator = self.allocator, .key_value = multipart };
        self.parsed_multipart = try self.multipart.?.params();
        return self.parsed_multipart.?.value.?;
    }

    const data = try self.allocator.create(jetzig.data.Data);
    data.* = jetzig.data.Data.init(self.allocator);
    self.query_body = try self.allocator.create(jetzig.http.Query);
    self.query_body.?.* = jetzig.http.Query.init(
        self.allocator,
        self.body,
        data,
    );

    try self.query_body.?.parse();

    return self.query_body.?.data.value.?;
}

/// Parse `Cookie` header into separate cookies.
pub fn cookies(self: *Request) !*jetzig.http.Cookies {
    if (self._cookies) |capture| return capture;

    const cookie = self.httpz_request.headers.get("cookie");

    const local_cookies = try self.allocator.create(jetzig.http.Cookies);
    local_cookies.* = jetzig.http.Cookies.init(
        self.allocator,
        cookie orelse "",
    );
    try local_cookies.parse();

    self._cookies = local_cookies;

    return local_cookies;
}

/// Parse cookies, decrypt Jetzig cookie (`jetzig.http.Session.cookie_name`) and return a mutable
/// `jetzig.http.Session`.
pub fn session(self: *Request) !*jetzig.http.Session {
    if (self._session) |capture| return capture;

    const local_session = try self.allocator.create(jetzig.http.Session);
    local_session.* = jetzig.http.Session.init(
        self.allocator,
        try self.cookies(),
        self.server.env.secret,
    );
    local_session.parse() catch |err| {
        switch (err) {
            error.JetzigInvalidSessionCookie => {
                try self.server.logger.DEBUG("Invalid session cookie detected. Resetting session.", .{});
                try local_session.reset();
            },
            else => return err,
        }
    };

    self._session = local_session;
    return local_session;
}

/// Create a new Job. Receives a job name which must resolve to `src/app/jobs/<name>.zig`
/// Call `Job.put(...)` to set job params.
/// Call `Job.background()` to run the job outside of the request/response flow.
/// e.g.:
/// ```
/// pub fn post(request: *jetzig.Request, data: *jetzig.Data) !jetzig.View {
///     var job = try request.job("foo"); // Will invoke `process()` in `src/app/jobs/foo.zig`
///     try job.put("foo", data.string("bar"));
///     try job.background(); // Job added to queue and processed by job worker.
///     return request.render(.ok);
/// }
/// ```
pub fn job(self: *Request, job_name: []const u8) !*jetzig.Job {
    const background_job = try self.allocator.create(jetzig.Job);
    background_job.* = jetzig.Job.init(
        self.allocator,
        self.server.store,
        self.server.job_queue,
        self.server.cache,
        self.server.logger,
        self.server.job_definitions,
        job_name,
    );
    return background_job;
}

const RequestMail = struct {
    request: *Request,
    mail_params: jetzig.mail.MailParams,
    name: []const u8,

    // Will allow scheduling when strategy is `.later` (e.g.).
    const DeliveryOptions = struct {};

    pub fn deliver(self: RequestMail, strategy: enum { background, now }, options: DeliveryOptions) !void {
        _ = options;
        var mail_job = try self.request.job("__jetzig_mail");

        try mail_job.params.put("mailer_name", mail_job.data.string(self.name));

        const from = if (self.mail_params.from) |from| mail_job.data.string(from) else null;
        try mail_job.params.put("from", from);

        var to_array = try mail_job.data.array();
        if (self.mail_params.to) |capture| {
            for (capture) |to| try to_array.append(mail_job.data.string(to));
        }
        try mail_job.params.put("to", to_array);

        const subject = if (self.mail_params.subject) |subject| mail_job.data.string(subject) else null;
        try mail_job.params.put("subject", subject);

        const html = if (self.mail_params.html) |html| mail_job.data.string(html) else null;
        try mail_job.params.put("html", html);

        const text = if (self.mail_params.text) |text| mail_job.data.string(text) else null;
        try mail_job.params.put("text", text);

        if (self.request.response_data.value) |value| try mail_job.params.put(
            "params",
            if (strategy == .now) try value.clone(self.request.allocator) else value,
        );

        switch (strategy) {
            .background => try mail_job.schedule(),
            .now => try mail_job.definition.?.runFn(
                self.request.allocator,
                mail_job.params,
                jetzig.jobs.JobEnv{
                    .vars = self.request.server.env.vars,
                    .environment = self.request.server.env.environment,
                    .logger = self.request.server.logger,
                    .routes = self.request.server.routes,
                    .mailers = self.request.server.mailer_definitions,
                    .jobs = self.request.server.job_definitions,
                    .store = self.request.server.store,
                    .cache = self.request.server.cache,
                    .mutex = undefined,
                },
            ),
        }
    }
};

/// Create a new email from the mailer named `name` (`app/mailers/<name>.zig`). Pass delivery
/// params to override defaults defined my mailer (`to`, `from`, `subject`, etc.).
/// Must call `deliver` on the returned `RequestMail` to send the email.
/// Example:
/// ```zig
/// const mail = request.mail("welcome", .{ .to = &.{"hello@jetzig.dev"} });
/// try mail.deliver(.background, .{});
/// ```
pub fn mail(self: *Request, name: []const u8, mail_params: jetzig.mail.MailParams) RequestMail {
    return .{
        .request = self,
        .name = name,
        .mail_params = mail_params,
    };
}

fn extensionFormat(self: *const Request) ?jetzig.http.Request.Format {
    const extension = self.path.extension orelse return null;
    if (std.mem.eql(u8, extension, ".html")) {
        return .HTML;
    } else if (std.mem.eql(u8, extension, ".json")) {
        return .JSON;
    } else {
        return null;
    }
}

pub fn acceptHeaderFormat(self: *const Request) ?jetzig.http.Request.Format {
    if (self.httpz_request.headers.get("accept")) |value| {
        if (std.mem.eql(u8, value, "text/html")) return .HTML;
        if (std.mem.eql(u8, value, "application/json")) return .JSON;
    }

    return null;
}

pub fn contentTypeHeaderFormat(self: *const Request) ?jetzig.http.Request.Format {
    if (self.httpz_request.headers.get("content-type")) |value| {
        if (std.mem.eql(u8, value, "text/html")) return .HTML;
        if (std.mem.eql(u8, value, "application/json")) return .JSON;
    }

    return null;
}

pub fn fmtMethod(self: *const Request, colorized: bool) []const u8 {
    if (!colorized) return @tagName(self.method);

    return switch (self.method) {
        .GET => jetzig.colors.cyan("GET"),
        .PUT => jetzig.colors.yellow("PUT"),
        .PATCH => jetzig.colors.yellow("PATCH"),
        .HEAD => jetzig.colors.white("HEAD"),
        .POST => jetzig.colors.green("POST"),
        .DELETE => jetzig.colors.red("DELETE"),
        inline else => |method| jetzig.colors.white(@tagName(method)),
    };
}

/// Format a status code appropriately for the current request format.
/// e.g. `.HTML` => `404 Not Found`
///      `.JSON` => `{ "message": "Not Found", "status": "404" }`
pub fn formatStatus(self: *const Request, status_code: jetzig.http.StatusCode) ![]const u8 {
    const status = jetzig.http.status_codes.get(status_code);

    return switch (self.requestFormat()) {
        .JSON => try std.json.stringifyAlloc(self.allocator, .{
            .status = .{
                .message = status.getMessage(),
                .code = status.getCode(),
            },
        }, .{}),
        .HTML, .UNKNOWN => status.getFormatted(.{ .linebreak = true }),
    };
}

/// Override default template name for a matched route.
pub fn setTemplate(self: *Request, name: []const u8) void {
    self.dynamic_assigned_template = name;
}

pub fn joinPath(self: *const Request, args: anytype) ![]const u8 {
    const fields = std.meta.fields(@TypeOf(args));
    var buf: [fields.len][]const u8 = undefined;
    inline for (fields, 0..) |field, index| {
        buf[index] = switch (@typeInfo(field.type)) {
            .pointer => |info| switch (@typeInfo(info.child)) {
                .@"struct", .@"union" => if (@hasDecl(info.child, "toString"))
                    try args[index].toString()
                else
                    @compileError("Cannot coerce type `" ++ @typeName(field.type) ++ "` to string."),
                else => args[index], // Assume []const u8, let Zig do the work.
            },
            .int, .float => try std.fmt.allocPrint(self.allocator, "{d}", args[index]),
            else => @compileError("Cannot coerce type `" ++ @typeName(field.type) ++ "` to string."),
        };
    }
    return try std.mem.join(self.allocator, "/", buf[0..]);
}

pub fn joinPaths(self: *const Request, paths: []const []const []const u8) ![]const u8 {
    var buf = std.ArrayList([]const u8).init(self.allocator);
    defer buf.deinit();

    for (paths) |subpaths| {
        for (subpaths) |path| try buf.append(path);
    }
    return try std.mem.join(self.allocator, "/", buf.items);
}

pub fn setResponse(
    self: *Request,
    rendered_view: jetzig.http.Server.RenderedView,
    options: struct { content_type: ?[]const u8 = null },
) void {
    self.response.content = rendered_view.content;
    self.response.status_code = rendered_view.view.status_code;
    self.response.content_type = options.content_type orelse switch (self.requestFormat()) {
        .HTML, .UNKNOWN => "text/html",
        .JSON => "application/json",
    };
}

fn setCookieHeaders(self: *Request) !void {
    const local_cookies = self._cookies orelse return;
    if (!local_cookies.modified) return;

    var buf: [4096]u8 = undefined;
    var header_it = local_cookies.headerIterator(&buf);
    while (try header_it.next()) |header| try self.response.headers.append("Set-Cookie", header);
}

// Determine if a given route matches the current request.
pub fn match(self: *Request, route: jetzig.views.Route) !bool {
    return switch (self.method) {
        .GET => switch (route.action) {
            .index => self.isMatch(.exact, route),
            .get => self.isMatch(.resource_id, route),
            .new => self.isMatch(.exact, route),
            else => false,
        },
        .POST => switch (route.action) {
            .post => self.isMatch(.exact, route),
            else => false,
        },
        .PUT => switch (route.action) {
            .put => self.isMatch(.resource_id, route),
            else => false,
        },
        .PATCH => switch (route.action) {
            .patch => self.isMatch(.resource_id, route),
            else => false,
        },
        .DELETE => switch (route.action) {
            .delete => self.isMatch(.resource_id, route),
            else => false,
        },
        .HEAD, .CONNECT, .OPTIONS, .TRACE => false,
    };
}

fn isMatch(self: *Request, match_type: enum { exact, resource_id }, route: jetzig.views.Route) bool {
    const path = switch (match_type) {
        .exact => self.path.base_path,
        .resource_id => self.path.directory,
    };

    if (route.action == .get and std.mem.eql(u8, self.path.resource_id, "new")) return false;

    return std.mem.eql(u8, path, route.uri_path);
}
