const std = @import("std");
const testing = std.testing;
const ArrayList = std.ArrayList;
const Allocator = std.mem.Allocator;
const ArenaAllocator = std.heap.ArenaAllocator;
const Writer = std.Io.Writer;

const jetzig = @import("../../jetzig.zig");

allocator: Allocator,
cookie_string: []const u8,
cookies: std.StringArrayHashMap(*Cookie),
modified: bool = false,
arena: ArenaAllocator,

const Cookies = @This();
pub const Cookie = @import("Cookie.zig");

// pub const CookieOptions = struct {
//     domain: ?[]const u8 = "localhost",
//     path: []const u8 = "/",
//     secure: bool = false,
//     http_only: bool = false,
//     partitioned: bool = false,
//     same_site: ?SameSite = null,
//     expires: ?i64 = null, // if used, set to time in seconds to be added to std.time.timestamp()
//     max_age: ?i64 = null,
// };

// const cookie_options = jetzig.config.get(Cookie.Options, "cookies");

// pub const Cookie = struct {
//     name: []const u8,
//     value: []const u8,
//     secure: bool = cookie_options.secure,
//     http_only: bool = cookie_options.http_only,
//     partitioned: bool = cookie_options.partitioned,
//     domain: ?[]const u8 = cookie_options.domain,
//     path: ?[]const u8 = cookie_options.path,
//     same_site: ?SameSite = cookie_options.same_site,
//     // if used, set to time in seconds to be added to std.time.timestamp()
//     expires: ?i64 = cookie_options.expires,
//     max_age: ?i64 = cookie_options.max_age,
//
//     /// Build a cookie string.
//     pub fn bufPrint(self: Cookie, buf: *[4096]u8) ![]const u8 {
//         var stream = std.io.fixedBufferStream(buf);
//         const writer = stream.writer();
//         try writer.print("{any}", .{self});
//         return stream.getWritten();
//     }
//
//     /// Build a cookie string.
//     pub fn format(self: Cookie, _: anytype, _: anytype, writer: anytype) !void {
//         // secure is required if samesite is set to none
//         const require_secure = if (self.same_site) |same_site| same_site == .none else false;
//
//         try writer.print("{s}={s}; path={s};", .{
//             self.name,
//             self.value,
//             self.path orelse "/",
//         });
//
//         if (self.domain) |domain| try writer.print(" domain={s};", .{domain});
//         if (self.same_site) |same_site| try writer.print(
//             " SameSite={s};",
//             .{@tagName(same_site)},
//         );
//         if (self.secure or require_secure) try writer.writeAll(" Secure;");
//         if (self.expires) |expires| {
//             const seconds = std.time.timestamp() + expires;
//             const timestamp = try jetzig.jetcommon.DateTime.fromUnix(seconds, .seconds);
//             // https://developer.mozilla.org/en-US/docs/Web/HTTP/Headers/Set-Cookie#expiresdate
//             try timestamp.strftime(writer, " Expires=%a, %d %h %Y %H:%M:%S GMT;");
//         }
//         if (self.max_age) |max_age| try writer.print(" Max-Age={d};", .{max_age});
//         if (self.http_only) try writer.writeAll(" HttpOnly;");
//         if (self.partitioned) try writer.writeAll(" Partitioned;");
//     }
//
//     pub fn applyFlag(self: *Cookie, allocator: std.mem.Allocator, flag: Flag) !void {
//         switch (flag) {
//             .domain => |domain| self.domain = try allocator.dupe(u8, domain),
//             .path => |path| self.path = try allocator.dupe(u8, path),
//             .same_site => |same_site| self.same_site = same_site,
//             .secure => |secure| self.secure = secure,
//             .expires => |expires| self.expires = expires,
//             .http_only => |http_only| self.http_only = http_only,
//             .max_age => |max_age| self.max_age = max_age,
//             .partitioned => |partitioned| self.partitioned = partitioned,
//         }
//     }
// };
//
pub fn init(allocator: Allocator, cookie_string: []const u8) Cookies {
    return .{
        .allocator = allocator,
        .cookie_string = cookie_string,
        .cookies = .init(allocator),
        .arena = .init(allocator),
    };
}

pub fn deinit(self: *Cookies) void {
    var it = self.cookies.iterator();
    while (it.next()) |item| {
        self.allocator.free(item.key_ptr.*);
        self.allocator.destroy(item.value_ptr.*);
    }
    self.cookies.deinit();
    self.arena.deinit();
}

/// Fetch a cookie by name.
pub fn get(self: *Cookies, key: []const u8) ?*Cookie {
    return self.cookies.get(key);
}

/// Put a cookie into the cookie store.
pub fn put(self: *Cookies, cookie: Cookie) !void {
    self.modified = true;

    if (self.cookies.fetchSwapRemove(cookie.get(.name))) |entry| {
        self.allocator.free(entry.key);
        self.allocator.destroy(entry.value);
    }
    const key = try self.allocator.dupe(u8, cookie.get(.name));
    const ptr = try self.allocator.create(Cookie);
    ptr.* = cookie;
    try ptr.set(.{ .name = key });
    try ptr.set(.{ .value = cookie.get(.value) });
    // ptr.value = try self.allocator.dupe(u8, cookie.value);
    try self.cookies.put(key, ptr);
}

