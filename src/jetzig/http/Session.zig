const std = @import("std");

const jetzig = @import("../../jetzig.zig");

pub const Cipher = std.crypto.aead.chacha_poly.XChaCha20Poly1305;

allocator: std.mem.Allocator,
encryption_key: []const u8,
cookies: *jetzig.http.Cookies,
cookie_name: []const u8,

initialized: bool = false,
data: jetzig.data.Data,
state: enum { parsed, pending } = .pending,

const Self = @This();

pub fn init(
    allocator: std.mem.Allocator,
    cookies: *jetzig.http.Cookies,
    encryption_key: []const u8,
) Self {
    const env_cookie_name = std.process.getEnvVarOwned(allocator, "JETZIG_SESSION_COOKIE") catch null;
    const cookie_name = env_cookie_name orelse "_jetzig-session";

    return .{
        .allocator = allocator,
        .data = jetzig.data.Data.init(allocator),
        .cookies = cookies,
        .cookie_name = cookie_name,
        .encryption_key = encryption_key,
    };
}

/// Parse session cookie.
pub fn parse(self: *Self) !void {
    if (self.cookies.get(self.cookie_name)) |cookie| {
        try self.parseSessionCookie(cookie.value);
    } else {
        try self.reset();
    }
}

/// Reset session to an empty state.
pub fn reset(self: *Self) !void {
    self.data.reset();
    _ = try self.data.object();
    self.state = .parsed;
    try self.save();
}

/// Free allocated memory.
pub fn deinit(self: *Self) void {
    self.data.deinit();
}

/// Get a value from the session.
pub fn get(self: *Self, key: []const u8) ?*jetzig.data.Value {
    std.debug.assert(self.state == .parsed);

    return switch (self.data.value.?.*) {
        .object => self.data.value.?.object.get(key),
        else => unreachable,
    };
}

/// Get a typed value from the session.
pub fn getT(
    self: *Self,
    comptime T: jetzig.data.ValueType,
    key: []const u8,
) @TypeOf(self.data.value.?.object.getT(T, key)) {
    std.debug.assert(self.state == .parsed);

    return switch (self.data.value.?.*) {
        .object => self.data.value.?.object.getT(T, key),
        else => unreachable,
    };
}

/// Put a value into the session.
pub fn put(self: *Self, key: []const u8, value: anytype) !void {
    std.debug.assert(self.state == .parsed);

    switch (self.data.value.?.*) {
        .object => |*object| {
            try object.*.put(key, value);
        },
        else => unreachable,
    }

    try self.save();
}

// Returns `true` if a value was removed and `false` otherwise.
pub fn remove(self: *Self, key: []const u8) !bool {
    std.debug.assert(self.state == .parsed);

    // copied from `get()`
    const result = switch (self.data.value.?.*) {
        .object => self.data.value.?.object.remove(key),
        else => unreachable,
    };

    try self.save();
    return result;
}

fn save(self: *Self) !void {
    if (self.state != .parsed) return error.UnparsedSessionCookie;

    const json = try self.data.toJson();

    const encrypted = try self.encrypt(json);
    defer self.allocator.free(encrypted);
    const encoded = try jetzig.util.base64Encode(self.allocator, encrypted);
    defer self.allocator.free(encoded);
    try self.cookies.put(.{ .name = self.cookie_name, .value = encoded });
}

fn parseSessionCookie(self: *Self, cookie_value: []const u8) !void {
    const decoded = try jetzig.util.base64Decode(self.allocator, cookie_value);
    defer self.allocator.free(decoded);

    const decrypted = self.decrypt(decoded) catch |err| {
        switch (err) {
            error.AuthenticationFailed => return error.JetzigInvalidSessionCookie,
            else => return err,
        }
    };
    defer self.allocator.free(decrypted);

    try self.data.fromJson(decrypted);
    self.state = .parsed;
}

