const std = @import("std");
const testing = std.testing;
const Allocator = std.mem.Allocator;
const ArenaAllocator = std.heap.ArenaAllocator;
const assert = std.debug.assert;

const jetzig = @import("../../jetzig.zig");
const Data = jetzig.data.Data;
const Cookies = jetzig.http.Cookies;

pub const Cipher = std.crypto.aead.chacha_poly.XChaCha20Poly1305;

allocator: Allocator,
encryption_key: []const u8,
cookies: *Cookies,
cookie_name: []const u8,

initialized: bool = false,
data: jetzig.data.Data,
state: enum { parsed, pending } = .pending,

const Session = @This();

pub const default_cookie_name = "_jetzig-session";

pub const Options = struct {
    cookie_name: []const u8 = default_cookie_name,
};

pub fn init(
    allocator: Allocator,
    cookies: *Cookies,
    encryption_key: []const u8,
    options: Options,
) Session {
    return .{
        .allocator = allocator,
        .data = .init(allocator),
        .cookies = cookies,
        .cookie_name = options.cookie_name,
        .encryption_key = encryption_key,
    };
}

/// Parse session cookie.
pub fn parse(self: *Session) !void {
    if (self.cookies.get(self.cookie_name)) |cookie|
        try self.parseSessionCookie(cookie.get(.value))
    else
        try self.reset();
}

/// Reset session to an empty state.
pub fn reset(self: *Session) !void {
    self.data.reset();
    _ = try self.data.object();
    self.state = .parsed;
    try self.save();
}

/// Free allocated memory.
pub fn deinit(self: *Session) void {
    self.data.deinit();
}

/// Get a value from the session.
pub fn get(self: *Session, key: []const u8) ?*jetzig.data.Value {
    std.debug.assert(self.state == .parsed);

    return switch (self.data.value.?.*) {
        .object => self.data.value.?.object.get(key),
        else => unreachable,
    };
}

/// Get a typed value from the session.
pub fn getT(
    self: *Session,
    comptime T: jetzig.data.ValueType,
    key: []const u8,
) @TypeOf(self.data.value.?.object.getT(T, key)) {
    assert(self.state == .parsed);

    return switch (self.data.value.?.*) {
        .object => self.data.value.?.object.getT(T, key),
        else => unreachable,
    };
}

/// Put a value into the session.
pub fn put(self: *Session, key: []const u8, value: anytype) !void {
    assert(self.state == .parsed);

    switch (self.data.value.?.*) {
        .object => |*object| {
            try object.*.put(key, value);
        },
        else => unreachable,
    }

    try self.save();
}

// Returns `true` if a value was removed and `false` otherwise.
pub fn remove(self: *Session, key: []const u8) !bool {
    assert(self.state == .parsed);

    // copied from `get()`
    const result = switch (self.data.value.?.*) {
        .object => self.data.value.?.object.remove(key),
        else => unreachable,
    };

    try self.save();
    return result;
}

fn save(self: *Session) !void {
    if (self.state != .parsed) return error.UnparsedSessionCookie;

    const json = try self.data.toJson();

    const encrypted = try self.encrypt(json);
    defer self.allocator.free(encrypted);
    const encoded = try jetzig.util.base64Encode(self.allocator, encrypted);
    defer self.allocator.free(encoded);
    try self.cookies.put(try .init(self.cookie_name, encoded, .{}));
}

fn parseSessionCookie(self: *Session, cookie_value: []const u8) !void {
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

fn decrypt(self: *Session, data: []u8) ![]u8 {
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

fn encrypt(self: *Session, value: []const u8) ![]const u8 {
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
    var cookies: Cookies = .init(testing.allocator, "");
    defer cookies.deinit();
    try cookies.parse();

    const secret: [Cipher.key_length]u8 = [_]u8{0x69} ** Cipher.key_length;
    var session: Session = .init(testing.allocator, &cookies, &secret, .{});
    defer session.deinit();

    var data: Data = .init(testing.allocator);
    defer data.deinit();

    try session.parse();
    try session.put("foo", data.string("bar"));
    var value = (session.get("foo")).?;
    try testing.expectEqualStrings(try value.toString(), "bar");
}

test "remove session key/value" {
    var cookies: Cookies = .init(testing.allocator, "");
    defer cookies.deinit();
    try cookies.parse();

    const secret: [Cipher.key_length]u8 = [_]u8{0x69} ** Cipher.key_length;
    var session = Session.init(testing.allocator, &cookies, &secret, .{});
    defer session.deinit();

    var data: Data = .init(testing.allocator);
    defer data.deinit();

    try session.parse();
    try session.put("foo", data.string("bar"));
    var value = (session.get("foo")).?;
    try testing.expectEqualStrings(try value.toString(), "bar");

    try testing.expectEqual(true, try session.remove("foo"));
    try testing.expectEqual(null, session.get("foo"));
}

test "get value from parsed/decrypted cookie" {
    var cookies: Cookies = .init(
        testing.allocator,
        "_jetzig-session=fPCFwZHvPDT-XCVcsQUSspDLchS3tRuJDqPpB2v3127VXpRP_bPcPLgpHK6RiVkfcP1bMtU",
    );
    defer cookies.deinit();
    try cookies.parse();

    const secret: [Cipher.key_length]u8 = [_]u8{0x69} ** Cipher.key_length;
    var session: Session = .init(testing.allocator, &cookies, &secret, .{});
    defer session.deinit();

    try session.parse();
    var value = (session.get("foo")).?;
    try testing.expectEqualStrings("bar", try value.toString());
}

test "invalid cookie value - too short" {
    var cookies: Cookies = .init(testing.allocator, "_jetzig-session=abc");
    defer cookies.deinit();
    try cookies.parse();

    const secret: [Cipher.key_length]u8 = [_]u8{0x69} ** Cipher.key_length;
    var session: Session = .init(testing.allocator, &cookies, &secret, .{});
    defer session.deinit();

    try testing.expectError(error.JetzigInvalidSessionCookie, session.parse());
}

test "custom session cookie name" {
    var cookies: Cookies = .init(
        testing.allocator,
        "custom-cookie-name=fPCFwZHvPDT-XCVcsQUSspDLchS3tRuJDqPpB2v3127VXpRP_bPcPLgpHK6RiVkfcP1bMtU",
    );
    defer cookies.deinit();
    try cookies.parse();

    const secret: [Cipher.key_length]u8 = [_]u8{0x69} ** Cipher.key_length;
    var session: Session = .init(testing.allocator, &cookies, &secret, .{
        .cookie_name = "custom-cookie-name",
    });
    defer session.deinit();

    try session.parse();
    var value = (session.get("foo")).?;
    try testing.expectEqualStrings("bar", try value.toString());
}
