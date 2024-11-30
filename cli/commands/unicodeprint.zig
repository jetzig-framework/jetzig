const std = @import("std");
const builtin = @import("builtin");

pub fn unicodePrint(comptime fmt: []const u8, args: anytype) !void {
    if (builtin.os.tag == .windows) {
        // Windows-specific code
        const cp_out = try UTF8ConsoleOutput.init();
        defer cp_out.deinit();

        std.debug.print(comptime fmt, args);
    } else {
        // Non-Windows platforms just print normally
        std.debug.print(fmt, args);
    }
}
const UTF8ConsoleOutput = struct {
    original: if (builtin.os.tag == .windows) c_uint else void,

    fn init() !UTF8ConsoleOutput {
        if (builtin.os.tag == .windows) {
            const original = std.os.windows.kernel32.GetConsoleOutputCP();
            if (original == 0) {
                return error.FailedToGetConsoleOutputCP;
            }
            const result = std.os.windows.kernel32.SetConsoleOutputCP(65001); // UTF-8 code page
            if (result == 0) {
                return error.FailedToSetConsoleOutputCP;
            }
            return .{ .original = original };
        }
        // For non-Windows, return an empty struct
        return .{ .original = {} };
    }

    fn deinit(self: UTF8ConsoleOutput) void {
        if (builtin.os.tag == .windows) {
            // Restore the original code page
            _ = std.os.windows.kernel32.SetConsoleOutputCP(self.original);
        }
    }
};
