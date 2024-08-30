const std = @import("std");

const jetzig = @import("../jetzig.zig");
const zmpl = @import("zmpl");
const httpz = @import("httpz");

/// An app used for testing. Processes requests and renders responses.
pub const App = @import("testing/App.zig");

const testing = @This();

/// Pre-built mime map, assigned by Jetzig test runner.
pub var mime_map: *jetzig.http.mime.MimeMap = undefined;
pub var state: enum { initial, ready } = .initial;
pub var logger: Logger = undefined;

pub const secret = "secret-bytes-for-use-in-test-environment-only";

pub const app = App.init;

pub const Logger = struct {
    allocator: std.mem.Allocator,
    logs: std.AutoHashMap(usize, *LogCollection),
    index: usize = 0,

    pub const LogEvent = struct {
        level: std.log.Level,
        output: []const u8,
    };

    const LogCollection = std.ArrayList(LogEvent);

    pub fn init(allocator: std.mem.Allocator) Logger {
        return .{
            .allocator = allocator,
            .logs = std.AutoHashMap(usize, *LogCollection).init(allocator),
        };
    }

    pub fn log(
        self: *Logger,
        comptime message_level: std.log.Level,
        comptime scope: @Type(.enum_literal),
        comptime format: []const u8,
        args: anytype,
    ) void {
        _ = scope;
        const output = std.fmt.allocPrint(self.allocator, format, args) catch @panic("OOM");
        const log_event: LogEvent = .{ .level = message_level, .output = output };
        if (self.logs.get(self.index)) |*item| {
            item.*.append(log_event) catch @panic("OOM");
        } else {
            const array = self.allocator.create(LogCollection) catch @panic("OOM");
            array.* = LogCollection.init(self.allocator);
            array.append(log_event) catch @panic("OOM");
            self.logs.put(self.index, array) catch @panic("OOM");
        }
    }
};

pub const TestResponse = struct {
    allocator: std.mem.Allocator,
    status: u16,
    body: []const u8,
    headers: []const Header,
    jobs: []Job,

    pub const Header = struct { name: []const u8, value: []const u8 };
    pub const Job = struct { name: []const u8, params: ?[]const u8 = null };

    pub fn expectStatus(self: TestResponse, comptime expected: jetzig.http.status_codes.StatusCode) !void {
        try testing.expectStatus(expected, self);
    }

    pub fn expectBodyContains(self: TestResponse, comptime expected: []const u8) !void {
        try testing.expectBodyContains(expected, self);
    }

    pub fn expectJson(self: TestResponse, expected_path: []const u8, expected_value: anytype) !void {
        try testing.expectJson(expected_path, expected_value, self);
    }

    pub fn expectHeader(self: TestResponse, expected_name: []const u8, expected_value: ?[]const u8) !void {
        try testing.expectHeader(expected_name, expected_value, self);
    }

    pub fn expectRedirect(self: TestResponse, path: []const u8) !void {
        try testing.expectRedirect(path, self);
    }

    pub fn expectJob(self: TestResponse, job_name: []const u8, job_params: anytype) !void {
        try testing.expectJob(job_name, job_params, self);
    }
};

pub fn expectStatus(comptime expected: jetzig.http.status_codes.StatusCode, response: TestResponse) !void {
    const expected_code = try jetzig.http.status_codes.get(expected).getCodeInt();

    if (response.status != expected_code) {
        logFailure(
            "Expected status: " ++ jetzig.colors.green("{}") ++ ", actual status: " ++ jetzig.colors.red("{}"),
            .{ expected_code, response.status },
        );
        return error.JetzigExpectStatusError;
    }
}

pub fn expectBodyContains(expected: []const u8, response: TestResponse) !void {
    if (!std.mem.containsAtLeast(u8, response.body, 1, expected)) {
        logFailure(
            "\nExpected content:\n" ++
                jetzig.colors.red("{s}") ++
                "\n\nActual content:\n" ++
                jetzig.colors.green("{s}") ++
                "\n",
            .{ expected, response.body },
        );
        return error.JetzigExpectBodyContainsError;
    }
}

pub fn expectHeader(expected_name: []const u8, expected_value: ?[]const u8, response: TestResponse) !void {
    for (response.headers) |header| {
        if (!std.ascii.eqlIgnoreCase(header.name, expected_name)) continue;
        if (expected_value) |value| {
            if (std.mem.eql(u8, header.value, value)) return;
        } else {
            return;
        }
    }
    return error.JetzigExpectHeaderError;
}

pub fn expectRedirect(path: []const u8, response: TestResponse) !void {
    if (response.status != 301 or response.status != 302) return error.JetzigExpectRedirectError;

    try expectHeader("location", path, response);
}

