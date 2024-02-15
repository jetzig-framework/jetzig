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
status_code: jetzig.http.status_codes.StatusCode = undefined,
response_data: *jetzig.data.Data,
cookies: *jetzig.http.Cookies,

pub fn init(
    allocator: std.mem.Allocator,
    server: *jetzig.http.Server,
    response: *std.http.Server.Response,
) !Self {
    const method = switch (response.request.method) {
        .DELETE => Method.DELETE,
        .GET => Method.GET,
        .PATCH => Method.PATCH,
        .POST => Method.POST,
        .HEAD => Method.HEAD,
        .PUT => Method.PUT,
        .CONNECT => Method.CONNECT,
        .OPTIONS => Method.OPTIONS,
        .TRACE => Method.TRACE,
        _ => return error.jetzig_unsupported_http_method,
    };

    var it = std.mem.splitScalar(u8, response.request.target, '/');
    var segments = std.ArrayList([]const u8).init(allocator);
    while (it.next()) |segment| try segments.append(segment);

    var cookies = try allocator.create(jetzig.http.Cookies);
    cookies.* = jetzig.http.Cookies.init(
        allocator,
        response.request.headers.getFirstValue("Cookie") orelse "",
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

    return .{
        .allocator = allocator,
        .path = response.request.target,
        .method = method,
        .headers = jetzig.http.Headers.init(allocator, response.request.headers),
        .server = server,
        .segments = segments,
        .cookies = cookies,
        .session = session,
        .response_data = response_data,
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
    const basename = std.fs.path.basename(self.segments.items[self.segments.items.len - 1]);
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

pub fn resourceId(self: *Self) []const u8 {
    return self.resourceName();
}

pub fn match(self: *Self, route: jetzig.views.Route) !bool {
    switch (self.method) {
        .GET => {
            return switch (route.action) {
                .index => blk: {
                    if (std.mem.eql(u8, self.path, "/") and std.mem.eql(u8, route.name, "app.views.index")) {
                        break :blk true;
                    } else {
                        break :blk std.mem.eql(u8, try self.fullName(), route.name);
                    }
                },
                .get => std.mem.eql(u8, try self.fullNameWithStrippedResourceId(), route.name),
                else => false,
            };
        },
        .POST => return route.action == .post,
        .PUT => return route.action == .put,
        .PATCH => return route.action == .patch,
        .DELETE => return route.action == .delete,
        else => return false,
    }

    return false;
}

fn isEditAction(self: *Self) bool {
    if (self.resourceModifier()) |modifier| {
        return modifier == .edit;
    } else return false;
}

fn isNewAction(self: *Self) bool {
    if (self.resourceModifier()) |modifier| {
        return modifier == .new;
    } else return false;
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
        ".",
        self.segments.items[0 .. self.segments.items.len - 1],
    );
    defer self.allocator.free(dirname);

    return std.mem.concat(self.allocator, u8, &[_][]const u8{
        "app.views",
        dirname,
        if (with_resource_id) "." else "",
        if (with_resource_id) self.resourceName() else "",
    });
}
