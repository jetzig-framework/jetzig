const std = @import("std");

const jetzig = @import("../../jetzig.zig");

pub const cookie_name = "_jetzig-session";
pub const Cipher = std.crypto.aead.aes_gcm.Aes256Gcm;

allocator: std.mem.Allocator,
encryption_key: ?[]const u8,
cookies: *jetzig.http.Cookies,

hashmap: std.StringHashMap(jetzig.data.Value),

cookie: ?jetzig.http.Cookies.Cookie = null,
initialized: bool = false,
data: jetzig.data.Data = undefined,
state: enum { parsed, pending } = .pending,
encrypted: ?[]const u8 = null,
decrypted: ?[]const u8 = null,
encoded: ?[]const u8 = null,

const Self = @This();

pub fn init(
    allocator: std.mem.Allocator,
    cookies: *jetzig.http.Cookies,
    encryption_key: ?[]const u8,
) Self {
    return .{
        .allocator = allocator,
        .hashmap = std.StringHashMap(jetzig.data.Value).init(allocator),
        .cookies = cookies,
        .encryption_key = encryption_key,
    };
}

pub fn parse(self: *Self) !void {
    if (self.cookies.get(cookie_name)) |cookie| {
        try self.parseSessionCookie(cookie.value);
    } else {
        try self.reset();
    }
}

pub fn reset(self: *Self) !void {
    self.data = jetzig.data.Data.init(self.allocator);
    _ = try self.data.object();
    self.state = .parsed;
    try self.save();
}

pub fn deinit(self: *Self) void {
    if (self.state != .parsed) return;

    var it = self.hashmap.iterator();
    while (it.next()) |item| {
        self.allocator.destroy(item.key_ptr);
        self.allocator.destroy(item.value_ptr);
    }
    self.hashmap.deinit();

    if (self.encoded) |*ptr| self.allocator.free(ptr.*);
    if (self.decrypted) |*ptr| self.allocator.free(ptr.*);
    if (self.encrypted) |*ptr| self.allocator.free(ptr.*);
    if (self.cookie) |*ptr| self.allocator.free(ptr.*.value);
}

pub fn get(self: *Self, key: []const u8) !?*jetzig.data.Value {
    if (self.state != .parsed) return error.UnparsedSessionCookie;

    return switch (self.data.value.?.*) {
        .object => self.data.value.?.object.get(key),
        else => unreachable,
    };
}

pub fn put(self: *Self, key: []const u8, value: *jetzig.data.Value) !void {
    if (self.state != .parsed) return error.UnparsedSessionCookie;

    switch (self.data.value.?.*) {
        .object => |*object| {
            try object.*.put(key, value);
        },
        else => unreachable,
    }

    try self.save();
}

fn save(self: *Self) !void {
    if (self.state != .parsed) return error.UnparsedSessionCookie;

    const json = try self.data.toJson();
    defer self.allocator.free(json);

    if (self.encrypted) |*ptr| {
        self.allocator.free(ptr.*);
        self.encrypted = null;
    }
    self.encrypted = try self.encrypt(json);

    const encoded = try jetzig.util.base64Encode(self.allocator, self.encrypted.?);
    defer self.allocator.free(encoded);

    if (self.cookie) |*ptr| self.allocator.free(ptr.*.value);
    self.cookie = .{ .value = try self.allocator.dupe(u8, encoded) };

    try self.cookies.put(
        cookie_name,
        self.cookie.?,
    );
}

fn parseSessionCookie(self: *Self, cookie_value: []const u8) !void {
    self.data = jetzig.data.Data.init(self.allocator);
    const decoded = try jetzig.util.base64Decode(self.allocator, cookie_value);
    defer self.allocator.free(decoded);

    const buf = self.decrypt(decoded) catch |err| {
        switch (err) {
            error.AuthenticationFailed => return error.JetzigInvalidSessionCookie,
            else => return err,
        }
    };
    defer self.allocator.free(buf);
    if (self.decrypted) |*ptr| self.allocator.free(ptr.*);
    self.decrypted = try self.allocator.dupe(u8, buf);

    try self.data.fromJson(self.decrypted.?);
    self.state = .parsed;
}

fn decrypt(self: *Self, data: []const u8) ![]const u8 {
    if (self.encryption_key) |secret| {
        const encrypted = data[0 .. data.len - Cipher.tag_length];
        const secret_bytes = std.mem.sliceAsBytes(secret);
        const key: [Cipher.key_length]u8 = secret_bytes[0..Cipher.key_length].*;
        const nonce: [Cipher.nonce_length]u8 = secret_bytes[Cipher.key_length .. Cipher.key_length + Cipher.nonce_length].*;
        const buf = try self.allocator.alloc(u8, data.len - Cipher.tag_length);
        const additional_data = "";
        var tag: [Cipher.tag_length]u8 = undefined;
        std.mem.copyForwards(u8, &tag, data[data.len - Cipher.tag_length ..]);

        try Cipher.decrypt(
            buf,
            encrypted,
            tag,
            additional_data,
            nonce,
            key,
        );
        return buf[0..];
    } else {
        return self.allocator.dupe(u8, "hello");
    }
}

fn encrypt(self: *Self, value: []const u8) ![]const u8 {
    if (self.encryption_key) |secret| {
        const secret_bytes = std.mem.sliceAsBytes(secret);
        const key: [Cipher.key_length]u8 = secret_bytes[0..Cipher.key_length].*;
        const nonce: [Cipher.nonce_length]u8 = secret_bytes[Cipher.key_length .. Cipher.key_length + Cipher.nonce_length].*;
        const associated_data = "";

        if (self.encrypted) |*val| {
            self.allocator.free(val.*);
            self.encrypted = null;
        }

        const buf = try self.allocator.alloc(u8, value.len);
        defer self.allocator.free(buf);
        var tag: [Cipher.tag_length]u8 = undefined;

        Cipher.encrypt(buf, &tag, value, associated_data, nonce, key);
        if (self.encrypted) |*ptr| self.allocator.free(ptr.*);
        self.encrypted = try std.mem.concat(
            self.allocator,
            u8,
            &[_][]const u8{ buf, tag[0..] },
        );
        return self.encrypted.?;
    } else {
        return value;
    }
}

test "put and get session key/value" {
    const allocator = std.testing.allocator;
    var cookies = jetzig.http.Cookies.init(allocator, "");
    defer cookies.deinit();
    try cookies.parse();

    const secret: [Cipher.key_length + Cipher.nonce_length]u8 = [_]u8{0x69} ** (Cipher.key_length + Cipher.nonce_length);
    var session = Self.init(allocator, &cookies, &secret);
    defer session.deinit();
    defer session.data.deinit();

    var data = jetzig.data.Data.init(allocator);
    defer data.deinit();

    try session.parse();
    try session.put("foo", data.string("bar"));
    var value = (try session.get("foo")).?;
    try std.testing.expectEqualStrings(try value.toString(), "bar");
}

test "get value from parsed/decrypted cookie" {
    const allocator = std.testing.allocator;
    var cookies = jetzig.http.Cookies.init(allocator, "_jetzig-session=GIRI22v4C9EwU_mY02_obbnX2QkdnEZenlQz2xs");
    defer cookies.deinit();
    try cookies.parse();

    const secret: [Cipher.key_length + Cipher.nonce_length]u8 = [_]u8{0x69} ** (Cipher.key_length + Cipher.nonce_length);
    var session = Self.init(allocator, &cookies, &secret);
    defer session.deinit();
    defer session.data.deinit();

    try session.parse();
    var value = (try session.get("foo")).?;
    try std.testing.expectEqualStrings("bar", try value.toString());
}