fn decrypt(self: *Self, data: []u8) ![]u8 {
    if (data.len < Cipher.nonce_length + Cipher.tag_length) return error.JetzigInvalidSessionCookie;

    const secret_bytes = std.mem.sliceAsBytes(self.encryption_key);
    const key = secret_bytes[0..Cipher.key_length];
    const nonce = data[0..Cipher.nonce_length];
    const buf = try self.allocator.alloc(u8, data.len - Cipher.tag_length - Cipher.nonce_length);
    errdefer self.allocator.free(buf);
    const associated_data = "";
    var tag: [Cipher.tag_length]u8 = undefined;
    @memcpy(&tag, data[data.len - Cipher.tag_length ..]);

    try Cipher.decrypt(
        buf,
        data[Cipher.nonce_length .. data.len - Cipher.tag_length],
        tag,
        associated_data,
        nonce.*,
        key.*,
    );
    return buf;
}

fn encrypt(self: *Self, value: []const u8) ![]const u8 {
    const secret_bytes = std.mem.sliceAsBytes(self.encryption_key);
    const key: [Cipher.key_length]u8 = secret_bytes[0..Cipher.key_length].*;
    var nonce: [Cipher.nonce_length]u8 = undefined;
    for (0..Cipher.nonce_length) |index| nonce[index] = std.crypto.random.int(u8);
    const associated_data = "";

    const buf = try self.allocator.alloc(u8, value.len);
    defer self.allocator.free(buf);
    var tag: [Cipher.tag_length]u8 = undefined;

    Cipher.encrypt(buf, &tag, value, associated_data, nonce, key);
    const encrypted = try std.mem.concat(
        self.allocator,
        u8,
        &[_][]const u8{ &nonce, buf, tag[0..] },
    );
    return encrypted;
}

test "put and get session key/value" {
    const allocator = std.testing.allocator;
    var cookies = jetzig.http.Cookies.init(allocator, "");
    defer cookies.deinit();
    try cookies.parse();

    const secret: [Cipher.key_length]u8 = [_]u8{0x69} ** Cipher.key_length;
    var session = Self.init(allocator, &cookies, &secret);
    defer session.deinit();

    var data = jetzig.data.Data.init(allocator);
    defer data.deinit();

    try session.parse();
    try session.put("foo", data.string("bar"));
    var value = (session.get("foo")).?;
    try std.testing.expectEqualStrings(try value.toString(), "bar");
}

test "remove session key/value" {
    const allocator = std.testing.allocator;
    var cookies = jetzig.http.Cookies.init(allocator, "");
    defer cookies.deinit();
    try cookies.parse();

    const secret: [Cipher.key_length]u8 = [_]u8{0x69} ** Cipher.key_length;
    var session = Self.init(allocator, &cookies, &secret);
    defer session.deinit();

    var data = jetzig.data.Data.init(allocator);
    defer data.deinit();

    try session.parse();
    try session.put("foo", data.string("bar"));
    var value = (session.get("foo")).?;
    try std.testing.expectEqualStrings(try value.toString(), "bar");

    try std.testing.expectEqual(true, try session.remove("foo"));
    try std.testing.expectEqual(null, session.get("foo"));
}

test "get value from parsed/decrypted cookie" {
    const allocator = std.testing.allocator;
    var cookies = jetzig.http.Cookies.init(
        allocator,
        "_jetzig-session=fPCFwZHvPDT-XCVcsQUSspDLchS3tRuJDqPpB2v3127VXpRP_bPcPLgpHK6RiVkfcP1bMtU",
    );
    defer cookies.deinit();
    try cookies.parse();

    const secret: [Cipher.key_length]u8 = [_]u8{0x69} ** Cipher.key_length;
    var session = Self.init(allocator, &cookies, &secret);
    defer session.deinit();

    try session.parse();
    var value = (session.get("foo")).?;
    try std.testing.expectEqualStrings("bar", try value.toString());
}

test "invalid cookie value - too short" {
    const allocator = std.testing.allocator;
    var cookies = jetzig.http.Cookies.init(
        allocator,
        "_jetzig-session=abc",
    );
    defer cookies.deinit();
    try cookies.parse();

    const secret: [Cipher.key_length]u8 = [_]u8{0x69} ** Cipher.key_length;
    var session = Self.init(allocator, &cookies, &secret);
    defer session.deinit();

    try std.testing.expectError(error.JetzigInvalidSessionCookie, session.parse());
}
