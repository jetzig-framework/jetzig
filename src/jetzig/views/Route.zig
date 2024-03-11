const std = @import("std");

const jetzig = @import("../../jetzig.zig");

const Self = @This();

pub const Action = enum { index, get, post, put, patch, delete };
pub const RenderFn = *const fn (Self, *jetzig.http.Request) anyerror!jetzig.views.View;
pub const RenderStaticFn = *const fn (Self, *jetzig.http.StaticRequest) anyerror!jetzig.views.View;

const ViewWithoutId = *const fn (*jetzig.http.Request, *jetzig.data.Data) anyerror!jetzig.views.View;
const ViewWithId = *const fn (id: []const u8, *jetzig.http.Request, *jetzig.data.Data) anyerror!jetzig.views.View;
const StaticViewWithoutId = *const fn (*jetzig.http.StaticRequest, *jetzig.data.Data) anyerror!jetzig.views.View;
const StaticViewWithId = *const fn (id: []const u8, *jetzig.http.StaticRequest, *jetzig.data.Data) anyerror!jetzig.views.View;

pub const DynamicViewType = union(Action) {
    index: ViewWithoutId,
    get: ViewWithId,
    post: ViewWithoutId,
    put: ViewWithId,
    patch: ViewWithId,
    delete: ViewWithId,
};

pub const StaticViewType = union(Action) {
    index: StaticViewWithoutId,
    get: StaticViewWithId,
    post: StaticViewWithoutId,
    put: StaticViewWithId,
    patch: StaticViewWithId,
    delete: StaticViewWithId,
};

pub const ViewType = union(enum) {
    static: StaticViewType,
    dynamic: DynamicViewType,
};

name: []const u8,
action: Action,
uri_path: []const u8,
view: ?ViewType = null,
static_view: ?StaticViewType = null,
static: bool,
render: RenderFn = renderFn,
renderStatic: RenderStaticFn = renderStaticFn,
layout: ?[]const u8,
template: []const u8,
json_params: [][]const u8,
params: std.ArrayList(*jetzig.data.Data) = undefined,

/// Initializes a route's static params on server launch. Converts static params (JSON strings)
/// to `jetzig.data.Data` values. Memory is owned by caller (`App.start()`).
pub fn initParams(self: *Self, allocator: std.mem.Allocator) !void {
    self.params = std.ArrayList(*jetzig.data.Data).init(allocator);
    for (self.json_params) |params| {
        var data = try allocator.create(jetzig.data.Data);
        data.* = jetzig.data.Data.init(allocator);
        try self.params.append(data);
        try data.fromJson(params);
    }
}

pub fn deinitParams(self: *const Self) void {
    for (self.params.items) |data| {
        data.deinit();
        data._allocator.destroy(data);
    }
    self.params.deinit();
}

fn renderFn(self: Self, request: *jetzig.http.Request) anyerror!jetzig.views.View {
    switch (self.view.?) {
        .dynamic => {},
        // We only end up here if a static route is defined but its output is not found in the
        // file system (e.g. if it was manually deleted after build). This should be avoidable by
        // including the content as an artifact in the compiled executable (TODO):
        .static => return error.JetzigMissingStaticContent,
    }

    switch (self.view.?.dynamic) {
        .index => |view| return try view(request, request.response_data),
        .get => |view| return try view(request.resourceId(), request, request.response_data),
        .post => |view| return try view(request, request.response_data),
        .patch => |view| return try view(request.resourceId(), request, request.response_data),
        .put => |view| return try view(request.resourceId(), request, request.response_data),
        .delete => |view| return try view(request.resourceId(), request, request.response_data),
    }
}

fn renderStaticFn(self: Self, request: *jetzig.http.StaticRequest) anyerror!jetzig.views.View {
    request.response_data.* = jetzig.data.Data.init(request.allocator);

    switch (self.view.?.static) {
        .index => |view| return try view(request, request.response_data),
        .get => |view| return try view(try request.resourceId(), request, request.response_data),
        .post => |view| return try view(request, request.response_data),
        .patch => |view| return try view(try request.resourceId(), request, request.response_data),
        .put => |view| return try view(try request.resourceId(), request, request.response_data),
        .delete => |view| return try view(try request.resourceId(), request, request.response_data),
    }
}
