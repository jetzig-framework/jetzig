const std = @import("std");
const jetzig = @import("jetzig");
const routes = @import("routes").routes;
const zmpl = @import("zmpl");
const jetzig_options = @import("jetzig_app").jetzig_options;

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

        const layout: ?[]const u8 = if (@hasDecl(static_route.module, "layout"))
            static_route.module.layout
        else
            null;

        const route = jetzig.views.Route{
            .name = static_route.name,
            .action = @field(jetzig.views.Route.Action, static_route.action),
            .view_name = static_route.view_name,
            .view = static_view,
            .static = true,
            .uri_path = static_route.uri_path,
            .layout = layout,
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

    const html_content = try renderZmplTemplate(allocator, route, view) orelse
        try renderMarkdown(allocator, route, view) orelse
        null;
    const html_path = try std.mem.concat(
        allocator,
        u8,
        &[_][]const u8{ route.name, index_suffix, ".html" },
    );
    if (html_content) |content| {
        defer allocator.free(html_path);
        const html_file = try dir.createFile(html_path, .{ .truncate = true });
        try html_file.writeAll(content);
        defer html_file.close();
        allocator.free(content);
        std.debug.print("[jetzig] Compiled static route: {s}\n", .{html_path});
    }
}

fn renderMarkdown(
    allocator: std.mem.Allocator,
    route: jetzig.views.Route,
    view: jetzig.views.View,
) !?[]const u8 {
    const fragments = if (@hasDecl(jetzig_options, "markdown_fragments"))
        jetzig_options.markdown_fragments
    else
        null;
    const path = try std.mem.join(allocator, "/", &[_][]const u8{ route.uri_path, @tagName(route.action) });
    defer allocator.free(path);
    const content = try jetzig.markdown.render(allocator, path, fragments) orelse return null;

    if (route.layout) |layout_name| {
        try view.data.addConst("jetzig_view", view.data.string(route.name));
        try view.data.addConst("jetzig_action", view.data.string(@tagName(route.action)));

        // TODO: Allow user to configure layouts directory other than src/app/views/layouts/
        const prefixed_name = try std.mem.concat(allocator, u8, &[_][]const u8{ "layouts_", layout_name });
        defer allocator.free(prefixed_name);
        defer allocator.free(prefixed_name);

        if (zmpl.find(prefixed_name)) |layout| {
            view.data.content = .{ .data = content };
            return try layout.render(view.data);
        } else {
            std.debug.print("Unknown layout: {s}\n", .{layout_name});
            return content;
        }
    } else return null;
}

fn renderZmplTemplate(
    allocator: std.mem.Allocator,
    route: jetzig.views.Route,
    view: jetzig.views.View,
) !?[]const u8 {
    if (zmpl.find(route.template)) |template| {
        try view.data.addConst("jetzig_view", view.data.string(route.name));
        try view.data.addConst("jetzig_action", view.data.string(@tagName(route.action)));

        if (route.layout) |layout_name| {
            // TODO: Allow user to configure layouts directory other than src/app/views/layouts/
            const prefixed_name = try std.mem.concat(allocator, u8, &[_][]const u8{ "layouts_", layout_name });
            defer allocator.free(prefixed_name);

            if (zmpl.find(prefixed_name)) |layout| {
                return try template.renderWithLayout(layout, view.data);
            } else {
                std.debug.print("Unknown layout: {s}\n", .{layout_name});
                return try allocator.dupe(u8, "");
            }
        } else {
            return try template.render(view.data);
        }
    } else return null;
}
