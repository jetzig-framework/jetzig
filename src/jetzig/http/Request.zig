const std = @import("std");

const jetzig = @import("../../jetzig.zig");

const Self = @This();
const default_content_type = "text/html";

pub const Method = enum { DELETE, GET, PATCH, POST, HEAD, PUT, CONNECT, OPTIONS, TRACE };
pub const Modifier = enum { edit, new };
pub const Format = enum { HTML, JSON, UNKNOWN };

allocator: std.mem.Allocator,
path: jetzig.http.Path,
method: Method,
headers: jetzig.http.Headers,
server: *jetzig.http.Server,
std_http_request: std.http.Server.Request,
response: *jetzig.http.Response,
status_code: jetzig.http.status_codes.StatusCode = undefined,
response_data: *jetzig.data.Data,
query_data: *jetzig.data.Data,
query: *jetzig.http.Query,
cookies: *jetzig.http.Cookies = undefined,
session: *jetzig.http.Session = undefined,
body: []const u8 = undefined,
processed: bool = false,
layout: ?[]const u8 = null,
layout_disabled: bool = false,
rendered: bool = false,
redirected: bool = false,
rendered_multiple: bool = false,
rendered_view: ?jetzig.views.View = null,
start_time: i128,

pub fn init(
    allocator: std.mem.Allocator,
    server: *jetzig.http.Server,
    start_time: i128,
    std_http_request: std.http.Server.Request,
    response: *jetzig.http.Response,
) !Self {
    const method = switch (std_http_request.head.method) {
        .DELETE => Method.DELETE,
        .GET => Method.GET,
        .PATCH => Method.PATCH,
        .POST => Method.POST,
        .HEAD => Method.HEAD,
        .PUT => Method.PUT,
        .CONNECT => Method.CONNECT,
        .OPTIONS => Method.OPTIONS,
        .TRACE => Method.TRACE,
        _ => return error.JetzigUnsupportedHttpMethod,
    };

    const response_data = try allocator.create(jetzig.data.Data);
    response_data.* = jetzig.data.Data.init(allocator);

    const query_data = try allocator.create(jetzig.data.Data);
    query_data.* = jetzig.data.Data.init(allocator);

    const query = try allocator.create(jetzig.http.Query);

    return .{
        .allocator = allocator,
        .path = jetzig.http.Path.init(std_http_request.head.target),
        .method = method,
        .headers = jetzig.http.Headers.init(allocator),
        .server = server,
        .response = response,
        .response_data = response_data,
        .query_data = query_data,
        .query = query,
        .std_http_request = std_http_request,
        .start_time = start_time,
    };
}

pub fn deinit(self: *Self) void {
    // self.session.deinit();
    self.allocator.destroy(self.cookies);
    self.allocator.destroy(self.session);
    if (self.processed) self.allocator.free(self.body);
}

/// Process request, read body if present, parse headers (TODO)
pub fn process(self: *Self) !void {
    var headers_it = self.std_http_request.iterateHeaders();
    var cookie: ?[]const u8 = null;

    while (headers_it.next()) |header| {
        try self.headers.append(header.name, header.value);
        if (std.mem.eql(u8, header.name, "Cookie")) cookie = header.value;
    }

    self.cookies = try self.allocator.create(jetzig.http.Cookies);
    self.cookies.* = jetzig.http.Cookies.init(
        self.allocator,
        cookie orelse "",
    );
    try self.cookies.parse();

    self.session = try self.allocator.create(jetzig.http.Session);
    self.session.* = jetzig.http.Session.init(self.allocator, self.cookies, self.server.options.secret);
    self.session.parse() catch |err| {
        switch (err) {
            error.JetzigInvalidSessionCookie => {
                try self.server.logger.DEBUG("Invalid session cookie detected. Resetting session.", .{});
                try self.session.reset();
            },
            else => return err,
        }
    };

    const reader = try self.std_http_request.reader();
    self.body = try reader.readAllAlloc(self.allocator, jetzig.config.get(usize, "max_bytes_request_body"));
    self.processed = true;
}

/// Set response headers, write response payload, and finalize the response.
pub fn respond(self: *Self) !void {
    if (!self.processed) unreachable;

    var cookie_it = self.cookies.headerIterator();
    while (try cookie_it.next()) |header| {
        // FIXME: Skip setting cookies that are already present ?
        try self.response.headers.append("Set-Cookie", header);
    }

    var std_response_headers = try self.response.headers.stdHeaders();
    defer std_response_headers.deinit(self.allocator);

    try self.std_http_request.respond(
        self.response.content,
        .{
            .keep_alive = false,
            .status = switch (self.response.status_code) {
                inline else => |tag| @field(std.http.Status, @tagName(tag)),
            },
            .extra_headers = std_response_headers.items,
        },
    );
}

