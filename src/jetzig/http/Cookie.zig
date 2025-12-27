const Cookie = @This();

name: [64:0]u8 = std.mem.zeroes([64:0]u8),
value: [2048:0]u8 = std.mem.zeroes([2048:0]u8),
// instead of nullable buffers we'll just zero them when not in use
path: [256:0]u8 = std.mem.zeroes([256:0]u8),
domain: [256:0]u8 = std.mem.zeroes([256:0]u8),
// Stringified; 38 bytes
expires: ?i64 = null,
// max value; 29 bytes
@"max-age": ?i64 = null,
// Secure; 7 bytes
secure: bool = false,
// HttpOnly; 9 bytes
httponly: bool = false,
// Partitioned; 12 bytes
partitioned: bool = false,
// SameSite=Strict; 16 bytes
samesite: ?SameSite = null,

const empty: Cookie = .{
    .name = std.mem.zeroes([64:0]u8),
    .value = std.mem.zeroes([2048:0]u8),
    .path = std.mem.zeroes([256:0]u8),
    .domain = std.mem.zeroes([256:0]u8),
    .expires = null,
    .@"max-age" = null,
    .secure = false,
    .httponly = false,
    .partitioned = false,
    .samesite = null,
};

pub fn parse(string: []const u8) !Cookie {
    var cookie: Cookie = .{};
    var iterator = std.mem.splitScalar(u8, string, ';');
    while (iterator.next()) |segment| {
        var sections = std.mem.splitScalar(u8, segment, '=');
        var buf = std.mem.zeroes([64:0]u8);
        const stripped = trim(sections.first());
        if (stripped.len == 0) continue;
        const key = std.ascii.lowerString(&buf, stripped)[0..stripped.len];
        const value = trim(sections.next() orelse "");
        switch (stringToEnum(Flags, key) orelse .name) {
            // just in case someone named the cookie "value"
            .name, .value => {
                try cookie.set(.{ .name = key });
                try cookie.set(.{ .value = value });
            },
            .path => try cookie.set(.{
                .path = value,
            }),
            .domain => try cookie.set(.{
                .domain = value,
            }),
            .expires => try cookie.set(.{
                .expires = std.fmt.parseInt(i64, value, 10) catch null,
            }),
            .@"max-age" => try cookie.set(.{
                .@"max-age" = std.fmt.parseInt(i64, value, 10) catch null,
            }),
            .secure => try cookie.set(.{
                .secure = if (value.len == 0) true else trueFalse(value),
            }),
            .httponly => try cookie.set(.{
                .httponly = if (value.len == 0) true else trueFalse(value),
            }),
            .partitioned => try cookie.set(.{
                .partitioned = if (value.len == 0) true else trueFalse(value),
            }),
            .samesite => try cookie.set(.{
                .samesite = stringToEnum(SameSite, value),
            }),
        }
    }
    return cookie;
}

test "cookie parse test" {
    var cookie: Cookie = try .parse("foo=bar;path=/;domain=localhost;max-age=100;secure;httponly;partitioned;samesite=strict;");
    _ = &cookie;
    try testing.expectEqualStrings("foo", cookie.get(.name));
    try testing.expectEqualStrings("bar", cookie.get(.value));
    try testing.expectEqualStrings("/", cookie.get(.path));
    try testing.expectEqualStrings("localhost", cookie.get(.domain));
    try testing.expectEqual(100, cookie.get(.@"max-age"));
    try testing.expectEqual(true, cookie.get(.httponly));
    try testing.expectEqual(true, cookie.get(.partitioned));
    try testing.expectEqual(true, cookie.get(.secure));
    try testing.expectEqual(.strict, cookie.get(.samesite));
}

pub fn init(name: []const u8, value: []const u8, options: Options) !Cookie {
    var cookie: Cookie = .{
        .expires = options.expires,
        .@"max-age" = options.@"max-age",
        .samesite = options.samesite,
        .secure = options.secure orelse false,
        .httponly = options.httponly orelse false,
        .partitioned = options.partitioned orelse false,
    };
    try cookie.set(.{ .name = name });
    try cookie.set(.{ .value = value });
    try cookie.set(.{ .path = options.path });
    try cookie.set(.{ .domain = options.domain });
    return cookie;
}

/// convenience function, mostly to turn buffers into `[]const u8`
pub fn get(self: *const Cookie, comptime flag: Flags) switch (flag) {
    .name, .value, .path, .domain => []const u8,
    .secure, .httponly, .partitioned => bool,
    .expires, .@"max-age" => ?i64,
    .samesite => ?SameSite,
} {
    return switch (flag) {
        .name => sliceTo(&self.name, 0),
        .value => sliceTo(&self.value, 0),
        .path => sliceTo(&self.path, 0),
        .domain => sliceTo(&self.domain, 0),
        .expires => self.expires,
        .@"max-age" => self.@"max-age",
        .httponly => self.httponly,
        .partitioned => self.partitioned,
        .secure => self.secure,
        .samesite => self.samesite,
    };
}

