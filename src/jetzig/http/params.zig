const std = @import("std");

const jetzig = @import("../../jetzig.zig");

/// See `Request.expectParams`.
pub fn expectParams(request: *jetzig.http.Request, T: type) !?T {
    const actual_params = try request.params();

    var t: T = undefined;

    const fields = std.meta.fields(T);
    var statuses: [fields.len]ParamInfo = undefined;
    var failed = false;

    inline for (fields, 0..) |field, index| {
        var maybe_value = actual_params.get(field.name);

        if (isBlank(maybe_value)) {
            maybe_value = null;
        }

        if (maybe_value) |value| {
            switch (@typeInfo(field.type)) {
                .optional => |info| if (value.coerce(info.child)) |coerced| {
                    @field(t, field.name) = coerced;
                    statuses[index] = .{ .present = value.* };
                } else |err| {
                    failed = true;
                    statuses[index] = .{ .failed = .{ .err = err, .value = value.* } };
                },
                // coerce value to target type, null on coerce error (e.g. numeric expected)
                else => {
                    if (value.coerce(field.type)) |coerced| {
                        @field(t, field.name) = coerced;
                        statuses[index] = .{ .present = value.* };
                    } else |err| {
                        failed = true;
                        statuses[index] = .{ .failed = .{ .err = err, .value = value.* } };
                    }
                },
            }
        } else if (@typeInfo(field.type) == .optional) {
            // if no matching param found and params struct provides a default value, use it,
            // otherwise set value to null
            @field(t, field.name) = if (field.default_value_ptr) |default_value_ptr|
                @as(*field.type, @ptrCast(@alignCast(@constCast(default_value_ptr)))).*
            else
                null;
            statuses[index] = .blank;
            // We don't set `failed = true` here because optional values are not required.
        } else {
            statuses[index] = .blank;
            failed = true;
        }
    }

    request._params_info = .{
        .fields = try std.BoundedArray([]const u8, 1024).init(@intCast(fields.len)),
        .params = try std.BoundedArray(ParamInfo, 1024).init(@intCast(fields.len)),
        .required = try std.BoundedArray(bool, 1024).init(@intCast(fields.len)),
    };
    inline for (fields, 0..) |field, index| {
        request._params_info.?.fields.set(index, field.name);
        request._params_info.?.params.set(index, statuses[index]);
        request._params_info.?.required.set(index, @typeInfo(field.type) != .optional);
    }

    if (failed) {
        return null;
    }

    return t;
}

fn isBlank(maybe_value: ?*const jetzig.Data.Value) bool {
    if (maybe_value) |value| {
        return value.* == .string and jetzig.util.strip(value.string.value).len == 0;
    } else return true;
}

/// See `Request.paramsInfo`.
pub const ParamsInfo = struct {
    params: std.BoundedArray(ParamInfo, 1024),
    fields: std.BoundedArray([]const u8, 1024),
    required: std.BoundedArray(bool, 1024),
    state: enum { initial, ready } = .initial,
    hashmap: std.StringHashMap(ParamInfo) = undefined,

    pub fn init(self: ParamsInfo, allocator: std.mem.Allocator) !ParamsInfo {
        var hashmap = std.StringHashMap(ParamInfo).init(allocator);
        try hashmap.ensureTotalCapacity(@intCast(self.params.len));
        for (self.fields.constSlice(), self.params.constSlice()) |field, param_info| {
            hashmap.putAssumeCapacity(field, param_info);
        }
        return .{
            .params = self.params,
            .fields = self.fields,
            .required = self.required,
            .hashmap = hashmap,
            .state = .ready,
        };
    }

    /// Get a information about a param. Provides param status (present/blank/failed) and
    /// original values. See `ParamInfo`.
    pub fn get(self: ParamsInfo, key: []const u8) ?ParamInfo {
        std.debug.assert(self.state == .ready);
        return self.hashmap.get(key);
    }

    /// Detect if any required params are blank or if any errors occurred when coercing params to
    /// their target type.
    pub fn isValid(self: ParamsInfo) bool {
        for (self.params.constSlice(), self.required.constSlice()) |param, required| {
            if (required and param == .blank) return false;
            if (param == .failed) return false;
        }
        return true;
    }

    pub fn format(self: ParamsInfo, _: anytype, _: anytype, writer: anytype) !void {
        std.debug.assert(self.state == .ready);
        var it = self.hashmap.iterator();
        try writer.print("{s}{{ ", .{
            if (self.isValid())
                jetzig.colors.green(@typeName(@TypeOf(self)))
            else
                jetzig.colors.red(@typeName(@TypeOf(self))),
        });
        while (it.next()) |entry| {
            try writer.print("[" ++ jetzig.colors.blue("{s}") ++ ":{}] ", .{ entry.key_ptr.*, entry.value_ptr.* });
        }
        try writer.writeByte('}');
    }
};

/// Status of a param as defined by the last call to `expectParams`.
pub const ParamInfo = union(enum) {
    /// The field was matched and coerced correctly. `value` is the original param value.
    present: jetzig.Data.Value,
    /// The field was not present (regardless of whether the field was optional)
    blank: void,
    /// The field was present but could not be coerced to the required type
    failed: ParamError,

    /// `err` is the error triggered by the type coercion attempt, `value` is the original param
    /// value.
    pub const ParamError = struct {
        err: anyerror,
        value: jetzig.Data.Value,

        pub fn format(self: ParamError, _: anytype, _: anytype, writer: anytype) !void {
            try writer.print(
                jetzig.colors.red("{s}") ++ ":\"" ++ jetzig.colors.yellow("{}") ++ "\"",
                .{ @errorName(self.err), self.value },
            );
        }
    };

    pub fn format(self: ParamInfo, _: anytype, _: anytype, writer: anytype) !void {
        switch (self) {
            .present => |present| try writer.print(
                jetzig.colors.green("present") ++ ":\"" ++ jetzig.colors.cyan("{}") ++ "\"",
                .{present},
            ),
            .blank => try writer.writeAll(jetzig.colors.yellow("blank")),
            .failed => |failed| try writer.print(
                jetzig.colors.red("failed") ++ ":" ++ jetzig.colors.cyan("{}") ++ "",
                .{failed},
            ),
        }
    }
};
