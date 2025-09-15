const std = @import("std");

const jetzig = @import("../../jetzig.zig");
const view_types = @import("view_types.zig");

const Route = @This();

pub const Action = enum { index, get, new, edit, post, put, patch, delete, custom };

pub const View = union(enum) {
    with_id: view_types.ViewWithId,
    without_id: view_types.ViewWithoutId,
    with_args: view_types.ViewWithArgs,

    static_with_id: view_types.StaticViewWithId,
    static_without_id: view_types.StaticViewWithoutId,
    static_with_args: view_types.StaticViewWithArgs,

    legacy_with_id: view_types.LegacyViewWithId,
    legacy_without_id: view_types.LegacyViewWithoutId,
    legacy_with_args: view_types.LegacyViewWithArgs,

    legacy_static_with_id: view_types.LegacyStaticViewWithId,
    legacy_static_without_id: view_types.LegacyStaticViewWithoutId,
    legacy_static_with_args: view_types.LegacyStaticViewWithArgs,
};

pub const RenderFn = *const fn (Route, *jetzig.http.Request) anyerror!jetzig.views.View;
pub const RenderStaticFn = *const fn (Route, *jetzig.http.StaticRequest) anyerror!jetzig.views.View;

pub const Formats = struct {
    index: ?[]const ResponseFormat = null,
    get: ?[]const ResponseFormat = null,
    new: ?[]const ResponseFormat = null,
    edit: ?[]const ResponseFormat = null,
    post: ?[]const ResponseFormat = null,
    put: ?[]const ResponseFormat = null,
    patch: ?[]const ResponseFormat = null,
    delete: ?[]const ResponseFormat = null,
    custom: ?[]const ResponseFormat = null,
};
const ResponseFormat = enum { html, json };

name: []const u8,
action: Action,
method: jetzig.http.Request.Method = undefined, // Used by custom routes only
view_name: []const u8,
uri_path: []const u8,
path: ?[]const u8 = null,
view: View,
render: RenderFn = renderFn,
renderStatic: RenderStaticFn = renderStaticFn,
static: bool = false,
layout: ?[]const u8 = null,
template: []const u8,
json_params: []const []const u8,
params: std.ArrayList(*jetzig.data.Data) = undefined,
id: []const u8,
formats: ?Formats = null,
before_callbacks: []const jetzig.callbacks.BeforeCallback = &.{},
after_callbacks: []const jetzig.callbacks.AfterCallback = &.{},

/// Initializes a route's static params on server launch. Converts static params (JSON strings)
/// to `jetzig.data.Data` values. Memory is owned by caller (`App.start()`).
pub fn initParams(self: *Route, allocator: std.mem.Allocator) !void {
    self.params = std.ArrayList(*jetzig.data.Data).init(allocator);
    for (self.json_params) |params| {
        var data = try allocator.create(jetzig.data.Data);
        data.* = jetzig.data.Data.init(allocator);
        try self.params.append(data);
        try data.fromJson(params);
    }
}

pub fn deinitParams(self: *const Route) void {
    for (self.params.items) |data| {
        data.deinit();
        data.parent_allocator.destroy(data);
    }
    self.params.deinit();
}

pub fn format(self: Route, _: []const u8, _: anytype, writer: anytype) !void {
    try writer.print(
        \\Route{{ .name = "{s}", .action = .{s}, .view_name = "{s}", .static = {} }}
    ,
        .{ self.name, @tagName(self.action), self.view_name, self.static },
    );
}

/// Match a **custom** route to a request - not used by auto-generated route matching.
pub fn match(self: Route, request: *const jetzig.http.Request) bool {
    if (self.method != request.method) return false;

    var request_path_it = std.mem.splitScalar(u8, request.path.base_path, '/');
    var uri_path_it = std.mem.splitScalar(u8, self.uri_path, '/');

    while (uri_path_it.next()) |expected_segment| {
        const actual_segment = request_path_it.next() orelse return false;
        if (std.mem.startsWith(u8, expected_segment, ":")) {
            if (std.mem.endsWith(u8, expected_segment, "*")) return true;
            continue;
        }
        if (!std.mem.eql(u8, expected_segment, actual_segment)) return false;
    }

    return true;
}

/// Return `true` if a format specification is defined for the current route/view function
/// **and** the format is supported by the current view function, otherwise return `false`.
pub fn validateFormat(self: Route, request: *const jetzig.http.Request) bool {
    const formats = self.formats orelse return true;
    const supported_formats = switch (self.action) {
        .index => formats.index orelse return true,
        .get => formats.get orelse return true,
        .new => formats.new orelse return true,
        .edit => formats.edit orelse return true,
        .post => formats.post orelse return true,
        .put => formats.put orelse return true,
        .patch => formats.patch orelse return true,
        .delete => formats.delete orelse return true,
        .custom => formats.custom orelse return true,
    };

    const request_format = request.requestFormat();
    for (supported_formats) |supported_format| {
        if ((request_format == .HTML or request_format == .UNKNOWN) and supported_format == .html) return true;
        if (request_format == .JSON and supported_format == .json) return true;
    }
    return false;
}

fn renderFn(self: Route, request: *jetzig.http.Request) anyerror!jetzig.views.View {
    return switch (self.view) {
        .with_id => |func| try func(request.path.resource_id, request),
        .without_id => |func| try func(request),
        .with_args => |func| try func(
            try request.path.resourceArgs(self, request.allocator),
            request,
        ),
        .legacy_with_id => |func| try func(
            request.path.resource_id,
            request,
            request.response_data,
        ),
        .legacy_without_id => |func| try func(request, request.response_data),
        .legacy_with_args => |func| try func(
            try request.path.resourceArgs(self, request.allocator),
            request,
            request.response_data,
        ),
        else => unreachable, // renderStaticFn is called for static routes, we can never get here.
    };
}

fn renderStaticFn(self: Route, request: *jetzig.http.StaticRequest) anyerror!jetzig.views.View {
    request.response_data.* = jetzig.data.Data.init(request.allocator);

    return switch (self.view) {
        .static_without_id => |func| try func(request),
        .legacy_static_without_id => |func| try func(request, request.response_data),
        .static_with_id => |func| try func(try request.resourceId(), request),
        .legacy_static_with_id => |func| try func(
            try request.resourceId(),
            request,
            request.response_data,
        ),
        else => unreachable,
    };
}
