const std = @import("std");
const jetzig = @import("jetzig");

ast: std.zig.Ast = undefined,
allocator: std.mem.Allocator,
root_path: []const u8,
templates_path: []const u8,
views_path: []const u8,
jobs_path: []const u8,
mailers_path: []const u8,
buffer: std.ArrayList(u8),
dynamic_routes: std.ArrayList(Function),
static_routes: std.ArrayList(Function),
module_paths: std.ArrayList([]const u8),
data: *jetzig.data.Data,

const Routes = @This();

const Function = struct {
    name: []const u8,
    view_name: []const u8,
    args: []Arg,
    routes: *const Routes,
    path: []const u8,
    source: []const u8,
    params: std.ArrayList([]const u8),
    static: bool = false,

    /// The full name of a route. This **must** match the naming convention used by static route
    /// compilation.
    /// path: `src/app/views/iguanas.zig`, action: `index` => `iguanas_index`
    pub fn fullName(self: Function) ![]const u8 {
        const relative_path = try self.routes.relativePathFrom(.views, self.path, .posix);
        defer self.routes.allocator.free(relative_path);

        const path = relative_path[0 .. relative_path.len - std.fs.path.extension(relative_path).len];
        std.mem.replaceScalar(u8, path, '/', '_');

        return std.mem.concat(self.routes.allocator, u8, &[_][]const u8{ path, "_", self.name });
    }

    pub fn viewName(self: Function) ![]const u8 {
        const relative_path = try self.routes.relativePathFrom(.views, self.path, .posix);
        defer self.routes.allocator.free(relative_path);

        return try self.routes.allocator.dupe(u8, chompExtension(relative_path));
    }

    /// The path used to match the route. Resource ID and extension is not included here and is
    /// appended as needed during matching logic at run time.
    pub fn uriPath(self: Function) ![]const u8 {
        const relative_path = try self.routes.relativePathFrom(.views, self.path, .posix);
        defer self.routes.allocator.free(relative_path);

        const path = relative_path[0 .. relative_path.len - std.fs.path.extension(relative_path).len];
        if (std.mem.eql(u8, path, "root")) return try self.routes.allocator.dupe(u8, "/");

        return try std.mem.concat(self.routes.allocator, u8, &[_][]const u8{ "/", path });
    }

    pub fn lessThanFn(context: void, lhs: Function, rhs: Function) bool {
        _ = context;
        return std.mem.order(u8, lhs.name, rhs.name).compare(std.math.CompareOperator.lt);
    }
};

