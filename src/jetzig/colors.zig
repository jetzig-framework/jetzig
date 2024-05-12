const std = @import("std");

const builtin = @import("builtin");

const types = @import("types.zig");

// Must be consistent with `std.io.tty.Color` for Windows compatibility.
const codes = .{
    .escape = "\x1b[",
    .black = "30m",
    .red = "31m",
    .green = "32m",
    .yellow = "33m",
    .blue = "34m",
    .magenta = "35m",
    .cyan = "36m",
    .white = "37m",
    .bright_black = "90m",
    .bright_red = "91m",
    .bright_green = "92m",
    .bright_yellow = "93m",
    .bright_blue = "94m",
    .bright_magenta = "95m",
    .bright_cyan = "96m",
    .bright_white = "97m",
    .bold = "1m",
    .dim = "2m",
    .reset = "0m",
};

/// Map color codes generated by `std.io.tty.Config.setColor` back to `std.io.tty.Color`. Used by
/// `jetzig.loggers.LogQueue.writeWindows` to parse escape codes so they can be passed to
/// `std.io.tty.Config.setColor` (using Windows API to set console color mode).
pub const codes_map = std.StaticStringMap(std.io.tty.Color).initComptime(.{
    .{ "30", .black },
    .{ "31", .red },
    .{ "32", .green },
    .{ "33", .yellow },
    .{ "34", .blue },
    .{ "35", .magenta },
    .{ "36", .cyan },
    .{ "37", .white },
    .{ "90", .bright_black },
    .{ "91", .bright_red },
    .{ "92", .bright_green },
    .{ "93", .bright_yellow },
    .{ "94", .bright_blue },
    .{ "95", .bright_magenta },
    .{ "96", .bright_cyan },
    .{ "97", .bright_white },
    .{ "1", .bold },
    .{ "2", .dim },
    .{ "0", .reset },
});

/// Colorize a log message. Note that we force `.escape_codes` when we are a TTY even on Windows.
/// `jetzig.loggers.LogQueue` parses the ANSI codes and uses `std.io.tty.Config.setColor` to
/// invoke the appropriate Windows API call to set the terminal color before writing each token.
/// We must do it this way because Windows colors are set by API calls at the time of write, not
/// encoded into the message string.
pub fn colorize(color: std.io.tty.Color, buf: []u8, input: []const u8, is_colorized: bool) ![]const u8 {
    if (!is_colorized) return input;

    const config: std.io.tty.Config = .escape_codes;
    var stream = std.io.fixedBufferStream(buf);
    const writer = stream.writer();
    try config.setColor(writer, color);
    try writer.writeAll(input);
    try config.setColor(writer, .reset);

    return stream.getWritten();
}

fn wrap(comptime attribute: []const u8, comptime message: []const u8) []const u8 {
    return codes.escape ++ attribute ++ message ++ codes.escape ++ codes.reset;
}

fn runtimeWrap(allocator: std.mem.Allocator, attribute: []const u8, message: []const u8) ![]const u8 {
    return try std.mem.join(
        allocator,
        "",
        &[_][]const u8{ codes.escape, attribute, message, codes.escape, codes.reset },
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

pub fn magenta(comptime message: []const u8) []const u8 {
    return wrap(codes.magenta, message);
}

pub fn runtimeMagenta(allocator: std.mem.Allocator, message: []const u8) ![]const u8 {
    return try runtimeWrap(allocator, codes.magenta, message);
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

pub fn duration(buf: *[256]u8, delta: i64, is_colorized: bool) ![]const u8 {
    if (!is_colorized) {
        return try std.fmt.bufPrint(
            buf,
            "{}",
            .{std.fmt.fmtDurationSigned(delta)},
        );
    }

    const color: std.io.tty.Color = if (delta < 1000000)
        .green
    else if (delta < 5000000)
        .yellow
    else
        .red;
    var duration_buf: [256]u8 = undefined;
    const formatted_duration = try std.fmt.bufPrint(
        &duration_buf,
        "{}",
        .{std.fmt.fmtDurationSigned(delta)},
    );
    return try colorize(color, buf, formatted_duration, true);
}
