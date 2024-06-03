const std = @import("std");
const builtin = @import("builtin");
const jetzig = @import("jetzig");

const Test = struct {
    name: []const u8,
    function: TestFn,
    module: ?[]const u8 = null,
    leaked: bool = false,
    result: Result = .success,
    stack_trace_buf: [4096]u8 = undefined,
    duration: usize = 0,

    pub const TestFn = *const fn () anyerror!void;
    pub const Result = union(enum) {
        success: void,
        failure: Failure,
        skipped: void,
    };

    const Failure = struct {
        err: anyerror,
        trace: ?[]const u8,
    };

    const name_template = jetzig.colors.blue("{s}") ++ ":" ++ jetzig.colors.cyan("{s}") ++ " ";

    pub fn init(test_fn: std.builtin.TestFn) Test {
        return if (std.mem.indexOf(u8, test_fn.name, ".test.")) |index|
            .{
                .function = test_fn.func,
                .module = test_fn.name[0..index],
                .name = test_fn.name[index + ".test.".len ..],
            }
        else
            .{ .function = test_fn.func, .name = test_fn.name };
    }

    pub fn run(self: *Test) !void {
        std.testing.allocator_instance = .{};
        const start = std.time.nanoTimestamp();

        self.function() catch |err| {
            switch (err) {
                error.SkipZigTest => self.result = .skipped,
                else => self.result = .{ .failure = .{
                    .err = err,
                    .trace = try self.formatStackTrace(@errorReturnTrace()),
                } },
            }
        };

        self.duration = @intCast(std.time.nanoTimestamp() - start);

        if (std.testing.allocator_instance.deinit() == .leak) self.leaked = true;
    }

    fn formatStackTrace(self: *Test, maybe_trace: ?*std.builtin.StackTrace) !?[]const u8 {
        return if (maybe_trace) |trace| blk: {
            var stream = std.io.fixedBufferStream(&self.stack_trace_buf);
            const writer = stream.writer();
            try trace.format("", .{}, writer);
            break :blk stream.getWritten();
        } else null;
    }

    pub fn print(self: Test, stream: anytype) !void {
        const writer = stream.writer();

        switch (self.result) {
            .success => try self.printPassed(writer),
            .failure => |failure| try self.printFailure(failure, writer),
            .skipped => try self.printSkipped(writer),
        }
        try self.printDuration(writer);

        if (self.leaked) try self.printLeaked(writer);

        try writer.writeByte('\n');
    }

    fn printPassed(self: Test, writer: anytype) !void {
        try writer.print(
            jetzig.colors.green("[PASS] ") ++ name_template,
            .{ self.module orelse "tests", self.name },
        );
    }

    fn printFailure(self: Test, failure: Failure, writer: anytype) !void {
        try writer.print(
            jetzig.colors.red("[FAIL] ") ++ name_template ++ jetzig.colors.yellow("({s})"),
            .{ self.module orelse "tests", self.name, @errorName(failure.err) },
        );

        if (failure.trace) |trace| {
            try writer.print("{s}", .{trace});
        }
    }

    fn printSkipped(self: Test, writer: anytype) !void {
        try writer.print(
            jetzig.colors.yellow("[SKIP]") ++ name_template,
            .{ self.module orelse "tests", self.name },
        );
    }

    fn printLeaked(self: Test, writer: anytype) !void {
        _ = self;
        try writer.print(jetzig.colors.red(" [LEAKED]"), .{});
    }

    fn printDuration(self: Test, writer: anytype) !void {
        var buf: [256]u8 = undefined;
        try writer.print(
            "[" ++ jetzig.colors.cyan("{s}") ++ "]",
            .{try jetzig.colors.duration(&buf, @intCast(self.duration), true)},
        );
    }
};

pub fn main() !void {
    const start = std.time.nanoTimestamp();

    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    const allocator = gpa.allocator();
    var tests = std.ArrayList(Test).init(allocator);
    defer tests.deinit();

    var mime_map = jetzig.http.mime.MimeMap.init(allocator);
    try mime_map.build();
    jetzig.testing.mime_map = &mime_map;

    try std.io.getStdErr().writer().writeAll("\n[jetzig] Launching Test Runner...\n\n");

    jetzig.testing.state = .ready;

    for (builtin.test_functions) |test_function| {
        var t = Test.init(test_function);
        try t.run();
        try t.print(std.io.getStdErr());
        try tests.append(t);
    }

    try printSummary(tests.items, start);
}

fn printSummary(tests: []const Test, start: i128) !void {
    var success: usize = 0;
    var failure: usize = 0;
    var leaked: usize = 0;
    var skipped: usize = 0;

    for (tests) |t| {
        switch (t.result) {
            .success => success += 1,
            .failure => failure += 1,
            .skipped => skipped += 1,
        }
        if (t.leaked) leaked += 1;
    }
    const tick = jetzig.colors.green("✔");
    const cross = jetzig.colors.red("✗");

    const writer = std.io.getStdErr().writer();

    var total_duration_buf: [256]u8 = undefined;
    const total_duration = try jetzig.colors.duration(
        &total_duration_buf,
        @intCast(std.time.nanoTimestamp() - start),
        false,
    );

    try writer.print(
        "\n {s}{s}{}" ++
            "\n {s}{s}{}" ++
            "\n  {s}{}" ++
            "\n " ++ jetzig.colors.cyan("    tests ") ++ "{}" ++
            "\n " ++ jetzig.colors.cyan(" duration ") ++ "{s}" ++ "\n\n",
        .{
            if (failure == 0) tick else cross,
            if (failure == 0) jetzig.colors.blue("  failed ") else jetzig.colors.red("  failed "),
            failure,
            if (leaked == 0) tick else cross,
            if (leaked == 0) jetzig.colors.blue("  leaked ") else jetzig.colors.red("  leaked "),
            leaked,
            if (skipped == 0) jetzig.colors.blue(" skipped ") else jetzig.colors.yellow(" skipped "),
            skipped,
            success + failure,
            total_duration,
        },
    );

    if (failure == 0 and leaked == 0) {
        try writer.print(jetzig.colors.green("      PASS   ") ++ "\n", .{});
        try writer.print(jetzig.colors.green("      ▔▔▔▔") ++ "\n", .{});
        std.process.exit(0);
    } else {
        try writer.print(jetzig.colors.red("      FAIL   ") ++ "\n", .{});
        try writer.print(jetzig.colors.red("      ▔▔▔▔") ++ "\n", .{});
        std.process.exit(1);
    }
}
