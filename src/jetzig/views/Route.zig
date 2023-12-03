const std = @import("std");

const root = @import("root");

const Self = @This();

pub const Action = enum { index, get, post, put, patch, delete };
pub const RenderFn = *const fn (Self, *root.jetzig.http.Request) anyerror!root.jetzig.views.View;

const ViewWithoutId = *const fn (*root.jetzig.http.Request) anyerror!root.jetzig.views.View;
const ViewWithId = *const fn (id: []const u8, *root.jetzig.http.Request) anyerror!root.jetzig.views.View;

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
    const underscored_name = try std.mem.replaceOwned(u8, allocator, self.name, ".", "_");
    defer allocator.free(underscored_name);

    // FIXME: Store names in a normalised way so we don't need to do this stuff:
    const unprefixed = try allocator.dupe(u8, underscored_name["app_views_".len..self.name.len]);
    defer allocator.free(unprefixed);

    const suffixed = try std.mem.concat(allocator, u8, &[_][]const u8{
        unprefixed,
        "_",
        switch (self.action) {
            .get => "get_id",
            else => @tagName(self.action),
        },
    });

    return suffixed;
}

fn renderFn(self: Self, request: *root.jetzig.http.Request) anyerror!root.jetzig.views.View {
    switch (self.view) {
        .index => |view| return try view(request),
        .get => |view| return try view(request.resourceId(), request),
        .post => |view| return try view(request),
        .patch => |view| return try view(request.resourceId(), request),
        .put => |view| return try view(request.resourceId(), request),
        .delete => |view| return try view(request.resourceId(), request),
    }
}