// An argument passed to a view function.
const Arg = struct {
    name: []const u8,
    type_name: []const u8,

    pub fn typeBasename(self: Arg) ![]const u8 {
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

pub fn init(
    allocator: std.mem.Allocator,
    root_path: []const u8,
    templates_path: []const u8,
    views_path: []const u8,
    jobs_path: []const u8,
    mailers_path: []const u8,
) !Routes {
    const data = try allocator.create(jetzig.data.Data);
    data.* = jetzig.data.Data.init(allocator);

    return .{
        .allocator = allocator,
        .root_path = root_path,
        .templates_path = templates_path,
        .views_path = views_path,
        .jobs_path = jobs_path,
        .mailers_path = mailers_path,
        .buffer = std.ArrayList(u8).init(allocator),
        .static_routes = std.ArrayList(Function).init(allocator),
        .dynamic_routes = std.ArrayList(Function).init(allocator),
        .module_paths = std.ArrayList([]const u8).init(allocator),
        .data = data,
    };
}

pub fn deinit(self: *Routes) void {
    self.ast.deinit(self.allocator);
    self.buffer.deinit();
    self.static_routes.deinit();
    self.dynamic_routes.deinit();
}

/// Generates the complete route set for the application
pub fn generateRoutes(self: *Routes) ![]const u8 {
    const writer = self.buffer.writer();

    try writer.writeAll(
        \\const jetzig = @import("jetzig");
        \\
        \\pub const routes = [_]jetzig.Route{
        \\
    );
    try self.writeRoutes(writer);
    try writer.writeAll(
        \\};
        \\
    );

    try writer.writeAll(
        \\
        \\pub const mailers = [_]jetzig.MailerDefinition{
        \\
    );
    try self.writeMailers(writer);
    try writer.writeAll(
        \\};
        \\
    );

    try writer.writeAll(
        \\
        \\pub const jobs = [_]jetzig.JobDefinition{
        \\    .{ .name = "__jetzig_mail", .runFn = jetzig.mail.Job.run },
        \\
    );
    try self.writeJobs(writer);
    try writer.writeAll(
        \\};
        \\
    );

    try writer.writeAll(
        \\test {
        \\
    );

    for (self.module_paths.items) |module_path| {
        try writer.print(
            \\    _ = @import("{s}");
            \\
        , .{module_path});
    }

    try writer.writeAll(
        \\    @import("std").testing.refAllDeclsRecursive(@This());
        \\}
        \\
    );

    return try self.buffer.toOwnedSlice();
    // std.debug.print("routes.zig\n{s}\n", .{self.buffer.items});
}

pub fn relativePathFrom(
    self: Routes,
    root: enum { root, views, mailers, jobs },
    sub_path: []const u8,
    format: enum { os, posix },
) ![]u8 {
    const root_path = switch (root) {
        .root => self.root_path,
        .views => self.views_path,
        .mailers => self.mailers_path,
        .jobs => self.jobs_path,
    };

    const path = try std.fs.path.relative(self.allocator, root_path, sub_path);
    defer self.allocator.free(path);

    return switch (format) {
        .posix => try self.normalizePosix(path),
        .os => try self.allocator.dupe(u8, path),
    };
}

fn writeRoutes(self: *Routes, writer: anytype) !void {
    var dir = std.fs.openDirAbsolute(self.views_path, .{ .iterate = true }) catch |err| {
        switch (err) {
            error.FileNotFound => {
                std.debug.print(
                    "[jetzig] Views directory not found, no routes generated: `{s}`\n",
                    .{self.views_path},
                );
                return;
            },
            else => return err,
        }
    };
    defer dir.close();

    var walker = try dir.walk(self.allocator);
    defer walker.deinit();

    while (try walker.next()) |entry| {
        if (entry.kind != .file) continue;

        const extension = std.fs.path.extension(entry.path);

        if (!std.mem.eql(u8, extension, ".zig")) continue;

        const realpath = try dir.realpathAlloc(self.allocator, entry.path);
        defer self.allocator.free(realpath);

        const view_routes = try self.generateRoutesForView(dir, try self.allocator.dupe(u8, realpath));

        for (view_routes.static) |view_route| {
            try self.static_routes.append(view_route);
        }

        for (view_routes.dynamic) |view_route| {
            try self.dynamic_routes.append(view_route);
        }
    }

    std.sort.pdq(Function, self.static_routes.items, {}, Function.lessThanFn);
    std.sort.pdq(Function, self.dynamic_routes.items, {}, Function.lessThanFn);

    for (self.static_routes.items) |static_route| {
        try self.writeRoute(writer, static_route);
    }

    for (self.dynamic_routes.items) |dynamic_route| {
        try self.writeRoute(writer, dynamic_route);
        const name = try dynamic_route.fullName();
        defer self.allocator.free(name);
    }

    std.debug.print("[jetzig] Imported {} route(s)\n", .{self.dynamic_routes.items.len});
}

fn writeRoute(self: *Routes, writer: std.ArrayList(u8).Writer, route: Function) !void {
    const full_name = try route.fullName();
    defer self.allocator.free(full_name);

    const uri_path = try route.uriPath();
    defer self.allocator.free(uri_path);

    const output_template =
        \\        .{{
        \\            .id = "{9s}",
        \\            .name = "{0s}",
        \\            .action = .{1s},
        \\            .view_name = "{2s}",
        \\            .view = jetzig.Route.ViewType{{ .{3s} = .{{ .{1s} = @import("{7s}").{1s} }} }},
        \\            .path = "{7s}",
        \\            .static = {4s},
        \\            .uri_path = "{5s}",
        \\            .template = "{6s}",
        \\            .layout = if (@hasDecl(@import("{7s}"), "layout")) @import("{7s}").layout else null,
        \\            .json_params = &[_][]const u8 {{ {8s} }},
        \\            .formats = if (@hasDecl(@import("{7s}"), "formats")) @import("{7s}").formats else null,
        \\        }},
        \\
    ;

    const module_path = try self.relativePathFrom(.root, route.path, .posix);
    defer self.allocator.free(module_path);

    const view_name = try route.viewName();
    defer self.allocator.free(view_name);

    const template = try std.mem.concat(
        self.allocator,
        u8,
        &[_][]const u8{ view_name, "/", route.name },
    );

    std.mem.replaceScalar(u8, module_path, '\\', '/');
    try self.module_paths.append(try self.allocator.dupe(u8, module_path));

    var buf: [32]u8 = undefined;
    const id = jetzig.util.generateVariableName(&buf);
    const output = try std.fmt.allocPrint(self.allocator, output_template, .{
        full_name,
        route.name,
        view_name,
        if (route.static) "static" else "dynamic",
        if (route.static) "true" else "false",
        uri_path,
        template,
        module_path,
        try std.mem.join(self.allocator, ", \n", route.params.items),
        id,
    });

    defer self.allocator.free(output);
    try writer.writeAll(output);
}

const RouteSet = struct {
    dynamic: []Function,
    static: []Function,
};

fn generateRoutesForView(self: *Routes, dir: std.fs.Dir, path: []const u8) !RouteSet {
    const stat = try dir.statFile(path);
    const source = try dir.readFileAllocOptions(self.allocator, path, @intCast(stat.size), null, @alignOf(u8), 0);
    defer self.allocator.free(source);

    self.ast = try std.zig.Ast.parse(self.allocator, source, .zig);

    var static_routes = std.ArrayList(Function).init(self.allocator);
    var dynamic_routes = std.ArrayList(Function).init(self.allocator);
    var static_params: ?*jetzig.data.Value = null;

    for (self.ast.nodes.items(.tag), 0..) |tag, index| {
        switch (tag) {
            .fn_proto_multi => {
                const function = try self.parseFunction(index, path, source);
                if (function) |*capture| {
                    for (capture.args) |arg| {
                        if (std.mem.eql(u8, try arg.typeBasename(), "StaticRequest")) {
                            @constCast(capture).static = true;
                            try static_routes.append(capture.*);
                        }
                        if (std.mem.eql(u8, try arg.typeBasename(), "Request")) {
                            try dynamic_routes.append(capture.*);
                        }
                    }
                }
            },
            .simple_var_decl => {
                const decl = self.ast.simpleVarDecl(asNodeIndex(index));
                if (self.isStaticParamsDecl(decl)) {
                    self.data.reset();
                    const params = try self.data.root(.object);
                    try self.parseStaticParamsDecl(decl, params);
                    static_params = self.data.value;
                }
            },
            else => {},
        }
    }

    for (static_routes.items) |*static_route| {
        var encoded_params = std.ArrayList([]const u8).init(self.allocator);
        defer encoded_params.deinit();

        if (static_params) |capture| {
            if (capture.get(static_route.name)) |params| {
                for (params.items(.array)) |item| {
                    const json = try item.toJson();
                    var encoded_buf = std.ArrayList(u8).init(self.allocator);
                    defer encoded_buf.deinit();
                    const writer = encoded_buf.writer();
                    try std.json.encodeJsonString(json, .{}, writer);
                    try static_route.params.append(try self.allocator.dupe(u8, encoded_buf.items));
                }
            }
        }
    }

    return .{
        .dynamic = dynamic_routes.items,
        .static = static_routes.items,
    };
}

// Parse the `pub const static_params` definition and into a `jetzig.data.Value`.
fn parseStaticParamsDecl(self: *Routes, decl: std.zig.Ast.full.VarDecl, params: *jetzig.data.Value) !void {
    const init_node = self.ast.nodes.items(.tag)[decl.ast.init_node];
    switch (init_node) {
        .struct_init_dot_two, .struct_init_dot_two_comma => {
            try self.parseStruct(decl.ast.init_node, params);
        },
        else => return,
    }
}
// Recursively parse a struct into a jetzig.data.Value so it can be serialized as JSON and stored
// in `routes.zig` - used for static param comparison at runtime.
fn parseStruct(self: *Routes, node: std.zig.Ast.Node.Index, params: *jetzig.data.Value) anyerror!void {
    var struct_buf: [2]std.zig.Ast.Node.Index = undefined;
    const maybe_struct_init = self.ast.fullStructInit(&struct_buf, node);

    if (maybe_struct_init == null) {
        std.debug.print("Expected struct node.\n", .{});
        return error.JetzigAstParserError;
    }

    const struct_init = maybe_struct_init.?;

    for (struct_init.ast.fields) |field| try self.parseField(field, params);
}

// Array of param sets for a route, e.g. `.{ .{ .foo = "bar" } }
fn parseArray(self: *Routes, node: std.zig.Ast.Node.Index, params: *jetzig.data.Value) anyerror!void {
    var array_buf: [2]std.zig.Ast.Node.Index = undefined;
    const maybe_array = self.ast.fullArrayInit(&array_buf, node);

    if (maybe_array == null) {
        std.debug.print("Expected array node.\n", .{});
        return error.JetzigAstParserError;
    }

    const array = maybe_array.?;

    const main_token = self.ast.nodes.items(.main_token)[node];
    const field_name = self.ast.tokenSlice(main_token - 3);

    const params_array = try self.data.array();
    try params.put(field_name, params_array);

    for (array.ast.elements) |element| {
        const elem = self.ast.nodes.items(.tag)[element];
        switch (elem) {
            .struct_init_dot, .struct_init_dot_two, .struct_init_dot_two_comma => {
                const route_params = try self.data.object();
                try params_array.append(route_params);
                try self.parseStruct(element, route_params);
            },
            .array_init_dot, .array_init_dot_two, .array_init_dot_comma, .array_init_dot_two_comma => {
                const route_params = try self.data.object();
                try params_array.append(route_params);
                try self.parseField(element, route_params);
            },
            .string_literal => {
                const string_token = self.ast.nodes.items(.main_token)[element];
                const string_value = self.ast.tokenSlice(string_token);

                // Strip quotes: `"foo"` -> `foo`
                try params_array.append(string_value[1 .. string_value.len - 1]);
            },
            .number_literal => {
                const number_token = self.ast.nodes.items(.main_token)[element];
                const number_value = self.ast.tokenSlice(number_token);
                try params_array.append(try parseNumber(number_value, self.data));
            },
            inline else => {
                const tag = self.ast.nodes.items(.tag)[element];
                std.debug.print("Unexpected token: {}\n", .{tag});
                return error.JetzigStaticParamsParseError;
            },
        }
    }
}

// Parse the value of a param field (recursively when field is a struct/array)
fn parseField(self: *Routes, node: std.zig.Ast.Node.Index, params: *jetzig.data.Value) anyerror!void {
    const tag = self.ast.nodes.items(.tag)[node];
    switch (tag) {
        // Route params, e.g. `.index = .{ ... }`
        .array_init_dot, .array_init_dot_two, .array_init_dot_comma, .array_init_dot_two_comma => {
            try self.parseArray(node, params);
        },
        .struct_init_dot, .struct_init_dot_two, .struct_init_dot_two_comma => {
            const nested_params = try self.data.object();
            const main_token = self.ast.nodes.items(.main_token)[node];
            const field_name = self.ast.tokenSlice(main_token - 3);
            try params.put(field_name, nested_params);
            try self.parseStruct(node, nested_params);
        },
        // Individual param in a params struct, e.g. `.foo = "bar"`
        .string_literal => {
            const main_token = self.ast.nodes.items(.main_token)[node];
            const field_name = self.ast.tokenSlice(main_token - 2);
            const field_value = self.ast.tokenSlice(main_token);

            try params.put(
                field_name,
                // strip outer quotes
                field_value[1 .. field_value.len - 1],
            );
        },
        .number_literal => {
            const main_token = self.ast.nodes.items(.main_token)[node];
            const field_name = self.ast.tokenSlice(main_token - 2);
            const field_value = self.ast.tokenSlice(main_token);

            try params.put(field_name, try parseNumber(field_value, self.data));
        },
        else => {
            std.debug.print("Unexpected token: {}\n", .{tag});
            return error.JetzigStaticParamsParseError;
        },
    }
}

fn parseNumber(value: []const u8, data: *jetzig.data.Data) !*jetzig.data.Value {
    if (std.mem.containsAtLeast(u8, value, 1, ".")) {
        return data.float(try std.fmt.parseFloat(f64, value));
    } else {
        return data.integer(try std.fmt.parseInt(i64, value, 10));
    }
}

fn isStaticParamsDecl(self: *Routes, decl: std.zig.Ast.full.VarDecl) bool {
    if (decl.visib_token) |token_index| {
        const visibility = self.ast.tokenSlice(token_index);
        const mutability = self.ast.tokenSlice(decl.ast.mut_token);
        const identifier = self.ast.tokenSlice(decl.ast.mut_token + 1); // FIXME
        return (std.mem.eql(u8, visibility, "pub") and
            std.mem.eql(u8, mutability, "const") and
            std.mem.eql(u8, identifier, "static_params"));
    } else {
        return false;
    }
}

fn parseFunction(
    self: *Routes,
    index: usize,
    path: []const u8,
    source: []const u8,
) !?Function {
    const fn_proto = self.ast.fnProtoMulti(@as(u32, @intCast(index)));
    if (fn_proto.name_token) |token| {
        const function_name = try self.allocator.dupe(u8, self.ast.tokenSlice(token));
        var it = fn_proto.iterate(&self.ast);
        var args = std.ArrayList(Arg).init(self.allocator);
        defer args.deinit();

        if (!isActionFunctionName(function_name)) {
            self.allocator.free(function_name);
            return null;
        }

        while (it.next()) |arg| {
            if (arg.name_token) |arg_token| {
                const arg_name = self.ast.tokenSlice(arg_token);
                const node = self.ast.nodes.get(arg.type_expr);
                const type_name = try self.parseTypeExpr(node);
                try args.append(.{ .name = arg_name, .type_name = type_name });
            }
        }

        const view_name = path[0 .. path.len - std.fs.path.extension(path).len];

        return .{
            .name = function_name,
            .view_name = try self.allocator.dupe(u8, view_name),
            .routes = self,
            .path = path,
            .args = try self.allocator.dupe(Arg, args.items),
            .source = try self.allocator.dupe(u8, source),
            .params = std.ArrayList([]const u8).init(self.allocator),
        };
    }

    return null;
}

fn parseTypeExpr(self: *Routes, node: std.zig.Ast.Node) ![]const u8 {
    switch (node.tag) {
        // Currently all expected params are pointers, keeping this here in case that changes in future:
        .identifier => {},
        .ptr_type_aligned => {
            var buf = std.ArrayList([]const u8).init(self.allocator);
            defer buf.deinit();

            for (0..(self.ast.tokens.len - node.main_token)) |index| {
                const token = self.ast.tokens.get(node.main_token + index);
                switch (token.tag) {
                    .asterisk, .period, .identifier => {
                        try buf.append(self.ast.tokenSlice(@as(u32, @intCast(node.main_token + index))));
                    },
                    else => return try std.mem.concat(self.allocator, u8, buf.items),
                }
            }
        },
        else => {},
    }

    return error.JetzigAstParserError;
}

fn asNodeIndex(index: usize) std.zig.Ast.Node.Index {
    return @as(std.zig.Ast.Node.Index, @intCast(index));
}

fn isActionFunctionName(name: []const u8) bool {
    inline for (@typeInfo(jetzig.views.Route.Action).@"enum".fields) |field| {
        if (std.mem.eql(u8, field.name, name)) return true;
    }

    return false;
}

inline fn chompExtension(path: []const u8) []const u8 {
    return path[0 .. path.len - std.fs.path.extension(path).len];
}

fn zigEscape(self: Routes, input: []const u8) ![]const u8 {
    var buf = std.ArrayList(u8).init(self.allocator);
    const writer = buf.writer();
    try std.zig.stringEscape(input, "", .{}, writer);
    return try buf.toOwnedSlice();
}

fn normalizePosix(self: Routes, path: []const u8) ![]u8 {
    var buf = std.ArrayList([]const u8).init(self.allocator);
    defer buf.deinit();

    var it = std.mem.splitSequence(u8, path, std.fs.path.sep_str);
    while (it.next()) |segment| try buf.append(segment);

    return try std.mem.join(self.allocator, std.fs.path.sep_str_posix, buf.items);
}

fn writeMailers(self: Routes, writer: anytype) !void {
    var dir = std.fs.openDirAbsolute(self.mailers_path, .{ .iterate = true }) catch |err| {
        switch (err) {
            error.FileNotFound => {
                std.debug.print(
                    "[jetzig] Mailers directory not found, no mailers generated: `{s}`\n",
                    .{self.mailers_path},
                );
                return;
            },
            else => return err,
        }
    };
    defer dir.close();

    var count: usize = 0;
    var walker = try dir.walk(self.allocator);
    while (try walker.next()) |entry| {
        if (!std.mem.eql(u8, std.fs.path.extension(entry.path), ".zig")) continue;

        const realpath = try dir.realpathAlloc(self.allocator, entry.path);
        defer self.allocator.free(realpath);

        const root_relative_path = try self.relativePathFrom(.root, realpath, .posix);
        defer self.allocator.free(root_relative_path);

        const mailers_relative_path = try self.relativePathFrom(.mailers, realpath, .posix);
        defer self.allocator.free(mailers_relative_path);

        const module_path = try self.zigEscape(root_relative_path);
        defer self.allocator.free(module_path);

        const name_path = try self.zigEscape(mailers_relative_path);
        defer self.allocator.free(name_path);

        const name = chompExtension(name_path);

        try writer.writeAll(try std.fmt.allocPrint(
            self.allocator,
            \\    .{{
            \\        .name = "{0s}",
            \\        .deliverFn = @import("{1s}").deliver,
            \\        .defaults = if (@hasDecl(@import("{1s}"), "defaults")) @import("{1s}").defaults else null,
            \\        .html_template = "{0s}/html",
            \\        .text_template = "{0s}/text",
            \\    }},
            \\
        ,
            .{ name, module_path },
        ));
        count += 1;
    }

    std.debug.print("[jetzig] Imported {} mailer(s)\n", .{count});
}

fn writeJobs(self: Routes, writer: anytype) !void {
    var dir = std.fs.openDirAbsolute(self.jobs_path, .{ .iterate = true }) catch |err| {
        switch (err) {
            error.FileNotFound => {
                std.debug.print(
                    "[jetzig] Jobs directory not found, no jobs generated: `{s}`\n",
                    .{self.jobs_path},
                );
                return;
            },
            else => return err,
        }
    };
    defer dir.close();

    var count: usize = 0;
    var walker = try dir.walk(self.allocator);
    while (try walker.next()) |entry| {
        if (!std.mem.eql(u8, std.fs.path.extension(entry.path), ".zig")) continue;

        const realpath = try dir.realpathAlloc(self.allocator, entry.path);
        defer self.allocator.free(realpath);

        const root_relative_path = try self.relativePathFrom(.root, realpath, .posix);
        defer self.allocator.free(root_relative_path);

        const jobs_relative_path = try self.relativePathFrom(.jobs, realpath, .posix);
        defer self.allocator.free(jobs_relative_path);

        const module_path = try self.zigEscape(root_relative_path);
        defer self.allocator.free(module_path);

        const name_path = try self.zigEscape(jobs_relative_path);
        defer self.allocator.free(name_path);

        const name = chompExtension(name_path);

        try writer.writeAll(try std.fmt.allocPrint(
            self.allocator,
            \\    .{{
            \\        .name = "{0s}",
            \\        .runFn = @import("{1s}").run,
            \\    }},
            \\
        ,
            .{ name, module_path },
        ));
        count += 1;
    }

    std.debug.print("[jetzig] Imported {} job(s)\n", .{count});
}
