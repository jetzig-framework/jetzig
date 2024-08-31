const std = @import("std");
const util = @import("../../util.zig");

/// Run the view generator. Create a view in `src/app/views/`
pub fn run(allocator: std.mem.Allocator, cwd: std.fs.Dir, args: [][]const u8, help: bool) !void {
    if (help or args.len == 0) {
        std.debug.print(
            \\Generate a view. Pass optional action names from:
            \\  index, get, post, put, patch, delete
            \\
            \\Optionally suffix actions with `:static` to use static routing.
            \\Static requests are rendered at build time only. Use static routes
            \\when rendering takes a long time and content does not change between
            \\deployments.
            \\
            \\Omit action names to generate a view with all actions defined.
            \\
            \\Example:
            \\
            \\  jetzig generate view iguanas index:static get post delete
            \\
        , .{});

        if (help) return;

        return error.JetzigCommandError;
    }

    var buf = std.ArrayList(u8).init(allocator);
    defer buf.deinit();

    const writer = buf.writer();

    try writer.writeAll(
        \\const std = @import("std");
        \\const jetzig = @import("jetzig");
        \\
        \\
    );

    const filename = try std.mem.concat(allocator, u8, &[_][]const u8{ args[0], ".zig" });
    defer allocator.free(filename);
    const action_args = if (args.len > 1)
        args[1..]
    else
        &[_][]const u8{ "index", "get", "post", "put", "patch", "delete" };

    var actions = std.ArrayList(Action).init(allocator);
    defer actions.deinit();

    var static_actions = std.ArrayList(Action).init(allocator);
    defer static_actions.deinit();

    for (action_args) |arg| {
        if (parseAction(arg)) |action| {
            try actions.append(action);
            if (action.static) try static_actions.append(action);
        } else {
            std.debug.print("Unexpected argument: {s}\n", .{arg});
            return error.JetzigCommandError;
        }
    }

    if (static_actions.items.len > 0) try writeStaticParams(allocator, static_actions.items, writer);

    for (actions.items) |action| {
        try writeAction(allocator, writer, action);
        try writeTemplate(allocator, cwd, args[0], action);
    }

    for (actions.items) |action| {
        try writeTest(allocator, writer, args[0], action);
    }

    var dir = try cwd.openDir("src/app/views", .{});
    defer dir.close();

    const file = dir.createFile(filename, .{ .exclusive = true }) catch |err| {
        switch (err) {
            error.PathAlreadyExists => {
                std.debug.print("Path already exists, skipping view creation: {s}\n", .{filename});
                return error.JetzigCommandError;
            },
            else => return err,
        }
    };
    try file.writeAll(util.strip(buf.items));
    try file.writeAll("\n");
    file.close();
    const realpath = try dir.realpathAlloc(allocator, filename);
    defer allocator.free(realpath);
    std.debug.print("Generated view: {s}\n", .{realpath});
}

const Method = enum { index, get, post, put, patch, delete };
const Action = struct {
    method: Method,
    static: bool,
};

// Parse a view arg. Grammar:
// [index[:static]|get[:static]|post[:static]|put[:static]|patch[:static]|delete[:static]]
fn parseAction(arg: []const u8) ?Action {
    inline for (@typeInfo(Method).@"enum".fields) |tag| {
        const with_static = tag.name ++ ":static";
        const method: Method = @enumFromInt(tag.value);

        if (std.mem.eql(u8, tag.name, arg)) return .{ .method = method, .static = false };
        if (std.mem.eql(u8, with_static, arg)) return .{ .method = method, .static = true };
    }

    return null;
}

// Write a view function to the output buffer.
fn writeAction(allocator: std.mem.Allocator, writer: anytype, action: Action) !void {
    const function = try std.fmt.allocPrint(
        allocator,
        \\pub fn {s}({s}request: *jetzig.{s}, data: *jetzig.Data) !jetzig.View {{
        \\    _ = data;{s}
        \\    return request.render({s});
        \\}}
        \\
        \\
    ,
        .{
            @tagName(action.method),
            switch (action.method) {
                .index, .post => "",
                .get, .put, .patch, .delete => "id: []const u8, ",
            },
            if (action.static) "StaticRequest" else "Request",
            switch (action.method) {
                .index, .post => "",
                .get, .put, .patch, .delete => "\n    _ = id;",
            },
            switch (action.method) {
                .index, .get => ".ok",
                .post => ".created",
                .put, .patch, .delete => ".ok",
            },
        },
    );
    defer allocator.free(function);
    try writer.writeAll(function);
}

