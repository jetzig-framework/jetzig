const std = @import("std");

allocator: std.mem.Allocator,
views_path: []const u8,
buffer: std.ArrayList(u8),
dynamic_routes: std.ArrayList(Function),
static_routes: std.ArrayList(Function),

const Self = @This();

const Function = struct {
    name: []const u8,
    params: []Param,
    path: []const u8,
    source: []const u8,

    pub fn fullName(self: @This(), allocator: std.mem.Allocator) ![]const u8 {
        var path = try allocator.dupe(u8, self.path);
        const extension = std.fs.path.extension(path);
        defer allocator.free(path);
        std.mem.replaceScalar(u8, path, std.fs.path.sep, '_');
        return std.mem.concat(
            allocator,
            u8,
            &[_][]const u8{ path[0 .. path.len - extension.len], "_", self.name },
        );
    }

    pub fn uriPath(self: @This(), allocator: std.mem.Allocator) ![]const u8 {
        if (std.mem.eql(u8, self.path, "root.zig")) return try allocator.dupe(u8, "/");

        var path = try allocator.dupe(u8, self.path);
        const extension = std.fs.path.extension(path);
        defer allocator.free(path);
        std.mem.replaceScalar(u8, path, std.fs.path.sep, '/');
        return std.mem.concat(
            allocator,
            u8,
            &[_][]const u8{ "/", path[0 .. path.len - extension.len] },
        );
    }

    pub fn lessThanFn(context: void, lhs: @This(), rhs: @This()) bool {
        _ = context;
        return std.mem.order(u8, lhs.name, rhs.name).compare(std.math.CompareOperator.lt);
    }
};

const Param = struct {
    name: []const u8,
    type_name: []const u8,

    pub fn typeBasename(self: @This()) ![]const u8 {
        if (std.mem.indexOfScalar(u8, self.type_name, '.')) |_| {
            var it = std.mem.splitBackwardsScalar(u8, self.type_name, '.');
            while (it.next()) |capture| {
                return capture;
            }
        }

        const pointer_start = std.mem.indexOfScalar(u8, self.type_name, '*');
        if (pointer_start) |index| {
            if (self.type_name.len < index + 1) return error.JetzigAstParserError;
            return self.type_name[index + 1 ..];
        } else {
            return self.type_name;
        }
    }
};

pub fn init(allocator: std.mem.Allocator, views_path: []const u8) Self {
    return .{
        .allocator = allocator,
        .views_path = views_path,
        .buffer = std.ArrayList(u8).init(allocator),
        .static_routes = std.ArrayList(Function).init(allocator),
        .dynamic_routes = std.ArrayList(Function).init(allocator),
    };
}

pub fn deinit(self: *Self) void {
    self.buffer.deinit();
    self.static_routes.deinit();
    self.dynamic_routes.deinit();
}

pub fn generateRoutes(self: *Self) !void {
    const writer = self.buffer.writer();

    var views_dir = try std.fs.cwd().openDir(self.views_path, .{ .iterate = true });
    defer views_dir.close();

    var walker = try views_dir.walk(self.allocator);
    defer walker.deinit();

    while (try walker.next()) |entry| {
        if (entry.kind != .file) continue;

        const extension = std.fs.path.extension(entry.path);
        const basename = std.fs.path.basename(entry.path);

        if (std.mem.eql(u8, basename, "routes.zig")) continue;
        if (std.mem.eql(u8, basename, "zmpl.manifest.zig")) continue;
        if (std.mem.startsWith(u8, basename, ".")) continue;
        if (!std.mem.eql(u8, extension, ".zig")) continue;

        const routes = try self.generateRoute(views_dir, entry.path);

        for (routes.static) |route| {
            try self.static_routes.append(route);
        }

        for (routes.dynamic) |route| {
            try self.dynamic_routes.append(route);
        }
    }

    std.sort.pdq(Function, self.static_routes.items, {}, Function.lessThanFn);
    std.sort.pdq(Function, self.dynamic_routes.items, {}, Function.lessThanFn);

    try writer.writeAll("pub const routes = struct {\n");
    try writer.writeAll("    pub const static = .{\n");

    for (self.static_routes.items) |static_route| {
        try self.writeRoute(writer, static_route);
    }

    try writer.writeAll("    };\n\n");
    try writer.writeAll("    pub const dynamic = .{\n");

    for (self.dynamic_routes.items) |dynamic_route| {
        try self.writeRoute(writer, dynamic_route);
        const name = try dynamic_route.fullName(self.allocator);
        defer self.allocator.free(name);
        std.debug.print("[jetzig] Imported route: {s}\n", .{name});
    }

    try writer.writeAll("    };\n");
    try writer.writeAll("};");
}

