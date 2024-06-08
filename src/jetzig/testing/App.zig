const std = @import("std");

const jetzig = @import("../../jetzig.zig");
const httpz = @import("httpz");

const App = @This();

allocator: std.mem.Allocator,
routes: []const jetzig.views.Route,
arena: *std.heap.ArenaAllocator,
store: *jetzig.kv.Store,
cache: *jetzig.kv.Store,
job_queue: *jetzig.kv.Store,

const initHook = jetzig.root.initHook;

pub fn init(allocator: std.mem.Allocator, routes_module: type) !App {
    switch (jetzig.testing.state) {
        .ready => {},
        .initial => {
            std.log.err(
                "Unexpected state. Use Jetzig test runner: `zig build jetzig:test` or `jetzig test`",
                .{},
            );
            std.process.exit(1);
        },
    }

    const arena = try allocator.create(std.heap.ArenaAllocator);
    arena.* = std.heap.ArenaAllocator.init(allocator);

    return .{
        .arena = arena,
        .allocator = allocator,
        .routes = &routes_module.routes,
        .store = try createStore(arena.allocator()),
        .cache = try createStore(arena.allocator()),
        .job_queue = try createStore(arena.allocator()),
    };
}

pub fn deinit(self: *App) void {
    self.arena.deinit();
    self.allocator.destroy(self.arena);
}

const RequestOptions = struct {
    headers: []const jetzig.testing.TestResponse.Header = &.{},
    json: ?[]const u8 = null,
    params: ?[]Param = null,
};

const Param = struct {
    key: []const u8,
    value: ?[]const u8,
};

pub fn request(
    self: *App,
    comptime method: jetzig.http.Request.Method,
    comptime path: []const u8,
    args: anytype,
) !jetzig.testing.TestResponse {
    const options = buildOptions(self, args);

    const allocator = self.arena.allocator();
    const routes = try jetzig.App.createRoutes(allocator, self.routes);

    const logger = jetzig.loggers.Logger{ .test_logger = jetzig.loggers.TestLogger{} };
    var log_queue = jetzig.loggers.LogQueue.init(allocator);
    var server = jetzig.http.Server{
        .allocator = allocator,
        .logger = logger,
        .options = .{
            .logger = logger,
            .bind = undefined,
            .port = undefined,
            .detach = false,
            .environment = .testing,
            .log_queue = &log_queue,
            .secret = jetzig.testing.secret,
        },
        .routes = routes,
        .custom_routes = &.{},
        .mailer_definitions = &.{},
        .job_definitions = &.{},
        .mime_map = jetzig.testing.mime_map,
        .store = self.store,
        .cache = self.cache,
        .job_queue = self.job_queue,
    };

    try server.decodeStaticParams();

    var buf: [1024]u8 = undefined;
    var httpz_request = try stubbedRequest(allocator, &buf, method, path, options);
    var httpz_response = try stubbedResponse(allocator);
    try server.processNextRequest(&httpz_request, &httpz_response);
    var headers = std.ArrayList(jetzig.testing.TestResponse.Header).init(self.arena.allocator());
    for (0..httpz_response.headers.len) |index| {
        try headers.append(.{
            .name = try self.arena.allocator().dupe(u8, httpz_response.headers.keys[index]),
            .value = try self.arena.allocator().dupe(u8, httpz_response.headers.values[index]),
        });
    }
    var data = jetzig.data.Data.init(allocator);
    defer data.deinit();

    var jobs = std.ArrayList(jetzig.testing.TestResponse.Job).init(self.arena.allocator());
    while (try self.job_queue.popFirst(&data, "__jetzig_jobs")) |value| {
        if (value.getT(.string, "__jetzig_job_name")) |job_name| try jobs.append(.{
            .name = try self.arena.allocator().dupe(u8, job_name),
        });
    }

    return .{
        .allocator = self.arena.allocator(),
        .status = httpz_response.status,
        .body = try self.arena.allocator().dupe(u8, httpz_response.body orelse ""),
        .headers = try headers.toOwnedSlice(),
        .jobs = try jobs.toOwnedSlice(),
    };
}

