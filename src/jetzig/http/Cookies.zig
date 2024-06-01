const std = @import("std");

const jetzig = @import("../../jetzig.zig");

allocator: std.mem.Allocator,
cookie_string: []const u8,
cookies: std.StringArrayHashMap(*Cookie),
modified: bool = false,
arena: std.heap.ArenaAllocator,

const Self = @This();

const SameSite = enum { strict, lax, none };
pub const CookieOptions = struct {
    domain: []const u8 = "localhost",
    path: []const u8 = "/",
    same_site: ?SameSite = null,
    secure: bool = false,
    expires: ?i64 = null, // if used, set to time in seconds to be added to std.time.timestamp()
    http_only: bool = false,
    max_age: ?i64 = null,
    partitioned: bool = false,
};

const cookie_options = jetzig.config.get(CookieOptions, "cookie_options");

pub const Cookie = struct {
    name: []const u8,
    value: []const u8,
    domain: ?[]const u8 = null,
    path: ?[]const u8 = null,
    same_site: ?SameSite = null,
    secure: ?bool = null,
    expires: ?i64 = null, // if used, set to time in seconds to be added to std.time.timestamp()
    http_only: ?bool = null,
    max_age: ?i64 = null,
    partitioned: ?bool = null,

    /// Build a cookie string.
    pub fn bufPrint(self: Cookie, buf: *[4096]u8) ![]const u8 {
        var options = cookie_options;
        inline for (std.meta.fields(CookieOptions)) |field| {
            @field(options, field.name) = @field(self, field.name) orelse @field(cookie_options, field.name);
        }

        // secure is required if samesite is set to none
        const require_secure = if (options.same_site) |same_site| same_site == .none else false;

        var stream = std.io.fixedBufferStream(buf);
        const writer = stream.writer();

        try writer.print("{s}={s}; path={s}; domain={s};", .{
            self.name,
            self.value,
            options.path,
            options.domain,
        });

        if (options.same_site) |same_site| try writer.print(" SameSite={s};", .{@tagName(same_site)});
        if (options.secure or require_secure) try writer.writeAll(" Secure;");
        if (options.expires) |expires| try writer.print(" Expires={d};", .{std.time.timestamp() + expires});
        if (options.max_age) |max_age| try writer.print(" Max-Age={d};", .{max_age});
        if (options.http_only) try writer.writeAll(" HttpOnly;");
        if (options.partitioned) try writer.writeAll(" Partitioned;");

        return stream.getWritten();
    }

    pub fn applyFlag(self: *Cookie, allocator: std.mem.Allocator, flag: Flag) !void {
        switch (flag) {
            .domain => |domain| self.domain = try allocator.dupe(u8, domain),
            .path => |path| self.path = try allocator.dupe(u8, path),
            .same_site => |same_site| self.same_site = same_site,
            .secure => |secure| self.secure = secure,
            .expires => |expires| self.expires = expires,
            .http_only => |http_only| self.http_only = http_only,
            .max_age => |max_age| self.max_age = max_age,
            .partitioned => |partitioned| self.partitioned = partitioned,
        }
    }
};

pub fn init(allocator: std.mem.Allocator, cookie_string: []const u8) Self {
    return .{
        .allocator = allocator,
        .cookie_string = cookie_string,
        .cookies = std.StringArrayHashMap(*Cookie).init(allocator),
        .arena = std.heap.ArenaAllocator.init(allocator),
    };
}

pub fn deinit(self: *Self) void {
    var it = self.cookies.iterator();
    while (it.next()) |item| {
        self.allocator.free(item.key_ptr.*);
        self.allocator.free(item.value_ptr.*.value);
        self.allocator.destroy(item.value_ptr.*);
    }
    self.cookies.deinit();
    self.arena.deinit();
}

pub fn get(self: *Self, key: []const u8) ?*Cookie {
    return self.cookies.get(key);
}

pub fn put(self: *Self, cookie: Cookie) !void {
    self.modified = true;

    if (self.cookies.fetchSwapRemove(cookie.name)) |entry| {
        self.allocator.free(entry.key);
        self.allocator.free(entry.value.value);
        self.allocator.destroy(entry.value);
    }
    const key = try self.allocator.dupe(u8, cookie.name);
    const ptr = try self.allocator.create(Cookie);
    ptr.* = cookie;
    ptr.name = key;
    ptr.value = try self.allocator.dupe(u8, cookie.value);
    try self.cookies.put(key, ptr);
}

pub const HeaderIterator = struct {
    allocator: std.mem.Allocator,
    cookies_iterator: std.StringArrayHashMap(*Cookie).Iterator,
    buf: *[4096]u8,

    pub fn init(allocator: std.mem.Allocator, cookies: *Self, buf: *[4096]u8) HeaderIterator {
        return .{ .allocator = allocator, .cookies_iterator = cookies.cookies.iterator(), .buf = buf };
    }

    pub fn next(self: *HeaderIterator) !?[]const u8 {
        if (self.cookies_iterator.next()) |entry| {
            const cookie = entry.value_ptr.*;
            return try cookie.bufPrint(self.buf);
        } else {
            return null;
        }
    }
};

