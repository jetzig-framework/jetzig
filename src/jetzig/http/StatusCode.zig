const std = @import("std");

const jetzig = @import("../jetzig.zig");

pub const StatusCode = enum {
    ok,
    not_found,
};

pub fn StatusCodeType(comptime code: []const u8, comptime message: []const u8) type {
    return struct {
        code: []const u8 = code,
        message: []const u8 = message,

        const Self = @This();

        pub fn format(self: Self) []const u8 {
            _ = self;

            const full_message = code ++ " " ++ message;

            if (std.mem.startsWith(u8, code, "2")) {
                return jetzig.colors.green(full_message);
            } else if (std.mem.startsWith(u8, code, "3")) {
                return jetzig.colors.blue(full_message);
            } else if (std.mem.startsWith(u8, code, "4")) {
                return jetzig.colors.yellow(full_message);
            } else if (std.mem.startsWith(u8, code, "5")) {
                return jetzig.colors.red(full_message);
            } else {
                return full_message;
            }
        }
    };
}

pub const StatusCodeUnion = union(StatusCode) {
    ok: StatusCode("200", "OK"),
    not_found: StatusCode("404", "Not Found"),

    const Self = @This();

    pub fn format(self: Self) []const u8 {
        return switch (self) {
            inline else => |case| case.format(),
        };
    }
};