// Write a view function to the output buffer.
fn writeTest(allocator: std.mem.Allocator, writer: anytype, name: []const u8, action: Action) !void {
    const action_upper = try std.ascii.allocUpperString(allocator, @tagName(action.method));
    defer allocator.free(action_upper);

    const test_body = try std.fmt.allocPrint(
        allocator,
        \\
        \\test "{s}" {{
        \\    var app = try jetzig.testing.app(std.testing.allocator, @import("routes"));
        \\    defer app.deinit();
        \\
        \\    const response = try app.request(.{s}, "/{s}{s}", .{{}});
        \\    try response.expectStatus({s});
        \\}}
        \\
    ,
        .{
            @tagName(action.method),
            switch (action.method) {
                .index, .get => "GET",
                .put, .patch, .delete, .post => action_upper,
            },
            name,
            switch (action.method) {
                .index, .post => "",
                .get, .put, .patch, .delete => "/example-id",
            },
            switch (action.method) {
                .index, .get => ".ok",
                .post => ".created",
                .put, .patch, .delete => ".ok",
            },
        },
    );
    defer allocator.free(test_body);
    try writer.writeAll(test_body);
}
// Output static params example. Only invoked if one or more static routes are created.
fn writeStaticParams(allocator: std.mem.Allocator, actions: []Action, writer: anytype) !void {
    try writer.writeAll(
        \\// Define an array of params for each static view function.
        \\// At build time, static outputs are generated for each set of params.
        \\// At run time, requests matching the provided params will render the pre-rendered content.
        \\pub const static_params = .{
        \\
    );

    for (actions) |action| {
        switch (action.method) {
            .index, .post => {
                const output = try std.fmt.allocPrint(
                    allocator,
                    \\    .{s} = .{{
                    \\        .{{ .params = .{{ .foo = "bar", .baz = "qux" }} }},
                    \\    }},
                    \\
                ,
                    .{@tagName(action.method)},
                );
                defer allocator.free(output);
                try writer.writeAll(output);
            },
            .get, .put, .patch, .delete => {
                const output = try std.fmt.allocPrint(
                    allocator,
                    \\    .{s} = .{{
                    \\        .{{ .id = "1", .params = .{{ .foo = "bar", .baz = "qux" }} }},
                    \\    }},
                    \\
                ,
                    .{@tagName(action.method)},
                );
                defer allocator.free(output);
                try writer.writeAll(output);
            },
        }
    }

    try writer.writeAll(
        \\};
        \\
        \\
    );
}

// Generates a Zmpl template for a corresponding view + action.
fn writeTemplate(allocator: std.mem.Allocator, cwd: std.fs.Dir, name: []const u8, action: Action) !void {
    const path = try std.fs.path.join(allocator, &[_][]const u8{
        "src",
        "app",
        "views",
        name,
    });
    defer allocator.free(path);

    var view_dir = try cwd.makeOpenPath(path, .{});
    defer view_dir.close();

    const filename = try std.mem.concat(allocator, u8, &[_][]const u8{ @tagName(action.method), ".zmpl" });
    defer allocator.free(filename);

    const file = view_dir.createFile(filename, .{ .exclusive = true }) catch |err| {
        switch (err) {
            error.PathAlreadyExists => {
                std.debug.print("Path already exists, skipping template creation: {s}\n", .{filename});
                return;
            },
            else => return err,
        }
    };

    try file.writeAll(
        \\<div>
        \\  <span>Content goes here</span>
        \\</div>
        \\
    );

    file.close();

    const realpath = try view_dir.realpathAlloc(allocator, filename);
    defer allocator.free(realpath);
    std.debug.print("Generated template: {s}\n", .{realpath});
}