pub fn headerIterator(self: *Self, buf: *[4096]u8) HeaderIterator {
    return HeaderIterator.init(self.allocator, self, buf);
}

// https://datatracker.ietf.org/doc/html/rfc6265#section-4.2.1
// cookie-header = "Cookie:" OWS cookie-string OWS
// cookie-string = cookie-pair *( ";" SP cookie-pair )
pub fn parse(self: *Self) !void {
    var key_buf = std.ArrayList(u8).init(self.allocator);
    var value_buf = std.ArrayList(u8).init(self.allocator);
    var key_terminated = false;
    var value_started = false;
    var cookie_buf = std.ArrayList(Cookie).init(self.allocator);

    defer key_buf.deinit();
    defer value_buf.deinit();
    defer cookie_buf.deinit();
    defer self.modified = false;

    for (self.cookie_string, 0..) |char, index| {
        if (char == '=') {
            key_terminated = true;
            continue;
        }

        if (char == ';' or index == self.cookie_string.len - 1) {
            if (char != ';') try value_buf.append(char);
            if (parseFlag(key_buf.items, value_buf.items)) |flag| {
                for (cookie_buf.items) |*cookie| try cookie.applyFlag(self.arena.allocator(), flag);
            } else {
                try cookie_buf.append(.{
                    .name = try self.arena.allocator().dupe(u8, key_buf.items),
                    .value = try self.arena.allocator().dupe(u8, value_buf.items),
                });
            }
            key_buf.clearAndFree();
            value_buf.clearAndFree();
            value_started = false;
            key_terminated = false;
            continue;
        }

        if (!key_terminated and char == ' ') continue;

        if (!key_terminated) {
            try key_buf.append(char);
            continue;
        }

        if (char == ' ' and !value_started) continue;
        if (char != ' ' and !value_started) value_started = true;

        if (key_terminated and value_started) {
            try value_buf.append(char);
            continue;
        }

        return error.JetzigInvalidCookieHeader;
    }

    for (cookie_buf.items) |cookie| try self.put(cookie);
}

const Flag = union(enum) {
    domain: []const u8,
    path: []const u8,
    same_site: SameSite,
    secure: bool,
    expires: i64,
    max_age: i64,
    http_only: bool,
    partitioned: bool,
};

fn parseFlag(key: []const u8, value: []const u8) ?Flag {
    if (key.len > 64) return null;
    if (value.len > 64) return null;

    var key_buf: [64]u8 = undefined;

    const normalized_key = std.ascii.lowerString(&key_buf, jetzig.util.strip(key));
    const normalized_value = jetzig.util.strip(value);

    if (std.mem.eql(u8, normalized_key, "domain")) {
        return .{ .domain = normalized_value };
    } else if (std.mem.eql(u8, normalized_key, "path")) {
        return .{ .path = normalized_value };
    } else if (std.mem.eql(u8, normalized_key, "samesite")) {
        return if (std.mem.eql(u8, normalized_value, "strict"))
            .{ .same_site = .strict }
        else if (std.mem.eql(u8, normalized_value, "lax"))
            .{ .same_site = .lax }
        else
            .{ .same_site = .none };
    } else if (std.mem.eql(u8, normalized_key, "secure")) {
        return .{ .secure = true };
    } else if (std.mem.eql(u8, normalized_key, "httponly")) {
        return .{ .http_only = true };
    } else if (std.mem.eql(u8, normalized_key, "partitioned")) {
        return .{ .partitioned = true };
    } else if (std.mem.eql(u8, normalized_key, "expires")) {
        return .{ .expires = std.fmt.parseInt(i64, normalized_value, 10) catch return null };
    } else if (std.mem.eql(u8, normalized_key, "max-age")) {
        return .{ .max_age = std.fmt.parseInt(i64, normalized_value, 10) catch return null };
    } else {
        return null;
    }
}

test "basic cookie string" {
    const allocator = std.testing.allocator;
    var cookies = Self.init(allocator, "foo=bar; baz=qux;");
    defer cookies.deinit();
    try cookies.parse();
    try std.testing.expectEqualStrings("bar", cookies.get("foo").?.value);
    try std.testing.expectEqualStrings("qux", cookies.get("baz").?.value);
}

test "empty cookie string" {
    const allocator = std.testing.allocator;
    var cookies = Self.init(allocator, "");
    defer cookies.deinit();
    try cookies.parse();
}

test "cookie string with irregular spaces" {
    const allocator = std.testing.allocator;
    var cookies = Self.init(allocator, "foo=   bar;     baz=        qux;");
    defer cookies.deinit();
    try cookies.parse();
    try std.testing.expectEqualStrings("bar", cookies.get("foo").?.value);
    try std.testing.expectEqualStrings("qux", cookies.get("baz").?.value);
}

