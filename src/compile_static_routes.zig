const std = @import("std");
const jetzig = @import("jetzig");
const routes = @import("routes").routes;
const templates = @import("templates").templates;

pub fn main() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer std.debug.assert(gpa.deinit() == .ok);
    const gpa_allocator = gpa.allocator();

    var arena = std.heap.ArenaAllocator.init(gpa_allocator);
    const allocator = arena.allocator();
    defer arena.deinit();

    try compileStaticRoutes(allocator);
}

fn compileStaticRoutes(allocator: std.mem.Allocator) !void {
    std.fs.cwd().deleteTree("static") catch {};

    inline for (routes.static) |static_route| {
        const static_view = jetzig.views.Route.ViewType{
            .static = @unionInit(
                jetzig.views.Route.StaticViewType,
                static_route.action,
                static_route.function,
            ),
        };

        comptime var static_params_len = 0;
        inline for (static_route.params) |_| static_params_len += 1;
        comptime var params: [static_params_len][]const u8 = undefined;
        inline for (static_route.params, 0..) |json, index| params[index] = json;

        const route = jetzig.views.Route{
            .name = static_route.name,
            .action = @field(jetzig.views.Route.Action, static_route.action),
            .view = static_view,
            .static = true,
            .uri_path = static_route.uri_path,
            .template = static_route.template,
            .json_params = &params,
        };

        if (static_params_len > 0) {
            inline for (static_route.params, 0..) |json, index| {
                var request = try jetzig.http.StaticRequest.init(allocator, json);
                defer request.deinit();
                try writeContent(allocator, route, &request, index);
            }
        }

        // Always provide a fallback for non-resource routes (i.e. `index`, `post`) if params
        // do not match any of the configured param sets.
        switch (route.action) {
            .index, .post => {
                var request = try jetzig.http.StaticRequest.init(allocator, "{}");
                defer request.deinit();
                try writeContent(allocator, route, &request, null);
            },
            inline else => {},
        }
    }
}

fn writeContent(
    allocator: std.mem.Allocator,
    comptime route: jetzig.views.Route,
    request: *jetzig.http.StaticRequest,
    index: ?usize,
) !void {
    const index_suffix = if (index) |capture|
        try std.fmt.allocPrint(allocator, "_{}", .{capture})
    else
        try allocator.dupe(u8, "");
    defer allocator.free(index_suffix);

    const view = try route.renderStatic(route, request);
    defer view.deinit();

    var dir = try std.fs.cwd().makeOpenPath("static", .{});
    defer dir.close();

    const json_path = try std.mem.concat(
        allocator,
        u8,
        &[_][]const u8{ route.name, index_suffix, ".json" },
    );
    defer allocator.free(json_path);

    const json_file = try dir.createFile(json_path, .{ .truncate = true });
    try json_file.writeAll(try view.data.toJson());
    defer json_file.close();

    std.debug.print("[jetzig] Compiled static route: {s}\n", .{json_path});

    if (@hasDecl(templates, route.template)) {
        const template = @field(templates, route.template);
        const html_path = try std.mem.concat(
            allocator,
            u8,
            &[_][]const u8{ route.name, index_suffix, ".html" },
        );
        defer allocator.free(html_path);
        const html_file = try dir.createFile(html_path, .{ .truncate = true });
        try html_file.writeAll(try template.render(view.data));
        defer html_file.close();
        std.debug.print("[jetzig] Compiled static route: {s}\n", .{html_path});
    }
}
