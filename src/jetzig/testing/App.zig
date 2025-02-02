const std = @import("std");

const jetzig = @import("../../jetzig.zig");
const httpz = @import("httpz");

const App = @This();
const MemoryStore = jetzig.kv.Store.Generic(.{ .backend = .memory });

allocator: std.mem.Allocator,
routes: []const jetzig.views.Route,
arena: *std.heap.ArenaAllocator,
store: *MemoryStore,
cache: *MemoryStore,
job_queue: *MemoryStore,
multipart_boundary: ?[]const u8 = null,
logger: jetzig.loggers.Logger,
server: Server,
repo: *jetzig.database.Repo,
cookies: *jetzig.http.Cookies,
session: *jetzig.http.Session,

const Server = struct { logger: jetzig.loggers.Logger };

const initHook = jetzig.root.initHook;

/// Initialize a new test app.
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

    var dir = try std.fs.cwd().makeOpenPath("log", .{});
    const file = try dir.createFile("test.log", .{ .exclusive = false, .truncate = false });

    const logger = jetzig.loggers.Logger{
        .test_logger = jetzig.loggers.TestLogger{ .mode = .file, .file = file },
    };

    const alloc = arena.allocator();
    const app = try alloc.create(App);
    const repo = try alloc.create(jetzig.database.Repo);

    const cookies = try alloc.create(jetzig.http.Cookies);
    cookies.* = jetzig.http.Cookies.init(alloc, "");
    try cookies.parse();

    const session = try alloc.create(jetzig.http.Session);
    session.* = jetzig.http.Session.init(alloc, cookies, jetzig.testing.secret);

    app.* = App{
        .arena = arena,
        .allocator = allocator,
        .routes = &routes_module.routes,
        .store = try createStore(arena.allocator(), logger, .general),
        .cache = try createStore(arena.allocator(), logger, .cache),
        .job_queue = try createStore(arena.allocator(), logger, .jobs),
        .logger = logger,
        .server = .{ .logger = logger },
        .repo = repo,
        .cookies = cookies,
        .session = session,
    };

    repo.* = try jetzig.database.repo(alloc, app.*);

    return app.*;
}

/// Free allocated resources for test app.
pub fn deinit(self: *App) void {
    self.arena.deinit();
    self.allocator.destroy(self.arena);
    if (self.logger.test_logger.file) |file| file.close();
}

const RequestOptions = struct {
    headers: []const jetzig.testing.TestResponse.Header = &.{},
    json: ?[]const u8 = null,
    params: ?[]Param = null,
    body: ?[]const u8 = null,

    pub fn getBody(self: RequestOptions) ?[]const u8 {
        if (self.json) |capture| return capture;
        if (self.body) |capture| return capture;

        return null;
    }

    pub fn bodyLen(self: RequestOptions) usize {
        if (self.json) |capture| return capture.len;
        if (self.body) |capture| return capture.len;

        return 0;
    }
};

const Param = struct {
    key: []const u8,
    value: ?[]const u8,
};