pub fn set(self: *Cookie, flag: Flag) !void {
    switch (flag) {
        inline .name, .value => |string, tag| {
            var field = &@field(self, @tagName(tag));
            if (string.len > field.len - 1) return error.BufferOverflow;
            @memcpy(field[0..string.len], string);
            @memset(field[string.len..], 0);
        },
        inline .path, .domain => |string, tag| {
            const value = string orelse "";
            var field = &@field(self, @tagName(tag));
            if (value.len > field.len - 1) return error.BufferOverflow;
            @memcpy(field[0..value.len], value);
            @memset(field[value.len..], 0);
        },
        inline .expires, .@"max-age" => |i, tag| {
            @field(self, @tagName(tag)) = i;
        },
        inline .secure, .httponly, .partitioned => |b, tag| {
            @field(self, @tagName(tag)) = b;
        },
        .samesite => |samesite| self.samesite = samesite,
    }
}

pub fn format(self: *const Cookie, writer: *Writer) !void {
    try writer.print(
        "{[name]s}={[value]s};path={[path]s};",
        .{
            .name = sliceTo(&self.name, 0),
            .value = sliceTo(&self.value, 0),
            .path = if (self.path[0] == 0) "/" else sliceTo(&self.path, 0),
        },
    );
    if (self.domain[0] != 0)
        try writer.print("domain={s};", .{std.mem.sliceTo(&self.domain, 0)});
    if (self.samesite) |samesite|
        try writer.print("samesite={s};", .{@tagName(samesite)});
    if (self.expires) |expires| {
        const seconds = std.time.timestamp() + expires;
        const timestamp = try jetcommon.DateTime.fromUnix(seconds, .seconds);
        // https://developer.mozilla.org/en-US/docs/Web/HTTP/Headers/Set-Cookie#expiresdate
        try timestamp.strftime(writer, "expires=%a, %d %h %Y %H:%M:%S GMT;");
    }
    if (self.@"max-age") |max_age| try writer.print("max-age={d};", .{max_age});
    if (self.httponly) try writer.writeAll("httponly;");
    if (self.partitioned) try writer.writeAll("partitioned;");
    const require_secure = if (self.samesite) |samesite|
        samesite == .none
    else
        false;
    if (self.secure or require_secure) try writer.writeAll("secure;");
}

// test "format test" {
//     var cookie: Cookie = try .init("new", "value", .{});
//     try cookie.set(.{ .value = "jetcommon" });
//     var buf: Writer.Allocating = .init(testing.allocator);
//     defer buf.deinit();
//     try buf.writer.print("{f}", .{cookie});
//     const output = try buf.toOwnedSlice();
//     defer testing.allocator.free(output);
//     try testing.expectEqualStrings("new=jetcommon;Path=/;", output);
// }
//
// test "default test" {
//     var cookie: Cookie = try .init("new", "title", .default);
//     try cookie.set(.{ .value = "defaults" });
//     var buf: Writer.Allocating = .init(testing.allocator);
//     defer buf.deinit();
//     try buf.writer.print("{f}", .{cookie});
//     const output = try buf.toOwnedSlice();
//     defer testing.allocator.free(output);
//     try testing.expectEqualStrings("new=defaults;Path=/;Domain=localhost;", output);
// }

/// returns formatted
pub fn bufPrint(self: *Cookie, buf: *[MaxLength]u8) ![]const u8 {
    @memset(buf, 0);
    var writer: Writer = .fixed(buf);
    try self.format(&writer);
    return writer.buffered();
}

pub fn printAlloc(self: *Cookie, allocator: Allocator) ![]const u8 {
    var buf: [MaxLength]u8 = undefined;
    const string = try self.bufPrint(&buf);
    return allocator.dupe(u8, string);
}

pub const Options = struct {
    path: ?[]const u8 = "/",
    domain: ?[]const u8 = "localhost",
    expires: ?i64 = null,
    @"max-age": ?i64 = null,
    httponly: ?bool = null,
    secure: ?bool = null,
    partitioned: ?bool = null,
    samesite: ?SameSite = null,

    pub const default: Options = .{
        .path = cookie_options.path orelse "/",
        .domain = cookie_options.domain orelse "localhost",
        .expires = null,
        .httponly = false,
        .@"max-age" = 0,
        .samesite = .none,
        .partitioned = false,
        .secure = false,
    };
};

/// not sure these really should be accessed outside of Cookie.zig but leaving
/// public for now
pub const Flags = enum {
    name,
    value,
    path,
    domain,
    expires,
    @"max-age",
    samesite,
    httponly,
    secure,
    partitioned,
};

pub const Flag = union(Flags) {
    name: []const u8,
    value: []const u8,
    path: ?[]const u8,
    domain: ?[]const u8,
    expires: ?i64,
    @"max-age": ?i64,
    samesite: ?SameSite,
    httponly: bool,
    secure: bool,
    partitioned: bool,
};

pub const SameSite = enum(u2) { strict, lax, none };

const std = @import("std");
const testing = std.testing;
const Writer = std.Io.Writer;
const Allocator = std.mem.Allocator;
const stringToEnum = std.meta.stringToEnum;
const sliceTo = std.mem.sliceTo;

const jetcommon = @import("jetcommon");
const jetzig = @import("../../jetzig.zig");
const cookie_options = jetzig.config.get(Options, "cookies");

/// maximum cookie length
pub const MaxLength: usize = 4096;

fn trim(string: []const u8) []const u8 {
    return std.mem.trim(u8, string, &std.ascii.whitespace);
}

fn replace(slice: []u8, match: u8, replacement: u8) void {
    return std.mem.replaceScalar(u8, slice, match, replacement);
}

fn trueFalse(string: []const u8) bool {
    return std.ascii.eqlIgnoreCase("true", string);
}

//4096 total bytes
//3471
//627
