const std = @import("std");

const types = @import("types.zig");

const codes = .{
    .escape = "\x1B[",
    .reset = "0;0",
    .black = "0;30",
    .red = "0;31",
    .green = "0;32",
    .yellow = "0;33",
    .blue = "0;34",
    .purple = "0;35",
    .cyan = "0;36",
    .white = "0;37",
};

fn wrap(comptime attribute: []const u8, comptime message: []const u8) []const u8 {
    return codes.escape ++ attribute ++ "m" ++ message ++ codes.escape ++ codes.reset ++ "m";
}

fn runtimeWrap(allocator: std.mem.Allocator, attribute: []const u8, message: []const u8) ![]const u8 {
    return try std.mem.join(
        allocator,
        "",
        &[_][]const u8{ codes.escape, attribute, "m", message, codes.escape, codes.reset, "m" },
    );
}

pub fn black(comptime message: []const u8) []const u8 {
    return wrap(codes.black, message);
}

pub fn runtimeBlack(allocator: std.mem.Allocator, message: []const u8) ![]const u8 {
    return try runtimeWrap(allocator, codes.black, message);
}

pub fn red(comptime message: []const u8) []const u8 {
    return wrap(codes.red, message);
}

pub fn runtimeRed(allocator: std.mem.Allocator, message: []const u8) ![]const u8 {
    return try runtimeWrap(allocator, codes.red, message);
}

pub fn green(comptime message: []const u8) []const u8 {
    return wrap(codes.green, message);
}

pub fn runtimeGreen(allocator: std.mem.Allocator, message: []const u8) ![]const u8 {
    return try runtimeWrap(allocator, codes.green, message);
}

pub fn yellow(comptime message: []const u8) []const u8 {
    return wrap(codes.yellow, message);
}

pub fn runtimeYellow(allocator: std.mem.Allocator, message: []const u8) ![]const u8 {
    return try runtimeWrap(allocator, codes.yellow, message);
}

pub fn blue(comptime message: []const u8) []const u8 {
    return wrap(codes.blue, message);
}

pub fn runtimeBlue(allocator: std.mem.Allocator, message: []const u8) ![]const u8 {
    return try runtimeWrap(allocator, codes.blue, message);
}

pub fn purple(comptime message: []const u8) []const u8 {
    return wrap(codes.purple, message);
}

pub fn runtimePurple(allocator: std.mem.Allocator, message: []const u8) ![]const u8 {
    return try runtimeWrap(allocator, codes.purple, message);
}

pub fn cyan(comptime message: []const u8) []const u8 {
    return wrap(codes.cyan, message);
}

pub fn runtimeCyan(allocator: std.mem.Allocator, message: []const u8) ![]const u8 {
    return try runtimeWrap(allocator, codes.cyan, message);
}

pub fn white(comptime message: []const u8) []const u8 {
    return wrap(codes.white, message);
}

pub fn runtimeWhite(allocator: std.mem.Allocator, message: []const u8) ![]const u8 {
    return try runtimeWrap(allocator, codes.white, message);
}

pub fn duration(allocator: std.mem.Allocator, delta: i64) ![]const u8 {
    var buf: [1024]u8 = undefined;
    const formatted_duration = try std.fmt.bufPrint(&buf, "{}", .{std.fmt.fmtDurationSigned(delta)});

    if (delta < 100000) {
        return try runtimeGreen(allocator, formatted_duration);
    } else if (delta < 500000) {
        return try runtimeYellow(allocator, formatted_duration);
    } else {
        return try runtimeRed(allocator, formatted_duration);
    }
}