/// Issue a request to the test server.
pub fn request(
    self: *App,
    comptime method: jetzig.http.Request.Method,
    comptime path: []const u8,
    args: anytype,
) !jetzig.testing.TestResponse {
    const allocator = self.arena.allocator();

    const options = try buildOptions(allocator, self, args);
    const routes = try jetzig.App.createRoutes(allocator, self.routes);

    var log_queue = jetzig.loggers.LogQueue.init(allocator);

    // We init the `std.process.EnvMap` directly here (instead of calling `std.process.getEnvMap`
    // to ensure that tests run in a clean environment. Users can manually add items to the
    // environment within a test if required.
    const vars = jetzig.Environment.Vars{
        .env_map = std.process.EnvMap.init(allocator),
        .env_file = null,
    };
    var server = jetzig.http.Server{
        .allocator = allocator,
        .logger = self.logger,
        .env = .{
            .parent_allocator = undefined,
            .arena = undefined,
            .allocator = allocator,
            .vars = vars,
            .logger = self.logger,
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
        .global = undefined,
        .repo = self.repo,
    };

    try server.decodeStaticParams();

    var buf: [1024]u8 = undefined;
    var httpz_request = try stubbedRequest(
        allocator,
        &buf,
        method,
        path,
        self.multipart_boundary,
        options,
        self.cookies,
    );
    var httpz_response = try stubbedResponse(allocator);

    try server.processNextRequest(&httpz_request, &httpz_response);

    {
        const cookies = try allocator.create(jetzig.http.Cookies);
        cookies.* = jetzig.http.Cookies.init(allocator, "");
        try cookies.parse();
        self.cookies = cookies;
    }

    var headers = std.ArrayList(jetzig.testing.TestResponse.Header).init(allocator);
    for (0..httpz_response.headers.len) |index| {
        const key = httpz_response.headers.keys[index];
        const value = httpz_response.headers.values[index];

        try headers.append(.{
            .name = try allocator.dupe(u8, key),
            .value = try allocator.dupe(u8, httpz_response.headers.values[index]),
        });

        if (std.ascii.eqlIgnoreCase(key, "set-cookie")) {
            // FIXME: We only expect one set-cookie header at the moment.
            const cookies = try allocator.create(jetzig.http.Cookies);
            cookies.* = jetzig.http.Cookies.init(allocator, value);
            self.cookies = cookies;
            try self.cookies.parse();
        }
    }

    var data = jetzig.data.Data.init(allocator);
    defer data.deinit();

    var jobs = std.ArrayList(jetzig.testing.TestResponse.Job).init(allocator);
    while (try self.job_queue.popFirst(&data, "__jetzig_jobs")) |value| {
        if (value.getT(.string, "__jetzig_job_name")) |job_name| try jobs.append(.{
            .name = try allocator.dupe(u8, job_name),
        });
    }

    try self.initSession();

    return .{
        .allocator = allocator,
        .status = httpz_response.status,
        .body = try allocator.dupe(u8, httpz_response.body),
        .headers = try headers.toOwnedSlice(),
        .jobs = try jobs.toOwnedSlice(),
    };
}

/// Generate query params to use with a request.
pub fn params(self: App, args: anytype) []Param {
    const allocator = self.arena.allocator();
    var array = std.ArrayList(Param).init(allocator);
    inline for (@typeInfo(@TypeOf(args)).@"struct".fields) |field| {
        const value = coerceString(allocator, @field(args, field.name));
        array.append(.{ .key = field.name, .value = value }) catch @panic("OOM");
    }
    return array.toOwnedSlice() catch @panic("OOM");
}

pub fn initSession(self: *App) !void {
    const allocator = self.arena.allocator();

    var local_session = try allocator.create(jetzig.http.Session);
    local_session.* = jetzig.http.Session.init(allocator, self.cookies, jetzig.testing.secret);
    try local_session.parse();

    self.session = local_session;
}

/// Encode an arbitrary struct to a JSON string for use as a request body.
pub fn json(self: App, args: anytype) []const u8 {
    const allocator = self.arena.allocator();
    return std.json.stringifyAlloc(allocator, args, .{}) catch @panic("OOM");
}

/// Generate a `multipart/form-data`-encoded request body.
pub fn multipart(self: *App, comptime args: anytype) []const u8 {
    var buf = std.ArrayList(u8).init(self.arena.allocator());
    const writer = buf.writer();
    var boundary_buf: [16]u8 = undefined;

    const boundary = jetzig.util.generateRandomString(&boundary_buf);
    self.multipart_boundary = boundary;

    inline for (@typeInfo(@TypeOf(args)).@"struct".fields, 0..) |field, index| {
        if (index > 0) tryWrite(writer, "\r\n");
        tryWrite(writer, "--");
        tryWrite(writer, boundary);
        tryWrite(writer, "\r\n");
        switch (@TypeOf(@field(args, field.name))) {
            jetzig.testing.File => {
                const header = std.fmt.comptimePrint(
                    \\Content-Disposition: form-data; name="{s}"; filename="{s}"
                , .{ field.name, @field(args, field.name).filename });
                tryWrite(writer, header ++ "\r\n\r\n");
                tryWrite(writer, @field(args, field.name).content);
            },
            // Assume a string, let Zig fail for us if not.
            else => {
                tryWrite(
                    writer,
                    "Content-Disposition: form-data; name=\"" ++ field.name ++ "\"\r\n\r\n",
                );
                tryWrite(writer, @field(args, field.name));
            },
        }
    }

    tryWrite(writer, "\r\n--");
    tryWrite(writer, boundary);
    tryWrite(writer, "--\r\n");
    return buf.toOwnedSlice() catch @panic("OOM");
}

fn tryWrite(writer: anytype, data: []const u8) void {
    writer.writeAll(data) catch @panic("OOM");
}

fn stubbedRequest(
    allocator: std.mem.Allocator,
    buf: []u8,
    comptime method: jetzig.http.Request.Method,
    comptime path: []const u8,
    multipart_boundary: ?[]const u8,
    options: RequestOptions,
    maybe_cookies: ?*const jetzig.http.Cookies,
) !httpz.Request {
    // TODO: Use httpz.testing
    var request_headers = try keyValue(allocator, 32);
    for (options.headers) |header| request_headers.add(header.name, header.value);

    if (maybe_cookies) |cookies| {
        var cookie_buf = std.ArrayList(u8).init(allocator);
        const cookie_writer = cookie_buf.writer();
        try cookie_writer.print("{}", .{cookies});
        const cookie = try cookie_buf.toOwnedSlice();
        request_headers.add("cookie", cookie);
    }

    if (options.json != null) {
        request_headers.add("accept", "application/json");
        request_headers.add("content-type", "application/json");
    } else if (multipart_boundary) |boundary| {
        const header = try std.mem.concat(
            allocator,
            u8,
            &.{ "multipart/form-data; boundary=", boundary },
        );
        request_headers.add("content-type", header);
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
        .route_data = null,
        .middlewares = undefined,
        .address = undefined,
        .method = std.enums.nameCast(httpz.Method, @tagName(method)),
        .protocol = .HTTP11,
        .params = undefined,
        .conn = undefined,
        .method_string = undefined,
        .unread_body = undefined,
        .headers = request_headers,
        .body_buffer = if (options.getBody()) |capture|
            .{ .data = @constCast(capture), .type = .static }
        else
            null,
        .body_len = options.bodyLen(),
        .qs = try keyValue(allocator, 32),
        .fd = try keyValue(allocator, 32),
        .mfd = try multiFormKeyValue(allocator, 32),
        .spare = buf,
        .arena = allocator,
    };
}

fn stubbedResponse(allocator: std.mem.Allocator) !httpz.Response {
    // TODO: Use httpz.testing
    return .{
        .conn = undefined,
        .pos = 0,
        .status = 200,
        .headers = (try keyValue(allocator, 32)).*,
        .content_type = null,
        .arena = allocator,
        .written = false,
        .chunked = false,
        .keepalive = false,
        .body = "",
        .buffer = .{ .pos = 0, .data = "" },
    };
}

fn keyValue(allocator: std.mem.Allocator, max: usize) !*httpz.key_value.StringKeyValue {
    const key_value = try allocator.create(httpz.key_value.StringKeyValue);
    key_value.* = try httpz.key_value.StringKeyValue.init(allocator, max);
    return key_value;
}

fn multiFormKeyValue(allocator: std.mem.Allocator, max: usize) !*httpz.key_value.MultiFormKeyValue {
    const key_value = try allocator.create(httpz.key_value.MultiFormKeyValue);
    key_value.* = try httpz.key_value.MultiFormKeyValue.init(allocator, max);
    return key_value;
}

fn createStore(
    allocator: std.mem.Allocator,
    logger: jetzig.loggers.Logger,
    role: jetzig.kv.Store.Role,
) !*MemoryStore {
    const store = try allocator.create(MemoryStore);
    store.* = try MemoryStore.init(
        allocator,
        logger,
        role,
    );
    return store;
}

fn buildOptions(allocator: std.mem.Allocator, app: *const App, args: anytype) !RequestOptions {
    const fields = switch (@typeInfo(@TypeOf(args))) {
        .@"struct" => |info| info.fields,
        else => @compileError("Expected struct, found `" ++ @tagName(@typeInfo(@TypeOf(args))) ++ "`"),
    };

    inline for (fields) |field| {
        comptime {
            if (std.mem.eql(u8, field.name, "headers")) continue;
            if (std.mem.eql(u8, field.name, "json")) continue;
            if (std.mem.eql(u8, field.name, "params")) continue;
            if (std.mem.eql(u8, field.name, "body")) continue;
        }

        @compileError(std.fmt.comptimePrint(
            "Unrecognized request option `{s}`. Expected: {{ {s}, {s}, {s}, {s} }}",
            .{
                jetzig.colors.yellow(field.name),
                jetzig.colors.cyan("headers"),
                jetzig.colors.cyan("json"),
                jetzig.colors.cyan("params"),
                jetzig.colors.cyan("body"),
            },
        ));
    }

    return .{
        .headers = if (@hasField(@TypeOf(args), "headers"))
            try buildHeaders(allocator, args.headers)
        else
            &.{},
        .json = if (@hasField(@TypeOf(args), "json")) app.json(args.json) else null,
        .params = if (@hasField(@TypeOf(args), "params")) app.params(args.params) else null,
        .body = if (@hasField(@TypeOf(args), "body")) args.body else null,
    };
}

fn buildHeaders(allocator: std.mem.Allocator, args: anytype) ![]const jetzig.testing.TestResponse.Header {
    var headers = std.ArrayList(jetzig.testing.TestResponse.Header).init(allocator);
    inline for (std.meta.fields(@TypeOf(args))) |field| {
        try headers.append(
            jetzig.testing.TestResponse.Header{
                .name = field.name,
                .value = @field(args, field.name),
            },
        );
    }
    return try headers.toOwnedSlice();
}

fn coerceString(allocator: std.mem.Allocator, value: anytype) []const u8 {
    return switch (@typeInfo(@TypeOf(value))) {
        .int,
        .float,
        .comptime_int,
        .comptime_float,
        => std.fmt.allocPrint(allocator, "{d}", .{value}) catch @panic("OOM"),
        else => value, // TODO: Handle more complex types - arrays, objects, etc.
    };
}