/// Render a response. This function can only be called once per request (repeat calls will
/// trigger an error).
pub fn render(self: *Self, status_code: jetzig.http.status_codes.StatusCode) jetzig.views.View {
    if (self.rendered) self.rendered_multiple = true;

    self.rendered = true;
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
    self: *Self,
    location: []const u8,
    redirect_status: enum { moved_permanently, found },
) jetzig.views.View {
    if (self.rendered) self.rendered_multiple = true;

    self.rendered = true;
    self.redirected = true;

    const status_code = switch (redirect_status) {
        .moved_permanently => jetzig.http.status_codes.StatusCode.moved_permanently,
        .found => jetzig.http.status_codes.StatusCode.found,
    };

    self.response_data.reset();

    self.response.headers.remove("Location");
    self.response.headers.append("Location", location) catch @panic("OOM");

    self.rendered_view = .{ .data = self.response_data, .status_code = status_code };
    return self.rendered_view.?;
}

/// Infer the current format (JSON or HTML) from the request in this order:
/// * Extension (path ends in `.json` or `.html`)
/// * `Accept` header (`application/json` or `text/html`)
/// * `Content-Type` header (`application/json` or `text/html`)
/// * Fall back to default: HTML
pub fn requestFormat(self: *Self) jetzig.http.Request.Format {
    return self.extensionFormat() orelse
        self.acceptHeaderFormat() orelse
        self.contentTypeHeaderFormat() orelse
        .UNKNOWN;
}

/// Set the layout for the current request/response. Use this to override a `pub const layout`
/// declaration in a view, either in middleware or in a view function itself.
pub fn setLayout(self: *Self, layout: ?[]const u8) void {
    if (layout) |layout_name| {
        self.layout = layout_name;
        self.layout_disabled = false;
    } else {
        self.layout_disabled = true;
    }
}

/// Derive a layout name from the current request if defined, otherwise from the route (if
/// defined).
pub fn getLayout(self: *Self, route: *jetzig.views.Route) ?[]const u8 {
    if (self.layout_disabled) return null;
    if (self.layout) |capture| return capture;
    if (route.layout) |capture| return capture;

    return null;
}

/// Shortcut for `request.headers.getFirstValue`. Returns the first matching value for a given
/// header name or `null` if not found. Header names are case-insensitive.
pub fn getHeader(self: *Self, key: []const u8) ?[]const u8 {
    return self.headers.getFirstValue(key);
}

/// Return a `Value` representing request parameters. Parameters are normalized, meaning that
/// both the JSON request body and query parameters are accessed via the same interface.
/// Note that query parameters are supported for JSON requests if no request body is present,
/// otherwise the parsed JSON request body will take precedence and query parameters will be
/// ignored.
pub fn params(self: *Self) !*jetzig.data.Value {
    if (!self.processed) unreachable;

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
        .HTML, .UNKNOWN => return self.queryParams(),
    }
}

fn queryParams(self: *Self) !*jetzig.data.Value {
    if (!try self.parseQueryString()) {
        self.query.data = try self.allocator.create(jetzig.data.Data);
        self.query.data.* = jetzig.data.Data.init(self.allocator);
        _ = try self.query.data.object();
    }
    return self.query.data.value.?;
}

fn parseQueryString(self: *Self) !bool {
    if (self.path.query) |query| {
        self.query.* = jetzig.http.Query.init(
            self.allocator,
            query,
            self.query_data,
        );
        try self.query.parse();
        return true;
    }

    return false;
}

fn extensionFormat(self: *Self) ?jetzig.http.Request.Format {
    const extension = self.path.extension orelse return null;

    if (std.mem.eql(u8, extension, ".html")) {
        return .HTML;
    } else if (std.mem.eql(u8, extension, ".json")) {
        return .JSON;
    } else {
        return null;
    }
}

pub fn acceptHeaderFormat(self: *Self) ?jetzig.http.Request.Format {
    const acceptHeader = self.getHeader("Accept");

    if (acceptHeader) |item| {
        if (std.mem.eql(u8, item, "text/html")) return .HTML;
        if (std.mem.eql(u8, item, "application/json")) return .JSON;
    }

    return null;
}

pub fn contentTypeHeaderFormat(self: *Self) ?jetzig.http.Request.Format {
    const acceptHeader = self.getHeader("content-type");

    if (acceptHeader) |item| {
        if (std.mem.eql(u8, item, "text/html")) return .HTML;
        if (std.mem.eql(u8, item, "application/json")) return .JSON;
    }

    return null;
}

pub fn hash(self: *Self) ![]const u8 {
    return try std.fmt.allocPrint(
        self.allocator,
        "{s}-{s}-{s}",
        .{ @tagName(self.method), self.path, @tagName(self.requestFormat()) },
    );
}

pub fn fmtMethod(self: *const Self, colorized: bool) []const u8 {
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

// Determine if a given route matches the current request.
pub fn match(self: *Self, route: jetzig.views.Route) !bool {
    return switch (self.method) {
        .GET => switch (route.action) {
            .index => self.isMatch(.exact, route),
            .get => self.isMatch(.resource_id, route),
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

fn isMatch(self: *Self, match_type: enum { exact, resource_id }, route: jetzig.views.Route) bool {
    const path = switch (match_type) {
        .exact => self.path.base_path,
        .resource_id => self.path.directory,
    };

    return std.mem.eql(u8, path, route.uri_path);
}