pub fn params(self: App, args: anytype) []Param {
    const allocator = self.arena.allocator();
    var array = std.ArrayList(Param).init(allocator);
    inline for (@typeInfo(@TypeOf(args)).Struct.fields) |field| {
        array.append(.{ .key = field.name, .value = @field(args, field.name) }) catch @panic("OOM");
    }
    return array.toOwnedSlice() catch @panic("OOM");
}

pub fn json(self: App, args: anytype) []const u8 {
    const allocator = self.arena.allocator();
    return std.json.stringifyAlloc(allocator, args, .{}) catch @panic("OOM");
}

fn stubbedRequest(
    allocator: std.mem.Allocator,
    buf: []u8,
    comptime method: jetzig.http.Request.Method,
    comptime path: []const u8,
    options: RequestOptions,
) !httpz.Request {
    var request_headers = try keyValue(allocator, 32);
    for (options.headers) |header| request_headers.add(header.name, header.value);
    if (options.json != null) {
        request_headers.add("accept", "application/json");
        request_headers.add("content-type", "application/json");
    }

    var params_buf = std.ArrayList([]const u8).init(allocator);
    if (options.params) |array| {
        for (array) |param| {
            try params_buf.append(
                try std.fmt.allocPrint(allocator, "{s}{s}{s}", .{
                    param.key,
                    if (param.value != null) "=" else "",
                    param.value orelse "",
                }),
            );
        }
    }
    const query = try std.mem.join(allocator, "&", try params_buf.toOwnedSlice());
    return .{
        .url = .{
            .raw = try std.mem.concat(allocator, u8, &.{ path, if (query.len > 0) "?" else "", query }),
            .path = path,
            .query = query,
        },
        .address = undefined,
        .method = std.enums.nameCast(httpz.Method, @tagName(method)),
        .protocol = .HTTP11,
        .params = undefined,
        .headers = request_headers,
        .body_buffer = if (options.json) |capture| .{ .data = @constCast(capture), .type = .static } else null,
        .body_len = if (options.json) |capture| capture.len else 0,
        .qs = try keyValue(allocator, 32),
        .fd = try keyValue(allocator, 32),
        .mfd = try multiFormKeyValue(allocator, 32),
        .spare = buf,
        .arena = allocator,
    };
}

fn stubbedResponse(allocator: std.mem.Allocator) !httpz.Response {
    return .{
        .conn = undefined,
        .pos = 0,
        .status = 200,
        .headers = try keyValue(allocator, 32),
        .content_type = null,
        .arena = allocator,
        .written = false,
        .chunked = false,
        .disowned = false,
        .keepalive = false,
        .body = null,
    };
}

fn keyValue(allocator: std.mem.Allocator, max: usize) !httpz.key_value.KeyValue {
    return try httpz.key_value.KeyValue.init(allocator, max);
}

fn multiFormKeyValue(allocator: std.mem.Allocator, max: usize) !httpz.key_value.MultiFormKeyValue {
    return try httpz.key_value.MultiFormKeyValue.init(allocator, max);
}

fn createStore(allocator: std.mem.Allocator) !*jetzig.kv.Store {
    const store = try allocator.create(jetzig.kv.Store);
    store.* = try jetzig.kv.Store.init(allocator, .{});
    return store;
}

fn buildOptions(app: *const App, args: anytype) RequestOptions {
    const fields = switch (@typeInfo(@TypeOf(args))) {
        .Struct => |info| info.fields,
        else => @compileError("Expected struct, found `" ++ @tagName(@typeInfo(@TypeOf(args))) ++ "`"),
    };

    inline for (fields) |field| {
        comptime {
            if (std.mem.eql(u8, field.name, "headers")) continue;
            if (std.mem.eql(u8, field.name, "json")) continue;
            if (std.mem.eql(u8, field.name, "params")) continue;
        }

        @compileError("Unrecognized request option: " ++ field.name);
    }

    return .{
        .headers = if (@hasField(@TypeOf(args), "headers")) args.headers else &.{},
        .json = if (@hasField(@TypeOf(args), "json")) app.json(args.json) else null,
        .params = if (@hasField(@TypeOf(args), "params")) app.params(args.params) else null,
    };
}
