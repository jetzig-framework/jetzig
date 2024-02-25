const std = @import("std");

const jetzig = @import("../../jetzig.zig");

const Self = @This();
const default_content_type = "text/html";

pub const Method = enum { DELETE, GET, PATCH, POST, HEAD, PUT, CONNECT, OPTIONS, TRACE };
pub const Modifier = enum { edit, new };
pub const Format = enum { HTML, JSON, UNKNOWN };

allocator: std.mem.Allocator,
path: []const u8,
method: Method,
headers: jetzig.http.Headers,
segments: std.ArrayList([]const u8),
server: *jetzig.http.Server,
session: *jetzig.http.Session,
response: *jetzig.http.Response,
status_code: jetzig.http.status_codes.StatusCode = undefined,
response_data: *jetzig.data.Data,
query_data: *jetzig.data.Data,
query: *jetzig.http.Query,
cookies: *jetzig.http.Cookies,
body: []const u8,

pub fn init(
    allocator: std.mem.Allocator,
    server: *jetzig.http.Server,
    response: *jetzig.http.Response,
    body: []const u8,
) !Self {
    const method = switch (response.std_response.request.method) {
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

    // TODO: Replace all this with a `Path` type which exposes all components of the path in a
    // sensible way:
    // * Array of segments: "/foo/bar/baz" => .{ "foo", "bar", "baz" }
    // * Resource ID: "/foo/bar/baz/1" => "1"
    // * Extension: "/foo/bar/baz/1.json" => ".json"
    // * Query params: "/foo/bar/baz?foo=bar&baz=qux" => .{ .foo = "bar", .baz => "qux" }
    // * Anything else ?
    var it = std.mem.splitScalar(u8, response.std_response.request.target, '/');
    var segments = std.ArrayList([]const u8).init(allocator);
    while (it.next()) |segment| {
        if (std.mem.indexOfScalar(u8, segment, '?')) |query_index| {
            try segments.append(segment[0..query_index]);
        } else {
            try segments.append(segment);
        }
    }

    var cookies = try allocator.create(jetzig.http.Cookies);
    cookies.* = jetzig.http.Cookies.init(
        allocator,
        response.std_response.request.headers.getFirstValue("Cookie") orelse "",
    );
    try cookies.parse();

    var session = try allocator.create(jetzig.http.Session);
    session.* = jetzig.http.Session.init(allocator, cookies, server.options.secret);
    session.parse() catch |err| {
        switch (err) {
            error.JetzigInvalidSessionCookie => {
                server.logger.debug("Invalid session cookie detected. Resetting session.", .{});
                try session.reset();
            },
            else => return err,
        }
    };

    const response_data = try allocator.create(jetzig.data.Data);
    response_data.* = jetzig.data.Data.init(allocator);

    const query_data = try allocator.create(jetzig.data.Data);
    query_data.* = jetzig.data.Data.init(allocator);

    const query = try allocator.create(jetzig.http.Query);

    return .{
        .allocator = allocator,
        .path = response.std_response.request.target,
        .method = method,
        .headers = jetzig.http.Headers.init(allocator, response.std_response.request.headers),
        .server = server,
        .segments = segments,
        .cookies = cookies,
        .session = session,
        .response_data = response_data,
        .query_data = query_data,
        .query = query,
        .body = body,
        .response = response,
    };
}

pub fn deinit(self: *Self) void {
    self.session.deinit();
    self.segments.deinit();
    self.allocator.destroy(self.cookies);
    self.allocator.destroy(self.session);
}

pub fn render(self: *Self, status_code: jetzig.http.status_codes.StatusCode) jetzig.views.View {
    return .{ .data = self.response_data, .status_code = status_code };
}

pub fn requestFormat(self: *Self) jetzig.http.Request.Format {
    return self.extensionFormat() orelse self.acceptHeaderFormat() orelse .UNKNOWN;
}

pub fn getHeader(self: *Self, key: []const u8) ?[]const u8 {
    return self.headers.getFirstValue(key);
}

/// Provides a `Value` representing request parameters. Parameters are normalized, meaning that
/// both the JSON request body and query parameters are accessed via the same interface.
/// Note that query parameters are supported for JSON requests if no request body is present,
/// otherwise the parsed JSON request body will take precedence and query parameters will be
/// ignored.
pub fn params(self: *Self) !*jetzig.data.Value {
    switch (self.requestFormat()) {
        .JSON => {
            if (self.body.len == 0) return self.queryParams();

            var data = try self.allocator.create(jetzig.data.Data);
            data.* = jetzig.data.Data.init(self.allocator);
            data.fromJson(self.body) catch |err| {
                switch (err) {
                    error.UnexpectedEndOfInput => return error.JetzigBodyParseError,
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
    const delimiter_index = std.mem.indexOfScalar(u8, self.path, '?');
    if (delimiter_index) |index| {
        if (self.path.len - 1 < index + 1) return false;

        self.query.* = jetzig.http.Query.init(
            self.allocator,
            self.path[index + 1 ..],
            self.query_data,
        );
        try self.query.parse();
        return true;
    }

    return false;
}

fn extensionFormat(self: *Self) ?jetzig.http.Request.Format {
    const extension = std.fs.path.extension(self.path);

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

pub fn hash(self: *Self) ![]const u8 {
    return try std.fmt.allocPrint(
        self.allocator,
        "{s}-{s}-{s}",
        .{ @tagName(self.method), self.path, @tagName(self.requestFormat()) },
    );
}

pub fn fmtMethod(self: *Self) []const u8 {
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

pub fn resourceModifier(self: *Self) ?Modifier {
    const basename = std.fs.path.basename(self.segments.items[self.segments.items.len - 1]);
    const extension = std.fs.path.extension(basename);
    const resource = basename[0 .. basename.len - extension.len];
    if (std.mem.eql(u8, resource, "edit")) return .edit;
    if (std.mem.eql(u8, resource, "new")) return .new;

    return null;
}

pub fn resourceName(self: *Self) []const u8 {
    if (self.segments.items.len == 0) return "default"; // Should never happen ?

    const basename = std.fs.path.basename(self.segments.items[self.segments.items.len - 1]);
    if (std.mem.indexOfScalar(u8, basename, '?')) |index| {
        return basename[0..index];
    }
    const extension = std.fs.path.extension(basename);
    return basename[0 .. basename.len - extension.len];
}

pub fn resourcePath(self: *Self) ![]const u8 {
    const path = try std.fs.path.join(
        self.allocator,
        self.segments.items[0 .. self.segments.items.len - 1],
    );
    defer self.allocator.free(path);
    return try std.mem.concat(self.allocator, u8, &[_][]const u8{ "/", path });
}

/// For a path `/foo/bar/baz/123.json`, returns `"123"`.
pub fn resourceId(self: *Self) []const u8 {
    return self.resourceName();
}

// Determine if a given route matches the current request.
pub fn match(self: *Self, route: jetzig.views.Route) !bool {
    switch (self.method) {
        .GET => {
            return switch (route.action) {
                .index => self.isMatch(.exact, route),
                .get => self.isMatch(.resource_id, route),
                else => false,
            };
        },
        .POST => return self.isMatch(.exact, route),
        .PUT => return self.isMatch(.resource_id, route),
        .PATCH => return self.isMatch(.resource_id, route),
        .DELETE => return self.isMatch(.resource_id, route),
        else => return false,
    }

    return false;
}

fn isMatch(self: *Self, match_type: enum { exact, resource_id }, route: jetzig.views.Route) bool {
    const path = switch (match_type) {
        .exact => self.pathWithoutExtension(),
        .resource_id => self.pathWithoutExtensionAndResourceId(),
    };

    return std.mem.eql(u8, path, route.uri_path);
}

// TODO: Be a bit more deterministic in identifying extension, e.g. deal with `.` characters
// elsewhere in the path (e.g. in query string).
fn pathWithoutExtension(self: *Self) []const u8 {
    const extension_index = std.mem.lastIndexOfScalar(u8, self.path, '.');
    if (extension_index) |capture| return self.path[0..capture];

    const query_index = std.mem.indexOfScalar(u8, self.path, '?');
    if (query_index) |capture| return self.path[0..capture];

    return self.path;
}

fn pathWithoutExtensionAndResourceId(self: *Self) []const u8 {
    const path = self.pathWithoutExtension();
    const index = std.mem.lastIndexOfScalar(u8, self.path, '/');
    if (index) |capture| {
        if (capture == 0) return "/";
        return path[0..capture];
    } else {
        return path;
    }
}

fn fullName(self: *Self) ![]const u8 {
    return try self.name(true);
}

fn fullNameWithStrippedResourceId(self: *Self) ![]const u8 {
    return try self.name(false);
}

fn name(self: *Self, with_resource_id: bool) ![]const u8 {
    const dirname = try std.mem.join(
        self.allocator,
        "_",
        self.segments.items[0 .. self.segments.items.len - 1],
    );
    defer self.allocator.free(dirname);

    return std.mem.concat(self.allocator, u8, &[_][]const u8{
        dirname,
        if (with_resource_id) "." else "",
        if (with_resource_id) self.resourceName() else "",
    });
}
