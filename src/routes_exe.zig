const std = @import("std");
const routes = @import("routes");
const app = @import("app");
const jetzig = @import("jetzig");

pub fn main() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    const allocator = gpa.allocator();

    comptime var max_uri_path_len: usize = 0;

    log("Jetzig Routes:", .{});

    const environment = jetzig.Environment.init(undefined);
    const initHook: ?*const fn (*jetzig.App) anyerror!void = if (@hasDecl(app, "init")) app.init else null;

    inline for (routes.routes) |route| max_uri_path_len = @max(route.uri_path.len + 5, max_uri_path_len);
    const padded_path = std.fmt.comptimePrint("{{s: <{}}}", .{max_uri_path_len});

    inline for (routes.routes) |route| {
        const action = comptime switch (route.action) {
            .get => jetzig.colors.cyan("{s: <7}"),
            .index => jetzig.colors.blue("{s: <7}"),
            .post => jetzig.colors.yellow("{s: <7}"),
            .put => jetzig.colors.magenta("{s: <7}"),
            .patch => jetzig.colors.bright_magenta("{s: <7}"),
            .delete => jetzig.colors.red("{s: <7}"),
            .custom => unreachable,
        };

        log("  " ++ action ++ "  " ++ padded_path ++ " {?s}", .{
            @tagName(route.action),
            route.uri_path ++ switch (route.action) {
                .index, .post => "",
                .get, .put, .patch, .delete => "/:id",
                .custom => "",
            },
            route.path,
        });
    }

    var jetzig_app = jetzig.App{
        .environment = environment,
        .allocator = allocator,
        .custom_routes = std.ArrayList(jetzig.views.Route).init(allocator),
        .initHook = initHook,
    };

    if (initHook) |hook| try hook(&jetzig_app);

    for (jetzig_app.custom_routes.items) |route| {
        log(
            "  " ++ jetzig.colors.bold(jetzig.colors.white("{s: <7}")) ++ "  " ++ padded_path ++ " {s}:{s}",
            .{ route.name, route.uri_path, route.view_name, route.name },
        );
    }
}

fn log(comptime message: []const u8, args: anytype) void {
    std.debug.print(message ++ "\n", args);
}

fn sortedRoutes(comptime unordered_routes: []const jetzig.views.Route) void {
    comptime std.sort.pdq(jetzig.views.Route, unordered_routes, {}, lessThanFn);
}
pub fn lessThanFn(context: void, lhs: jetzig.views.Route, rhs: jetzig.views.Route) bool {
    _ = context;
    return std.mem.order(u8, lhs.uri_path, rhs.uri_path).compare(std.math.CompareOperator.lt);
}
