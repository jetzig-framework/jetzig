const std = @import("std");

const root = @import("root");

const Self = @This();
const default_content_type = "text/html";

pub const Method = enum { DELETE, GET, PATCH, POST, HEAD, PUT, CONNECT, OPTIONS, TRACE };
pub const Modifier = enum { edit, new };
pub const Format = enum { HTML, JSON, UNKNOWN };

allocator: std.mem.Allocator,
path: []const u8,
method: Method,
headers: std.http.Headers,
segments: std.ArrayList([]const u8),
server: *root.jetzig.http.Server,
status_code: root.jetzig.http.status_codes.StatusCode = undefined,
response_data: root.jetzig.views.data.Data = undefined,

pub fn init(
    allocator: std.mem.Allocator,
    server: *root.jetzig.http.Server,
    request: std.http.Server.Request,
) !Self {
    const method = switch (request.method) {
        .DELETE => Method.DELETE,
        .GET => Method.GET,
        .PATCH => Method.PATCH,
        .POST => Method.POST,
        .HEAD => Method.HEAD,
        .PUT => Method.PUT,
        .CONNECT => Method.CONNECT,
        .OPTIONS => Method.OPTIONS,
        .TRACE => Method.TRACE,
    };

    var it = std.mem.splitScalar(u8, request.target, '/');
    var segments = std.ArrayList([]const u8).init(allocator);
    while (it.next()) |segment| try segments.append(segment);

    return .{
        .allocator = allocator,
        .path = request.target,
        .method = method,
        .headers = request.headers,
        .server = server,
        .segments = segments,
    };
}

pub fn deinit(self: *Self) void {
    defer self.segments.deinit();
}

pub fn render(self: *Self, status_code: root.jetzig.http.status_codes.StatusCode) root.jetzig.views.View {
    return .{ .data = &self.response_data, .status_code = status_code };
}

pub fn requestFormat(self: *Self) root.jetzig.http.Request.Format {
    return self.extensionFormat() orelse self.acceptHeaderFormat() orelse .UNKNOWN;
}

pub fn getHeader(self: *Self, key: []const u8) ?[]const u8 {
    return self.headers.getFirstValue(key);
}

fn extensionFormat(self: *Self) ?root.jetzig.http.Request.Format {
    const extension = std.fs.path.extension(self.path);

    if (std.mem.eql(u8, extension, ".html")) {
        return .HTML;
    } else if (std.mem.eql(u8, extension, ".json")) {
        return .JSON;
    } else {
        return null;
    }
}

pub fn acceptHeaderFormat(self: *Self) ?root.jetzig.http.Request.Format {
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

pub fn fullPath(self: *Self) ![]const u8 {
    const base_path = try std.fs.path.join(self.allocator, &[_][]const u8{
        self.server.options.root_path,
        "views",
    });
    defer self.allocator.free(base_path);

    const resource_path = try self.resourcePath();
    defer self.allocator.free(resource_path);
    const full_path = try std.fs.path.join(self.allocator, &[_][]const u8{
        base_path,
        resource_path,
        self.resourceName(),
        self.templateName(),
    });
    defer self.allocator.free(full_path);
    return self.allocator.dupe(u8, full_path);
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

pub fn match(self: *Self, route: root.jetzig.views.Route) !bool {
    switch (self.method) {
        .GET => {
            return switch (route.action) {
                .index => std.mem.eql(u8, try self.nameWithResourceId(), route.name),
                .get => std.mem.eql(u8, try self.nameWithoutResourceId(), route.name),
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

pub fn data(self: *Self) *root.jetzig.views.data.Data {
    self.response_data = root.jetzig.views.data.Data.init(self.allocator);
    return &self.response_data;
}

fn templateName(self: *Self) []const u8 {
    switch (self.method) {
        .GET => return "index.html.zmpl",
        .SHOW => return "[id].html.zmpl",
        else => unreachable, // TODO: Missing HTTP verbs.
    }
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

fn nameWithResourceId(self: *Self) ![]const u8 {
    return try self.name(true);
}

fn nameWithoutResourceId(self: *Self) ![]const u8 {
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
