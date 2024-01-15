const std = @import("std");

const jetzig = @import("../../jetzig.zig");

const Self = @This();

pub const Action = enum { index, get, post, put, patch, delete };
pub const RenderFn = *const fn (Self, *jetzig.http.Request) anyerror!jetzig.views.View;

const ViewWithoutId = *const fn (*jetzig.http.Request, *jetzig.data.Data) anyerror!jetzig.views.View;
const ViewWithId = *const fn (id: []const u8, *jetzig.http.Request, *jetzig.data.Data) anyerror!jetzig.views.View;

pub const ViewType = union(Action) {
    index: ViewWithoutId,
    get: ViewWithId,
    post: ViewWithoutId,
    put: ViewWithId,
    patch: ViewWithId,
    delete: ViewWithId,
};

name: []const u8,
action: Action,
view: ViewType,
render: RenderFn = renderFn,

pub fn templateName(self: Self, allocator: std.mem.Allocator) ![]const u8 {
    if (std.mem.eql(u8, self.name, "app.views.index") and self.action == .index)
        return try allocator.dupe(u8, "index");

    const underscored_name = try std.mem.replaceOwned(u8, allocator, self.name, ".", "_");
    defer allocator.free(underscored_name);

    // FIXME: Store names in a normalised way so we don't need to do this stuff:
    const unprefixed = try allocator.dupe(u8, underscored_name["app_views_".len..self.name.len]);
    defer allocator.free(unprefixed);

    const suffixed = try std.mem.concat(allocator, u8, &[_][]const u8{
        unprefixed,
        "_",
        @tagName(self.action),
    });

    return suffixed;
}

fn renderFn(self: Self, request: *jetzig.http.Request) anyerror!jetzig.views.View {
    switch (self.view) {
        .index => |view| return try view(request, request.response_data),
        .get => |view| return try view(request.resourceId(), request, request.response_data),
        .post => |view| return try view(request, request.response_data),
        .patch => |view| return try view(request.resourceId(), request, request.response_data),
        .put => |view| return try view(request.resourceId(), request, request.response_data),
        .delete => |view| return try view(request.resourceId(), request, request.response_data),
    }
}
