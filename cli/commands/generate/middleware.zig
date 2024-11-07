const std = @import("std");
const util = @import("../../util.zig");

/// Run the middleware generator. Create a middleware file in `src/app/middleware/`
pub fn run(allocator: std.mem.Allocator, cwd: std.fs.Dir, args: [][]const u8, help: bool) !void {
    if (help or args.len != 1 or !util.isCamelCase(args[0])) {
        std.debug.print(
            \\Generate a middleware module. Module name must be in CamelCase.
            \\
            \\Example:
            \\
            \\  jetzig generate middleware IguanaBrain
            \\
        , .{});

        if (help) return;

        return error.JetzigCommandError;
    }

    const dir_path = try std.fs.path.join(allocator, &[_][]const u8{ "src", "app", "middleware" });
    defer allocator.free(dir_path);

    var dir = try cwd.makeOpenPath(dir_path, .{});
    defer dir.close();

    const filename = try std.mem.concat(allocator, u8, &[_][]const u8{ args[0], ".zig" });
    defer allocator.free(filename);

    const file = dir.createFile(filename, .{ .exclusive = true }) catch |err| {
        switch (err) {
            error.PathAlreadyExists => {
                std.debug.print("Middleware already exists: {s}\n", .{filename});
                return error.JetzigCommandError;
            },
            else => return err,
        }
    };

    try file.writeAll(middleware_content);

    file.close();

    const realpath = try dir.realpathAlloc(allocator, filename);
    defer allocator.free(realpath);
    std.debug.print(
        \\Generated middleware: {s}
        \\
        \\Edit `src/main.zig` and add the new middleware to the `jetzig_options.middleware` declaration:
        \\
        \\  pub const jetzig_options = struct {{
        \\      pub const middleware: []const type = &.{{
        \\          @import("app/middleware/{s}.zig"),
        \\      }};
        \\  }};
        \\
        \\Middleware are invoked in the order they appear in `jetzig_options.middleware`.
        \\
        \\
    , .{ realpath, args[0] });
}

const middleware_content =
    \\const std = @import("std");
    \\const jetzig = @import("jetzig");
    \\
    \\/// Define any custom data fields you want to store here. Assigning to these fields in the `init`
    \\/// function allows you to access them in the `beforeRequest` and `afterRequest` functions, where
    \\/// they can also be modified.
    \\my_custom_value: []const u8,
    \\
    \\const Self = @This();
    \\
    \\/// Initialize middleware.
    \\pub fn init(request: *jetzig.http.Request) !*Self {
    \\    var middleware = try request.allocator.create(Self);
    \\    middleware.my_custom_value = "initial value";
    \\    return middleware;
    \\}
    \\
    \\/// Invoked immediately after the request is received but before it has started processing.
    \\/// Any calls to `request.render` or `request.redirect` will prevent further processing of the
    \\/// request, including any other middleware in the chain.
    \\pub fn afterRequest(self: *Self, request: *jetzig.http.Request) !void {
    \\    request.server.logger.debug("[middleware] my_custom_value: {s}", .{self.my_custom_value});
    \\    self.my_custom_value = @tagName(request.method);
    \\}
    \\
    \\/// Invoked immediately before the response renders to the client.
    \\/// The response can be modified here if needed.
    \\pub fn beforeResponse(self: *Self, request: *jetzig.http.Request, response: *jetzig.http.Response) !void {
    \\    request.server.logger.debug(
    \\        "[middleware] my_custom_value: {s}, response status: {s}",
    \\        .{ self.my_custom_value, @tagName(response.status_code) },
    \\    );
    \\}
    \\
    \\/// Invoked immediately after the response has been finalized and sent to the client.
    \\/// Response data can be accessed for logging, but any modifications will have no impact.
    \\pub fn afterResponse(self: *Self, request: *jetzig.http.Request, response: *jetzig.http.Response) void {
    \\    request.allocator.destroy(self);
    \\}
    \\
    \\/// Invoked after `afterResponse` is called. Use this function to do any clean-up.
    \\/// Note that `request.allocator` is an arena allocator, so any allocations are automatically
    \\/// freed before the next request starts processing.
    \\pub fn deinit(self: *Self, request: *jetzig.http.Request) void {
    \\    request.allocator.destroy(self);
    \\}
    \\
;
