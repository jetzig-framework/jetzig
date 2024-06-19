const std = @import("std");
const builtin = @import("builtin");

const colors = @import("colors.zig");

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

pub fn gzip(allocator: std.mem.Allocator, content: []const u8, options: struct {}) ![]const u8 {
    _ = options; // Allow setting compression options later if needed.
    var compressed = std.ArrayList(u8).init(allocator);
    var content_reader = std.io.fixedBufferStream(content);
    try std.compress.gzip.compress(content_reader.reader(), compressed.writer(), .{ .level = .fast });
    return try compressed.toOwnedSlice();
}

pub fn deflate(allocator: std.mem.Allocator, content: []const u8, options: struct {}) ![]const u8 {
    _ = options; // Allow setting compression options later if needed.
    var compressed = std.ArrayList(u8).init(allocator);
    var content_reader = std.io.fixedBufferStream(content);
    try std.compress.flate.compress(content_reader.reader(), compressed.writer(), .{ .level = .fast });
    return try compressed.toOwnedSlice();
}

// Strip leading and trailing whitespace from a u8 slice.
pub inline fn strip(input: []const u8) []const u8 {
    return std.mem.trim(u8, input, &std.ascii.whitespace);
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

pub fn generateRandomString(buf: []u8) []const u8 {
    const chars = "abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789";

    for (0..buf.len) |index| {
        buf[index] = chars[std.crypto.random.intRangeAtMost(u8, 0, chars.len)];
    }

    return buf;
}

/// Calculate a duration from a given start time (in nanoseconds) to the current time.
pub fn duration(start_time: i128) i64 {
    return @intCast(std.time.nanoTimestamp() - start_time);
}

/// Generate a random variable name with enough entropy to be considered unique.
pub fn generateVariableName(buf: *[32]u8) []const u8 {
    const first_chars = "abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ";
    const any_chars = "0123456789" ++ first_chars;

    for (0..3) |index| {
        buf[index] = first_chars[std.crypto.random.intRangeAtMost(u8, 0, first_chars.len - 1)];
    }

    for (3..32) |index| {
        buf[index] = any_chars[std.crypto.random.intRangeAtMost(u8, 0, any_chars.len - 1)];
    }
    return buf[0..32];
}

/// Write a string of bytes, possibly containing ANSI escape codes. Translate ANSI escape codes
/// into Windows API console commands. Allow building an ANSI string and writing at once to a
/// Windows console. In non-Windows environments, output ANSI bytes directly.
pub fn writeAnsi(file: std.fs.File, writer: anytype, text: []const u8) !void {
    if (builtin.os.tag != .windows) {
        try writer.writeAll(text);
    } else {
        var info: std.os.windows.CONSOLE_SCREEN_BUFFER_INFO = undefined;
        _ = std.os.windows.kernel32.GetConsoleScreenBufferInfo(file.handle, &info);

        var it = std.mem.tokenizeSequence(u8, text, "\x1b[");
        while (it.next()) |token| {
            if (std.mem.indexOfScalar(u8, token, 'm')) |index| {
                if (index > 0 and index + 1 < token.len) {
                    if (colors.windows_map.get(token[0..index])) |color| {
                        try std.os.windows.SetConsoleTextAttribute(file.handle, color);
                        try writer.writeAll(token[index + 1 ..]);
                        continue;
                    }
                }
            }
            // Fallback
            try writer.writeAll(token);
        }
    }
}
