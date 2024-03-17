const std = @import("std");

pub fn equalStringsCaseInsensitive(expected: []const u8, actual: []const u8) bool {
    if (expected.len != actual.len) return false;
    for (expected, actual) |expected_char, actual_char| {
        if (std.ascii.toLower(expected_char) != std.ascii.toLower(actual_char)) return false;
    }
    return true;
}