/// Overwrite a cookie with an empty string and expiry of 0. The browser should then no longer
/// send the specified cookie value.
///
/// > Notice that servers can delete cookies by sending the user agent a new cookie with an
/// > Expires attribute with a value in the past.
/// - https://www.rfc-editor.org/rfc/rfc6265.html
pub fn delete(self: *Cookies, key: []const u8) !void {
    self.modified = true;
    try self.put(try .init(key, "", .{ .expires = 0 }));
}

pub const HeaderIterator = struct {
    allocator: Allocator,
    cookies_iterator: std.StringArrayHashMap(*Cookie).Iterator,
    buf: *[Cookie.MaxLength]u8,

    pub fn init(allocator: Allocator, cookies: *Cookies, buf: *[Cookie.MaxLength]u8) HeaderIterator {
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
        }
        return null;
    }
};

pub fn headerIterator(self: *Cookies, buf: *[4096]u8) HeaderIterator {
    return .init(self.allocator, self, buf);
}

// https://datatracker.ietf.org/doc/html/rfc6265#section-4.2.1
// cookie-header = "Cookie:" OWS cookie-string OWS
// cookie-string = cookie-pair *( ";" SP cookie-pair )
pub fn parse(self: *Cookies) !void {
    var key_buf = std.array_list.Managed(u8).init(self.allocator);
    var value_buf = std.array_list.Managed(u8).init(self.allocator);
    var key_terminated = false;
    var value_started = false;
    var cookie_buf = std.array_list.Managed(Cookie).init(self.allocator);

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
                // for (cookie_buf.items) |*cookie| try cookie.applyFlag(self.arena.allocator(), flag);
                for (cookie_buf.items) |*cookie| try cookie.set(flag);
            } else {
                try cookie_buf.append(try .init(key_buf.items, value_buf.items, .{}));
                // try cookie_buf.append(.{
                //     .name = try self.arena.allocator().dupe(u8, key_buf.items),
                //     .value = try self.arena.allocator().dupe(u8, value_buf.items),
                // });
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

pub fn format(self: Cookies, writer: *Writer) !void {
    var it = self.cookies.iterator();
    while (it.next()) |entry| {
        try writer.print("{}; ", .{entry.value_ptr.*});
    }
}

fn parseFlag(key: []const u8, value: []const u8) ?Cookie.Flag {
    if (key.len > 64) return null;
    if (value.len > 64) return null;

    var key_buf: [64]u8 = undefined;

    const normalized_key = std.ascii.lowerString(&key_buf, jetzig.util.strip(key));
    const normalized_value = jetzig.util.strip(value);

    if (std.mem.eql(u8, normalized_key, "domain"))
        return .{ .domain = normalized_value };
    if (std.mem.eql(u8, normalized_key, "path"))
        return .{ .path = normalized_value };
    if (std.mem.eql(u8, normalized_key, "samesite")) {
        return if (std.mem.eql(u8, normalized_value, "strict"))
            .{ .samesite = .strict }
        else if (std.mem.eql(u8, normalized_value, "lax"))
            .{ .samesite = .lax }
        else
            .{ .samesite = .none };
    }
    if (std.mem.eql(u8, normalized_key, "secure"))
        return .{ .secure = true };
    if (std.mem.eql(u8, normalized_key, "httponly"))
        return .{ .httponly = true };
    if (std.mem.eql(u8, normalized_key, "partitioned"))
        return .{ .partitioned = true };
    if (std.mem.eql(u8, normalized_key, "expires"))
        return .{ .expires = std.fmt.parseInt(i64, normalized_value, 10) catch return null };
    if (std.mem.eql(u8, normalized_key, "max-age"))
        return .{ .@"max-age" = std.fmt.parseInt(i64, normalized_value, 10) catch return null };
    return null;
}

test "basic cookie string" {
    var cookies: Cookies = .init(testing.allocator, "foo=bar; baz=qux;");
    defer cookies.deinit();
    try cookies.parse();
    try testing.expectEqualStrings("bar", cookies.get("foo").?.get(.value));
    try testing.expectEqualStrings("qux", cookies.get("baz").?.get(.value));
}

test "empty cookie string" {
    var cookies: Cookies = .init(testing.allocator, "");
    defer cookies.deinit();
    try cookies.parse();
}

test "cookie string with irregular spaces" {
    var cookies: Cookies = .init(testing.allocator, "foo=   bar;     baz=        qux;");
    defer cookies.deinit();
    try cookies.parse();
    try testing.expectEqualStrings("bar", cookies.get("foo").?.get(.value));
    try testing.expectEqualStrings("qux", cookies.get("baz").?.get(.value));
}

test "headerIterator" {
    var buf: Writer.Allocating = .init(testing.allocator);
    defer buf.deinit();

    var cookies = Cookies.init(testing.allocator, "foo=bar; baz=qux;");
    defer cookies.deinit();
    try cookies.parse();

    var it_buf: [4096]u8 = undefined;
    var it = cookies.headerIterator(&it_buf);
    while (try it.next()) |*header| {
        try buf.writer.writeAll(header.*);
        try buf.writer.writeAll("\n");
    }
    const output = try buf.toOwnedSlice();
    defer testing.allocator.free(output);

    try testing.expectEqualStrings(
        \\foo=bar;path=/;domain=localhost;
        \\baz=qux;path=/;domain=localhost;
        \\
    , output);
}

test "modified" {
    var cookies: Cookies = .init(testing.allocator, "foo=bar; baz=qux;");
    defer cookies.deinit();

    try cookies.parse();
    try testing.expect(cookies.modified == false);

    try cookies.put(try .init("quux", "corge", .{}));
    try testing.expect(cookies.modified == true);
}

test "domain=example.com" {
    var cookies: Cookies = .init(testing.allocator, "foo=bar; baz=qux; Domain=example.com;");
    defer cookies.deinit();

    try cookies.parse();
    const cookie = cookies.get("foo") orelse return testing.expect(false);
    try testing.expectEqualStrings(cookie.get(.domain), "example.com");
}

test "path=/example_path" {
    var cookies: Cookies = .init(testing.allocator, "foo=bar; baz=qux; Path=/example_path;");
    defer cookies.deinit();

    try cookies.parse();
    const cookie = cookies.get("foo") orelse return testing.expect(false);
    try testing.expectEqualStrings(cookie.get(.path), "/example_path");
}

test "SameSite=lax" {
    var cookies: Cookies = .init(testing.allocator, "foo=bar; baz=qux; SameSite=lax;");
    defer cookies.deinit();

    try cookies.parse();
    const cookie = cookies.get("foo") orelse return testing.expect(false);
    try testing.expect(cookie.samesite == .lax);
}

test "SameSite=none" {
    var cookies: Cookies = .init(testing.allocator, "foo=bar; baz=qux; SameSite=none;");
    defer cookies.deinit();

    try cookies.parse();
    const cookie = cookies.get("foo") orelse return testing.expect(false);
    try std.testing.expect(cookie.samesite == .none);
}

test "SameSite=strict" {
    var cookies: Cookies = .init(testing.allocator, "foo=bar; baz=qux; SameSite=strict;");
    defer cookies.deinit();

    try cookies.parse();
    const cookie = cookies.get("foo") orelse return testing.expect(false);
    try testing.expect(cookie.samesite == .strict);
}

test "Secure" {
    var cookies: Cookies = .init(testing.allocator, "foo=bar; baz=qux; Secure;");
    defer cookies.deinit();

    try cookies.parse();
    const cookie = cookies.get("foo") orelse return testing.expect(false);
    try testing.expect(cookie.secure);
}

test "Partitioned" {
    var cookies: Cookies = .init(testing.allocator, "foo=bar; baz=qux; Partitioned;");
    defer cookies.deinit();

    try cookies.parse();
    const cookie = cookies.get("foo") orelse return testing.expect(false);
    try testing.expect(cookie.partitioned);
}

test "Max-Age" {
    var cookies: Cookies = .init(testing.allocator, "foo=bar; baz=qux; Max-Age=123123123;");
    defer cookies.deinit();

    try cookies.parse();
    const cookie = cookies.get("foo") orelse return testing.expect(false);
    try testing.expect(cookie.@"max-age".? == 123123123);
}

test "Expires" {
    var cookies: Cookies = .init(testing.allocator, "foo=bar; baz=qux; Expires=123123123;");
    defer cookies.deinit();

    try cookies.parse();
    const cookie = cookies.get("foo") orelse return testing.expect(false);
    try testing.expect(cookie.expires.? == 123123123);
}

test "default flags" {
    var cookies: Cookies = .init(testing.allocator, "foo=bar; baz=qux;");
    defer cookies.deinit();

    try cookies.parse();
    const cookie = cookies.get("foo").?;
    try testing.expect(cookie.secure == false);
    try testing.expect(cookie.partitioned == false);
    try testing.expect(cookie.httponly == false);
    try testing.expect(cookie.samesite == null);
    try testing.expectEqualStrings("localhost", cookie.get(.domain));
    try testing.expectEqualStrings("/", cookie.get(.path));
    try testing.expect(cookie.expires == null);
    try testing.expect(cookie.@"max-age" == null);
}

test "delete" {
    var cookies: Cookies = .init(testing.allocator, "foo=bar;");
    defer cookies.deinit();

    try cookies.parse();

    try cookies.delete("foo");
    const cookie = cookies.get("foo") orelse return testing.expect(false);

    try testing.expectEqualStrings(cookie.get(.value), "");
    try testing.expectEqual(cookie.expires.?, 0);
}
