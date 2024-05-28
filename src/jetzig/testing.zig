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

pub const secret = "secret-bytes-for-use-in-test-environment-only";

pub const app = App.init;

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
        log("Expected status: `{}`, actual status: `{}`", .{ expected_code, response.status });
        return error.JetzigExpectStatusError;
    }
}

pub fn expectBodyContains(expected: []const u8, response: TestResponse) !void {
    if (!std.mem.containsAtLeast(u8, response.body, 1, expected)) {
        log(
            "Expected content:\n========\n{s}\n========\n\nActual content:\n========\n{s}\n========",
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
                log("Expected JSON, encountered parser error.", .{});
                return error.JetzigExpectJsonError;
            },
            else => return err,
        }
    };

    const json_banner = "\n======|json|======\n{s}\n======|/json|=====\n";

    if (try data.getValue(std.mem.trimLeft(u8, expected_path, &.{'.'}))) |value| {
        switch (value.*) {
            .string => |string| switch (@typeInfo(@TypeOf(expected_value))) {
                .Pointer, .Array => {
                    if (std.mem.eql(u8, string.value, expected_value)) return;
                },
                .Null => {
                    log(
                        "Expected null/non-existent value for `{s}`, found: `{s}`",
                        .{ expected_path, string.value },
                    );
                    return error.JetzigExpectJsonError;
                },
                else => unreachable,
            },
            .integer => |integer| switch (@typeInfo(@TypeOf(expected_value))) {
                .Int, .ComptimeInt => {
                    if (integer.value == expected_value) return;
                },
                .Null => {
                    log(
                        "Expected null/non-existent value for `{s}`, found: `{}`",
                        .{ expected_path, integer.value },
                    );
                    return error.JetzigExpectJsonError;
                },
                else => {},
            },
            .float => |float| switch (@typeInfo(@TypeOf(expected_value))) {
                .Float, .ComptimeFloat => {
                    if (float.value == expected_value) return;
                },
                .Null => {
                    log(
                        "Expected null/non-existent value for `{s}`, found: `{}`",
                        .{ expected_path, float.value },
                    );
                    return error.JetzigExpectJsonError;
                },
                else => {},
            },
            .boolean => |boolean| switch (@typeInfo(@TypeOf(expected_value))) {
                .Bool => {
                    if (boolean.value == expected_value) return;
                },
                .Null => {
                    log(
                        "Expected null/non-existent value for `{s}`, found: `{}`",
                        .{ expected_path, boolean.value },
                    );
                    return error.JetzigExpectJsonError;
                },
                else => {},
            },
            .Null => switch (@typeInfo(@TypeOf(expected_value))) {
                .Optional => {
                    if (expected_value == null) return;
                },
                .Null => {
                    return;
                },
                else => {},
            },
            else => {},
        }

        switch (value.*) {
            .string => |string| {
                switch (@typeInfo(@TypeOf(expected_value))) {
                    .Pointer, .Array => {
                        log(
                            "Expected `{s}` in `{s}`, found `{s}` in JSON:" ++ json_banner,
                            .{ expected_value, expected_path, string.value, response.body },
                        );
                    },
                    else => unreachable,
                }
            },
            .integer,
            => |integer| {
                switch (@typeInfo(@TypeOf(expected_value))) {
                    .Int, .ComptimeInt => {
                        log(
                            "Expected `{}` in `{s}`, found `{}` in JSON:" ++ json_banner,
                            .{ expected_value, expected_path, integer.value, response.body },
                        );
                    },
                    else => unreachable,
                }
            },
            .float => |float| {
                switch (@typeInfo(@TypeOf(expected_value))) {
                    .Float, .ComptimeFloat => {
                        log(
                            "Expected `{}` in `{s}`, found `{}` in JSON:" ++ json_banner,
                            .{ expected_value, expected_path, float.value, response.body },
                        );
                    },
                    else => unreachable,
                }
            },
            .boolean => |boolean| {
                switch (@typeInfo(@TypeOf(expected_value))) {
                    .Bool => {
                        log(
                            "Expected `{}` in `{s}`, found `{}` in JSON:" ++ json_banner,
                            .{ expected_value, expected_path, boolean.value, response.body },
                        );
                    },
                    else => unreachable,
                }
            },
            .Null => {
                log(
                    "Expected value in `{s}`, found `null` in JSON:" ++ json_banner,
                    .{ expected_path, response.body },
                );
            },
            else => unreachable,
        }
    } else {
        log(
            "Path not found: `{s}` in JSON: " ++ json_banner,
            .{ expected_path, response.body },
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

fn log(comptime message: []const u8, args: anytype) void {
    std.debug.print("[jetzig.testing] " ++ message ++ "\n", args);
}
