const std = @import("std");

/// Compare two strings with case-insensitive matching.
pub fn equalStringsCaseInsensitive(expected: []const u8, actual: []const u8) bool {
    if (expected.len != actual.len) return false;
    for (expected, actual) |expected_char, actual_char| {
        if (std.ascii.toLower(expected_char) != std.ascii.toLower(actual_char)) return false;
    }
    return true;
}

/// Encode arbitrary input to Base64.
pub fn base64Encode(allocator: std.mem.Allocator, string: []const u8) ![]u8 {
    const encoder = std.base64.Base64Encoder.init(
        std.base64.url_safe_no_pad.alphabet_chars,
        std.base64.url_safe_no_pad.pad_char,
    );
    const size = encoder.calcSize(string.len);
    const ptr = try allocator.alloc(u8, size);
    _ = encoder.encode(ptr, string);
    return ptr;
}

/// Decode arbitrary input from Base64.
pub fn base64Decode(allocator: std.mem.Allocator, string: []const u8) ![]u8 {
    const decoder = std.base64.Base64Decoder.init(
        std.base64.url_safe_no_pad.alphabet_chars,
        std.base64.url_safe_no_pad.pad_char,
    );
    const size = try decoder.calcSizeForSlice(string);
    const ptr = try allocator.alloc(u8, size);
    try decoder.decode(ptr, string);
    return ptr;
}

/// Generate a secure random string of `len` characters (for cryptographic purposes).
pub fn generateSecret(allocator: std.mem.Allocator, comptime len: u10) ![]const u8 {
    const chars = "abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789";
    var secret: [len]u8 = undefined;

    for (0..len) |index| {
        secret[index] = chars[std.crypto.random.intRangeAtMost(u8, 0, chars.len)];
    }

    return try allocator.dupe(u8, &secret);
}

/// Calculate a duration from a given start time (in nanoseconds) to the current time.
pub fn duration(start_time: i128) i64 {
    return @intCast(std.time.nanoTimestamp() - start_time);
}

pub inline fn strip(string: []const u8) []const u8 {
    return std.mem.trim(u8, string, &std.ascii.whitespace);
}
