const std = @import("std");

const jetzig = @import("../jetzig.zig");

pub const BeforeCallback = *const fn (
    *jetzig.http.Request,
    jetzig.views.Route,
) anyerror!void;

pub const AfterCallback = *const fn (
    *jetzig.http.Request,
    *jetzig.http.Response,
    jetzig.views.Route,
) anyerror!void;

pub const Context = enum { before, after };

pub fn beforeCallbacks(view: type) []const BeforeCallback {
    comptime {
        return buildCallbacks(.before, view);
    }
}

pub fn afterCallbacks(view: type) []const AfterCallback {
    comptime {
        return buildCallbacks(.after, view);
    }
}

fn buildCallbacks(comptime context: Context, view: type) switch (context) {
    .before => []const BeforeCallback,
    .after => []const AfterCallback,
} {
    comptime {
        if (!@hasDecl(view, "actions")) return &.{};
        if (!@hasField(@TypeOf(view.actions), @tagName(context))) return &.{};

        var size: usize = 0;
        for (@field(view.actions, @tagName(context))) |module| {
            if (isCallback(context, module)) {
                size += 1;
            } else {
                @compileError(std.fmt.comptimePrint(
                    "`{0s}` callbacks must be either a function `{1s}` or a type that defines " ++
                        "`pub const {0s}Render`. Found: `{2s}`",
                    .{
                        @tagName(context),
                        switch (context) {
                            .before => @typeName(BeforeCallback),
                            .after => @typeName(AfterCallback),
                        },
                        if (@TypeOf(module) == type)
                            @typeName(module)
                        else
                            @typeName(@TypeOf(&module)),
                    },
                ));
            }
        }

        var callbacks: [size]switch (context) {
            .before => BeforeCallback,
            .after => AfterCallback,
        } = undefined;
        var index: usize = 0;
        for (@field(view.actions, @tagName(context))) |module| {
            if (!isCallback(context, module)) continue;

            callbacks[index] = if (@TypeOf(module) == type)
                @field(module, @tagName(context) ++ "Render")
            else
                &module;

            index += 1;
        }

        const final = callbacks;
        return &final;
    }
}

fn isCallback(comptime context: Context, comptime module: anytype) bool {
    comptime {
        if (@typeInfo(@TypeOf(module)) == .@"fn") {
            const expected = switch (context) {
                .before => BeforeCallback,
                .after => AfterCallback,
            };

            const info = @typeInfo(@TypeOf(module)).@"fn";

            const actual_params = info.params;
            const expected_params = @typeInfo(@typeInfo(expected).pointer.child).@"fn".params;

            if (actual_params.len != expected_params.len) return false;

            for (actual_params, expected_params) |actual_param, expected_param| {
                if (actual_param.type != expected_param.type) return false;
            }

            if (@typeInfo(info.return_type.?) != .error_union) return false;
            if (@typeInfo(info.return_type.?).error_union.payload != void) return false;

            return true;
        }

        return if (@TypeOf(module) == type and @hasDecl(module, @tagName(context) ++ "Render"))
            true
        else
            false;
    }
}
