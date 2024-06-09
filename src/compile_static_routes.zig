const std = @import("std");
const jetzig = @import("jetzig");
const routes = @import("routes").routes;
const zmpl = @import("zmpl");
const markdown_fragments = @import("markdown_fragments");
// const jetzig_options = @import("jetzig_app").jetzig_options;

pub fn main() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer std.debug.assert(gpa.deinit() == .ok);
    const gpa_allocator = gpa.allocator();

    var arena = std.heap.ArenaAllocator.init(gpa_allocator);
    const allocator = arena.allocator();
    defer arena.deinit();

    var it = try std.process.argsWithAllocator(allocator);
    var index: usize = 0;
    while (it.next()) |arg| : (index += 1) {
        if (index == 0) continue;
        const file = try std.fs.createFileAbsolute(arg, .{});
        const writer = file.writer();
        try compileStaticRoutes(allocator, writer);
        file.close();
        break;
    }
}

fn compileStaticRoutes(allocator: std.mem.Allocator, writer: anytype) !void {
    var count: usize = 0;

    try writer.writeAll(
        \\const StaticOutput = struct { json: ?[]const u8 = null, html: ?[]const u8 = null, params: ?[]const u8 };
        \\const Compiled = struct { route_id: []const u8, output: StaticOutput };
        \\pub const compiled = [_]Compiled{
        \\
    );
    for (routes) |route| {
        if (!route.static) continue;

        if (route.json_params.len > 0) {
            for (route.json_params, 0..) |json, index| {
                var request = try jetzig.http.StaticRequest.init(allocator, json);
                defer request.deinit();
                try writeContent(allocator, writer, route, &request, index, &count, json);
            }
        }

        // Always provide a fallback for non-resource routes (i.e. `index`, `post`) if params
        // do not match any of the configured param sets.
        switch (route.action) {
            .index, .post => {
                var request = try jetzig.http.StaticRequest.init(allocator, "{}");
                defer request.deinit();
                try writeContent(allocator, writer, route, &request, null, &count, null);
            },
            inline else => {},
        }
    }

    try writer.writeAll(
        \\};
        \\
    );
    std.debug.print("[jetzig] Compiled {} static output(s)\n", .{count});
}

fn writeContent(
    allocator: std.mem.Allocator,
    writer: anytype,
    route: jetzig.views.Route,
    request: *jetzig.http.StaticRequest,
    index: ?usize,
    count: *usize,
    params_json: ?[]const u8,
) !void {
    const index_suffix = if (index) |capture|
        try std.fmt.allocPrint(allocator, "_{}", .{capture})
    else
        try allocator.dupe(u8, "");
    defer allocator.free(index_suffix);

    const view = try route.renderStatic(route, request);
    defer view.deinit();

    count.* += 1;

    const html_content = try renderZmplTemplate(allocator, route, view) orelse
        try renderMarkdown(allocator, route, view) orelse
        null;

    try writer.print(
        \\.{{ .route_id = "{s}", .output = StaticOutput{{ .json = "{s}", .html = "{s}", .params = {s}{s}{s} }} }},
        \\
        \\
    ,
        .{
            route.id,
            try zigEscape(allocator, try view.data.toJson()),
            try zigEscape(allocator, html_content orelse ""),
            if (params_json) |_| "\"" else "",
            if (params_json) |params| try zigEscape(allocator, params) else "null",
            if (params_json) |_| "\"" else "",
        },
    );

    if (html_content) |content| {
        allocator.free(content);
        count.* += 1;
    }
}

fn renderMarkdown(
    allocator: std.mem.Allocator,
    route: jetzig.views.Route,
    view: jetzig.views.View,
) !?[]const u8 {
    const path = try std.mem.join(allocator, "/", &[_][]const u8{ route.uri_path, @tagName(route.action) });
    defer allocator.free(path);
    const content = try jetzig.markdown.render(allocator, path, markdown_fragments) orelse return null;

    if (route.layout) |layout_name| {
        try view.data.addConst("jetzig_view", view.data.string(route.name));
        try view.data.addConst("jetzig_action", view.data.string(@tagName(route.action)));

        // TODO: Allow user to configure layouts directory other than src/app/views/layouts/
        const prefixed_name = try std.mem.concat(allocator, u8, &[_][]const u8{ "layouts_", layout_name });
        defer allocator.free(prefixed_name);
        defer allocator.free(prefixed_name);

        if (zmpl.findPrefixed("views", prefixed_name)) |layout| {
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
    if (zmpl.findPrefixed("views", route.template)) |template| {
        try view.data.addConst("jetzig_view", view.data.string(route.name));
        try view.data.addConst("jetzig_action", view.data.string(@tagName(route.action)));

        if (route.layout) |layout_name| {
            // TODO: Allow user to configure layouts directory other than src/app/views/layouts/
            const prefixed_name = try std.mem.concat(allocator, u8, &[_][]const u8{ "layouts_", layout_name });
            defer allocator.free(prefixed_name);

            if (zmpl.findPrefixed("views", prefixed_name)) |layout| {
                return try template.renderWithOptions(view.data, .{ .layout = layout });
            } else {
                std.debug.print("Unknown layout: {s}\n", .{layout_name});
                return try allocator.dupe(u8, "");
            }
        } else {
            return try template.render(view.data);
        }
    } else return null;
}

fn zigEscape(allocator: std.mem.Allocator, content: []const u8) ![]const u8 {
    var buf = std.ArrayList(u8).init(allocator);
    const writer = buf.writer();
    try std.zig.stringEscape(content, "", .{}, writer);
    return try buf.toOwnedSlice();
}