test "headerIterator" {
    const allocator = std.testing.allocator;
    var buf = std.ArrayList(u8).init(allocator);
    defer buf.deinit();

    const writer = buf.writer();

    var cookies = Self.init(allocator, "foo=bar; baz=qux;");
    defer cookies.deinit();
    try cookies.parse();

    var it_buf: [4096]u8 = undefined;
    var it = cookies.headerIterator(&it_buf);
    while (try it.next()) |*header| {
        try writer.writeAll(header.*);
        try writer.writeAll("\n");
    }

    try std.testing.expectEqualStrings(
        \\foo=bar; path=/; domain=localhost;
        \\baz=qux; path=/; domain=localhost;
        \\
    , buf.items);
}

test "modified" {
    const allocator = std.testing.allocator;
    var cookies = Self.init(allocator, "foo=bar; baz=qux;");
    defer cookies.deinit();

    try cookies.parse();
    try std.testing.expect(cookies.modified == false);

    try cookies.put(.{ .name = "quux", .value = "corge" });
    try std.testing.expect(cookies.modified == true);
}

test "domain=example.com" {
    const allocator = std.testing.allocator;
    var cookies = Self.init(allocator, "foo=bar; baz=qux; Domain=example.com;");
    defer cookies.deinit();

    try cookies.parse();
    const cookie = cookies.get("foo").?;
    try std.testing.expectEqualStrings(cookie.domain.?, "example.com");
}

test "path=/example_path" {
    const allocator = std.testing.allocator;
    var cookies = Self.init(allocator, "foo=bar; baz=qux; Path=/example_path;");
    defer cookies.deinit();

    try cookies.parse();
    const cookie = cookies.get("foo").?;
    try std.testing.expectEqualStrings(cookie.path.?, "/example_path");
}

test "SameSite=lax" {
    const allocator = std.testing.allocator;
    var cookies = Self.init(allocator, "foo=bar; baz=qux; SameSite=lax;");
    defer cookies.deinit();

    try cookies.parse();
    const cookie = cookies.get("foo").?;
    try std.testing.expect(cookie.same_site == .lax);
}

test "SameSite=none" {
    const allocator = std.testing.allocator;
    var cookies = Self.init(allocator, "foo=bar; baz=qux; SameSite=none;");
    defer cookies.deinit();

    try cookies.parse();
    const cookie = cookies.get("foo").?;
    try std.testing.expect(cookie.same_site == .none);
}

test "SameSite=strict" {
    const allocator = std.testing.allocator;
    var cookies = Self.init(allocator, "foo=bar; baz=qux; SameSite=strict;");
    defer cookies.deinit();

    try cookies.parse();
    const cookie = cookies.get("foo").?;
    try std.testing.expect(cookie.same_site == .strict);
}

test "Secure" {
    const allocator = std.testing.allocator;
    var cookies = Self.init(allocator, "foo=bar; baz=qux; Secure;");
    defer cookies.deinit();

    try cookies.parse();
    const cookie = cookies.get("foo").?;
    try std.testing.expect(cookie.secure.?);
}

test "Partitioned" {
    const allocator = std.testing.allocator;
    var cookies = Self.init(allocator, "foo=bar; baz=qux; Partitioned;");
    defer cookies.deinit();

    try cookies.parse();
    const cookie = cookies.get("foo").?;
    try std.testing.expect(cookie.partitioned.?);
}

test "Max-Age" {
    const allocator = std.testing.allocator;
    var cookies = Self.init(allocator, "foo=bar; baz=qux; Max-Age=123123123;");
    defer cookies.deinit();

    try cookies.parse();
    const cookie = cookies.get("foo").?;
    try std.testing.expect(cookie.max_age.? == 123123123);
}

test "Expires" {
    const allocator = std.testing.allocator;
    var cookies = Self.init(allocator, "foo=bar; baz=qux; Expires=123123123;");
    defer cookies.deinit();

    try cookies.parse();
    const cookie = cookies.get("foo").?;
    try std.testing.expect(cookie.expires.? == 123123123);
}

test "default flags" {
    const allocator = std.testing.allocator;
    var cookies = Self.init(allocator, "foo=bar; baz=qux;");
    defer cookies.deinit();

    try cookies.parse();
    const cookie = cookies.get("foo").?;
    try std.testing.expect(cookie.domain == null);
    try std.testing.expect(cookie.path == null);
    try std.testing.expect(cookie.same_site == null);
    try std.testing.expect(cookie.secure == null);
    try std.testing.expect(cookie.expires == null);
    try std.testing.expect(cookie.http_only == null);
    try std.testing.expect(cookie.max_age == null);
    try std.testing.expect(cookie.partitioned == null);
}