pub fn expectJson(expected_path: []const u8, expected_value: anytype, response: TestResponse) !void {
    var data = zmpl.Data.init(response.allocator);
    data.fromJson(response.body) catch |err| {
        switch (err) {
            error.SyntaxError => {
                logFailure("Expected JSON, encountered parser error.", .{});
                return error.JetzigExpectJsonError;
            },
            else => return err,
        }
    };

    const json_banner = "\n{s}";

    if (try data.getValue(std.mem.trimLeft(u8, expected_path, &.{'.'}))) |value| {
        switch (value.*) {
            .string => |string| switch (@typeInfo(@TypeOf(expected_value))) {
                .pointer, .array => {
                    if (std.mem.eql(u8, string.value, expected_value)) return;
                },
                .null => {
                    logFailure(
                        "Expected null/non-existent value for " ++ jetzig.colors.cyan("{s}") ++ ", found: " ++ jetzig.colors.cyan("{s}"),
                        .{ expected_path, string.value },
                    );
                    return error.JetzigExpectJsonError;
                },
                else => unreachable,
            },
            .integer => |integer| switch (@typeInfo(@TypeOf(expected_value))) {
                .int, .comptime_int => {
                    if (integer.value == expected_value) return;
                },
                .null => {
                    logFailure(
                        "Expected null/non-existent value for " ++ jetzig.colors.cyan("{s}") ++ ", found: " ++ jetzig.colors.green("{}"),
                        .{ expected_path, integer.value },
                    );
                    return error.JetzigExpectJsonError;
                },
                else => {},
            },
            .float => |float| switch (@typeInfo(@TypeOf(expected_value))) {
                .float, .comptime_float => {
                    if (float.value == expected_value) return;
                },
                .null => {
                    logFailure(
                        "Expected null/non-existent value for " ++ jetzig.colors.cyan("{s}") ++ ", found: " ++ jetzig.colors.green("{}"),
                        .{ expected_path, float.value },
                    );
                    return error.JetzigExpectJsonError;
                },
                else => {},
            },
            .boolean => |boolean| switch (@typeInfo(@TypeOf(expected_value))) {
                .bool => {
                    if (boolean.value == expected_value) return;
                },
                .null => {
                    logFailure(
                        "Expected null/non-existent value for " ++ jetzig.colors.cyan("{s}") ++ ", found: " ++ jetzig.colors.green("{}"),
                        .{ expected_path, boolean.value },
                    );
                    return error.JetzigExpectJsonError;
                },
                else => {},
            },
            .Null => switch (@typeInfo(@TypeOf(expected_value))) {
                .optional => {
                    if (expected_value == null) return;
                },
                .null => {
                    return;
                },
                else => {},
            },
            else => {},
        }

        switch (value.*) {
            .string => |string| {
                switch (@typeInfo(@TypeOf(expected_value))) {
                    .pointer, .array => {
                        logFailure(
                            "Expected \"" ++ jetzig.colors.red("{s}") ++ "\" in " ++ jetzig.colors.cyan("{s}") ++ ", found \"" ++ jetzig.colors.green("{s}") ++ "\"\nJSON:" ++ json_banner,
                            .{ expected_value, expected_path, string.value, try jsonPretty(response) },
                        );
                    },
                    else => unreachable,
                }
            },
            .integer,
            => |integer| {
                switch (@typeInfo(@TypeOf(expected_value))) {
                    .int, .comptime_int => {
                        logFailure(
                            "Expected " ++ jetzig.colors.red("{}") ++ " in " ++ jetzig.colors.cyan("{s}") ++ ", found " ++ jetzig.colors.green("{}") ++ "\nJSON:" ++ json_banner,

                            .{ expected_value, expected_path, integer.value, try jsonPretty(response) },
                        );
                    },
                    else => unreachable,
                }
            },
            .float => |float| {
                switch (@typeInfo(@TypeOf(expected_value))) {
                    .float, .comptime_float => {
                        logFailure(
                            "Expected " ++ jetzig.colors.red("{}") ++ " in " ++ jetzig.colors.cyan("{s}") ++ ", found " ++ jetzig.colors.green("{}") ++ "\nJSON:" ++ json_banner,
                            .{ expected_value, expected_path, float.value, try jsonPretty(response) },
                        );
                    },
                    else => unreachable,
                }
            },
            .boolean => |boolean| {
                switch (@typeInfo(@TypeOf(expected_value))) {
                    .bool => {
                        logFailure(
                            "Expected " ++ jetzig.colors.red("{}") ++ " in " ++ jetzig.colors.cyan("{s}") ++ ", found " ++ jetzig.colors.green("{}") ++ "\nJSON:" ++ json_banner,
                            .{ expected_value, expected_path, boolean.value, try jsonPretty(response) },
                        );
                    },
                    else => unreachable,
                }
            },
            .Null => {
                logFailure(
                    "Expected value in " ++ jetzig.colors.cyan("{s}") ++ ", found " ++ jetzig.colors.green("null") ++ "\nJSON:" ++ json_banner,
                    .{ expected_path, try jsonPretty(response) },
                );
            },
            else => unreachable,
        }
    } else {
        logFailure(
            "Path not found: `{s}`\nJSON: " ++ json_banner,
            .{ expected_path, try jsonPretty(response) },
        );
    }
    return error.JetzigExpectJsonError;
}

pub fn expectJob(job_name: []const u8, job_params: anytype, response: TestResponse) !void {
    for (response.jobs) |job| {
        comptime var has_args = false;
        inline for (@typeInfo(@TypeOf(job_params)).Struct.fields) |field| {
            has_args = true;
            _ = field;
        }
        if (!has_args and std.mem.eql(u8, job_name, job.name)) return;
    }
    return error.JetzigExpectJobError;
}

pub const File = struct { filename: []const u8, content: []const u8 };
pub fn file(comptime filename: []const u8, comptime content: []const u8) File {
    return .{ .filename = filename, .content = content };
}

fn logFailure(comptime message: []const u8, args: anytype) void {
    std.log.err("[jetzig.testing] " ++ message, args);
}

fn jsonPretty(response: TestResponse) ![]const u8 {
    var data = jetzig.data.Data.init(response.allocator);
    defer data.deinit();

    try data.fromJson(response.body);
    return try data.toJsonOptions(.{ .pretty = true, .color = true });
}
