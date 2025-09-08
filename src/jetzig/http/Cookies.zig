const std = @import("std");
const Allocator = std.mem.Allocator;
const ArenaAllocator = std.heap.ArenaAllocator;
const Writer = std.Io.Writer;
const ArrayList = std.ArrayList;
const StringArrayHashMap = std.StringArrayHashMap;

const jetzig = @import("../../jetzig.zig");

//allocator: Allocator,
cookie_string: []const u8,
cookies: StringArrayHashMap(*Cookie),
modified: bool = false,
arena: ArenaAllocator,

const Cookies = @This();

const SameSite = enum { strict, lax, none };
pub const CookieOptions = struct {
    domain: ?[]const u8 = "localhost",
    path: []const u8 = "/",
    secure: bool = false,
    http_only: bool = false,
    partitioned: bool = false,
    same_site: ?SameSite = null,
    expires: ?i64 = null, // if used, set to time in seconds to be added to std.time.timestamp()
    max_age: ?i64 = null,
};

const cookie_options = jetzig.config.get(CookieOptions, "cookies");

pub const Cookie = struct {
    name: []const u8,
    value: []const u8,
    secure: bool = cookie_options.secure,
    http_only: bool = cookie_options.http_only,
    partitioned: bool = cookie_options.partitioned,
    domain: ?[]const u8 = cookie_options.domain,
    path: ?[]const u8 = cookie_options.path,
    same_site: ?SameSite = cookie_options.same_site,
    // if used, set to time in seconds to be added to std.time.timestamp()
    expires: ?i64 = cookie_options.expires,
    max_age: ?i64 = cookie_options.max_age,

    pub const blank = Cookie{
        .name = undefined,
        .value = undefined,
    };

    /// Build a cookie string.
    pub fn bufPrint(self: Cookie, buf: *[4096]u8) ![]const u8 {
        // FIX: fixedBufferStream is deprecated
        var stream = std.io.fixedBufferStream(buf);

        //var writer: Writer = .fixed(&.{})
        const writer = stream.writer();
        try writer.print("{f}", .{self});
        return stream.getWritten();
    }

    /// Build a cookie string.
    pub fn format(self: Cookie, writer: *Writer) !void {
        // secure is required if samesite is set to none
        //const require_secure = if (self.same_site) |same_site| same_site == .none else false;

        try writer.print("{s}={s}; path={s};", .{
            self.name,
            self.value,
            self.path orelse "/",
        });

        if (self.domain) |domain| try writer.print(" domain={s};", .{domain});
        if (self.same_site) |same_site| try writer.print(
            " SameSite={s};",
            .{@tagName(same_site)},
        );
        if (self.secure or self.same_site == .none) try writer.writeAll(" Secure;");
        if (self.expires) |expires| {
            const seconds = std.time.timestamp() + expires;
            const timestamp = try jetzig.jetcommon.DateTime.fromUnix(seconds, .seconds);
            // https://developer.mozilla.org/en-US/docs/Web/HTTP/Headers/Set-Cookie#expiresdate
            try timestamp.strftime(writer, " Expires=%a, %d %h %Y %H:%M:%S GMT;");
        }
        if (self.max_age) |max_age| try writer.print(" Max-Age={d};", .{max_age});
        if (self.http_only) try writer.writeAll(" HttpOnly;");
        if (self.partitioned) try writer.writeAll(" Partitioned;");
    }

    pub fn applyFlag(self: *Cookie, allocator: Allocator, flag: Flag) !void {
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

pub fn init(allocator: Allocator, cookie_string: []const u8) Cookies {
    return .{
        //.allocator = allocator,
        .cookie_string = cookie_string,
        .cookies = .init(allocator),
        .arena = .init(allocator),
    };
}

pub fn deinit(self: *Cookies, allocator: Allocator) void {
    var it = self.cookies.iterator();
    while (it.next()) |item| {
        allocator.free(item.key_ptr.*);
        allocator.free(item.value_ptr.*.value);
        allocator.destroy(item.value_ptr.*);
    }
    self.cookies.deinit();
    self.arena.deinit();
}

/// Fetch a cookie by name.
pub fn get(self: *Cookies, key: []const u8) ?*Cookie {
    return self.cookies.get(key);
}

/// Put a cookie into the cookie store.
pub fn put(self: *Cookies, allocator: Allocator, cookie: Cookie) !void {
    self.modified = true;

    if (self.cookies.fetchSwapRemove(cookie.name)) |entry| {
        allocator.free(entry.key);
        allocator.free(entry.value.value);
        allocator.destroy(entry.value);
    }
    const key = try allocator.dupe(u8, cookie.name);
    const ptr = try allocator.create(Cookie);
    ptr.* = cookie;
    ptr.name = key;
    ptr.value = try allocator.dupe(u8, cookie.value);
    try self.cookies.put(key, ptr);
}

/// Overwrite a cookie with an empty string and expiry of 0. The browser should then no longer
/// send the specified cookie value.
///
/// > Notice that servers can delete cookies by sending the user agent a new cookie with an
/// > Expires attribute with a value in the past.
/// - https://www.rfc-editor.org/rfc/rfc6265.html
pub fn delete(self: *Cookies, allocator: Allocator, key: []const u8) !void {
    self.modified = true;

    try self.put(allocator, .{
        .name = key,
        .value = "",
        .expires = 0,
    });
}

pub const HeaderIterator = struct {
    allocator: Allocator,
    cookies_iterator: StringArrayHashMap(*Cookie).Iterator,
    buf: *[4096]u8,

    pub fn init(allocator: Allocator, cookies: *Cookies, buf: *[4096]u8) HeaderIterator {
        return .{
            .allocator = allocator,
            .cookies_iterator = cookies.cookies.iterator(),
            .buf = buf,
        };
    }

    pub fn next(self: *HeaderIterator) !?[]const u8 {
        if (self.cookies_iterator.next()) |entry| {
            const cookie = entry.value_ptr.*;
            return try cookie.bufPrint(self.buf);
        } else return null;
    }
};

pub fn headerIterator(self: *Cookies, buf: *[4096]u8) HeaderIterator {
    return .init(self.allocator, self, buf);
}

// https://datatracker.ietf.org/doc/html/rfc6265#section-4.2.1
// cookie-header = "Cookie:" OWS cookie-string OWS
// cookie-string = cookie-pair *( ";" SP cookie-pair )
pub fn parse(self: *Cookies, allocator: Allocator) !void {
    defer self.modified = false;
    var key: [64]u8 = undefined;
    const iterator = std.mem.splitSequence(u8, self.cookie_string, ";");
    while (iterator.next()) |segment| {
        key = std.mem.zeroes([64]u8);
        const cookie_iterator = std.mem.splitSequence(u8, segment, "=");
        const raw_key = cookie_iterator.first();
        const raw_value = cookie_iterator.next() orelse return error.MissingValue;
        _ = std.mem.replace(u8, raw_key, " ", "", &key);
        const value = std.mem.trim(u8, raw_value, &std.ascii.whitespace);
        try self.put(allocator, .{
            .name = try allocator.dupe(u8, key),
            .value = try allocator.dupe(u8, value),
        });
    }
}

pub fn format(self: Cookies, writer: *Writer) !void {
    var it = self.cookies.iterator();
    while (it.next()) |entry| {
        try writer.print("{s}; ", .{entry.value_ptr.*});
    }
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
    var cookies: Cookies = .init(allocator, "foo=bar; baz=qux;");
    defer cookies.deinit();
    try cookies.parse();
    try std.testing.expectEqualStrings("bar", cookies.get("foo").?.value);
    try std.testing.expectEqualStrings("qux", cookies.get("baz").?.value);
}

test "empty cookie string" {
    const allocator = std.testing.allocator;
    var cookies: Cookies = .init(allocator, "");
    defer cookies.deinit();
    try cookies.parse();
}

test "cookie string with irregular spaces" {
    const allocator = std.testing.allocator;
    var cookies: Cookies = .init(allocator, "foo=   bar;     baz=        qux;");
    defer cookies.deinit();
    try cookies.parse();
    try std.testing.expectEqualStrings("bar", cookies.get("foo").?.value);
    try std.testing.expectEqualStrings("qux", cookies.get("baz").?.value);
}

test "headerIterator" {
    const allocator = std.testing.allocator;
    var aw: Writer.Allocating = .init(allocator);
    defer aw.deinit();
    var writer = &aw.writer;

    var cookies: Cookies = .init(allocator, "foo=bar; baz=qux;");
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
    , try aw.toOwnedSlice());
}

test "modified" {
    const allocator = std.testing.allocator;
    var cookies: Cookies = .init(allocator, "foo=bar; baz=qux;");
    defer cookies.deinit();

    try cookies.parse();
    try std.testing.expect(cookies.modified == false);

    try cookies.put(.{ .name = "quux", .value = "corge" });
    try std.testing.expect(cookies.modified == true);
}

test "domain=example.com" {
    const allocator = std.testing.allocator;
    var cookies: Cookies = .init(allocator, "foo=bar; baz=qux; Domain=example.com;");
    defer cookies.deinit();

    try cookies.parse();
    const cookie = cookies.get("foo").?;
    try std.testing.expectEqualStrings(cookie.domain.?, "example.com");
}

test "path=/example_path" {
    const allocator = std.testing.allocator;
    var cookies: Cookies = .init(allocator, "foo=bar; baz=qux; Path=/example_path;");
    defer cookies.deinit();

    try cookies.parse();
    const cookie = cookies.get("foo").?;
    try std.testing.expectEqualStrings(cookie.path.?, "/example_path");
}

test "SameSite=lax" {
    const allocator = std.testing.allocator;
    var cookies: Cookies = .init(allocator, "foo=bar; baz=qux; SameSite=lax;");
    defer cookies.deinit();

    try cookies.parse();
    const cookie = cookies.get("foo").?;
    try std.testing.expect(cookie.same_site == .lax);
}

test "SameSite=none" {
    const allocator = std.testing.allocator;
    var cookies: Cookies = .init(allocator, "foo=bar; baz=qux; SameSite=none;");
    defer cookies.deinit();

    try cookies.parse();
    const cookie = cookies.get("foo").?;
    try std.testing.expect(cookie.same_site == .none);
}

test "SameSite=strict" {
    const allocator = std.testing.allocator;
    var cookies: Cookies = .init(allocator, "foo=bar; baz=qux; SameSite=strict;");
    defer cookies.deinit();

    try cookies.parse();
    const cookie = cookies.get("foo").?;
    try std.testing.expect(cookie.same_site == .strict);
}

test "Secure" {
    const allocator = std.testing.allocator;
    var cookies: Cookies = .init(allocator, "foo=bar; baz=qux; Secure;");
    defer cookies.deinit();

    try cookies.parse();
    const cookie = cookies.get("foo").?;
    try std.testing.expect(cookie.secure);
}

test "Partitioned" {
    const allocator = std.testing.allocator;
    var cookies: Cookies = .init(allocator, "foo=bar; baz=qux; Partitioned;");
    defer cookies.deinit();

    try cookies.parse();
    const cookie = cookies.get("foo").?;
    try std.testing.expect(cookie.partitioned);
}

test "Max-Age" {
    const allocator = std.testing.allocator;
    var cookies: Cookies = .init(allocator, "foo=bar; baz=qux; Max-Age=123123123;");
    defer cookies.deinit();

    try cookies.parse();
    const cookie = cookies.get("foo").?;
    try std.testing.expect(cookie.max_age.? == 123123123);
}

test "Expires" {
    const allocator = std.testing.allocator;
    var cookies: Cookies = .init(allocator, "foo=bar; baz=qux; Expires=123123123;");
    defer cookies.deinit();

    try cookies.parse();
    const cookie = cookies.get("foo").?;
    try std.testing.expect(cookie.expires.? == 123123123);
}

test "default flags" {
    const allocator = std.testing.allocator;
    var cookies: Cookies = .init(allocator, "foo=bar; baz=qux;");
    defer cookies.deinit();

    try cookies.parse();
    const cookie = cookies.get("foo").?;
    try std.testing.expect(cookie.secure == false);
    try std.testing.expect(cookie.partitioned == false);
    try std.testing.expect(cookie.http_only == false);
    try std.testing.expect(cookie.same_site == null);
    try std.testing.expectEqualStrings(cookie.domain.?, "localhost");
    try std.testing.expectEqualStrings(cookie.path.?, "/");
    try std.testing.expect(cookie.expires == null);
    try std.testing.expect(cookie.max_age == null);
}

test "delete" {
    const allocator = std.testing.allocator;
    var cookies: Cookies = .init(allocator, "foo=bar;");
    defer cookies.deinit();

    try cookies.parse();

    try cookies.delete("foo");
    const cookie = cookies.get("foo").?;

    try std.testing.expectEqualStrings(cookie.value, "");
    try std.testing.expectEqual(cookie.expires.?, 0);
}