fn writeRoute(self: *Self, writer: std.ArrayList(u8).Writer, route: Function) !void {
    const full_name = try route.fullName(self.allocator);
    defer self.allocator.free(full_name);

    const uri_path = try route.uriPath(self.allocator);
    defer self.allocator.free(uri_path);

    const output_template =
        \\        .{{
        \\            .name = "{s}",
        \\            .action = "{s}",
        \\            .uri_path = "{s}",
        \\            .template = "{s}",
        \\            .function = @import("{s}").{s},
        \\        }},
        \\
    ;

    const output = try std.fmt.allocPrint(self.allocator, output_template, .{
        full_name,
        route.name,
        uri_path,
        full_name,
        route.path,
        route.name,
    });

    defer self.allocator.free(output);
    try writer.writeAll(output);
}

const RouteSet = struct {
    dynamic: []Function,
    static: []Function,
};

fn generateRoute(self: *Self, views_dir: std.fs.Dir, path: []const u8) !RouteSet {
    // REVIEW: Choose a sensible upper limit or allow user to take their own risks here ?
    const stat = try views_dir.statFile(path);
    const source = try views_dir.readFileAllocOptions(self.allocator, path, stat.size, null, @alignOf(u8), 0);
    defer self.allocator.free(source);

    var ast = try std.zig.Ast.parse(self.allocator, source, .zig);
    defer ast.deinit(self.allocator);

    var static_routes = std.ArrayList(Function).init(self.allocator);
    var dynamic_routes = std.ArrayList(Function).init(self.allocator);

    for (ast.nodes.items(.tag), 0..) |tag, index| {
        const function = try self.parseTag(ast, tag, index, path, source);
        if (function) |capture| {
            for (capture.params) |param| {
                if (std.mem.eql(u8, try param.typeBasename(), "StaticRequest")) {
                    try static_routes.append(capture);
                }
                if (std.mem.eql(u8, try param.typeBasename(), "Request")) {
                    try dynamic_routes.append(capture);
                }
            }
        }
    }

    return .{ .dynamic = dynamic_routes.items, .static = static_routes.items };
}

fn parseTag(
    self: *Self,
    ast: std.zig.Ast,
    tag: std.zig.Ast.Node.Tag,
    index: usize,
    path: []const u8,
    source: []const u8,
) !?Function {
    switch (tag) {
        .fn_proto_multi => {
            const fn_proto = ast.fnProtoMulti(@as(u32, @intCast(index)));
            if (fn_proto.name_token) |token| {
                const function_name = try self.allocator.dupe(u8, ast.tokenSlice(token));
                var it = fn_proto.iterate(&ast);
                var params = std.ArrayList(Param).init(self.allocator);
                defer params.deinit();

                while (it.next()) |param| {
                    if (param.name_token) |param_token| {
                        const param_name = ast.tokenSlice(param_token);
                        const node = ast.nodes.get(param.type_expr);
                        const type_name = try self.parseTypeExpr(ast, node);
                        try params.append(.{ .name = param_name, .type_name = type_name });
                    }
                }

                return .{
                    .name = function_name,
                    .path = try self.allocator.dupe(u8, path),
                    .params = try self.allocator.dupe(Param, params.items),
                    .source = try self.allocator.dupe(u8, source),
                };
            }
        },
        else => {},
    }

    return null;
}

fn parseTypeExpr(self: *Self, ast: std.zig.Ast, node: std.zig.Ast.Node) ![]const u8 {
    switch (node.tag) {
        // Currently all expected params are pointers, keeping this here in case that changes in future:
        .identifier => {},
        .ptr_type_aligned => {
            var buf = std.ArrayList([]const u8).init(self.allocator);
            defer buf.deinit();

            for (0..(ast.tokens.len - node.main_token)) |index| {
                const token = ast.tokens.get(node.main_token + index);
                switch (token.tag) {
                    .asterisk, .period, .identifier => {
                        try buf.append(ast.tokenSlice(@as(u32, @intCast(node.main_token + index))));
                    },
                    else => return try std.mem.concat(self.allocator, u8, buf.items),
                }
            }
        },
        else => {},
    }

    return error.JetzigAstParserError;
}
