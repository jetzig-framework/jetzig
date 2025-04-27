const std = @import("std");

const jetzig = @import("../../jetzig.zig");

pub const Action = struct {
    view: []const u8,
    name: []const u8,
    params: []const std.builtin.Type.Fn.Param,
};

pub const ActionRouter = struct {
    actions: []const Action,
    routes: type,
    encoded_params: std.StaticStringMap([]const u8),

    pub fn invoke(
        comptime router: ActionRouter,
        allocator: std.mem.Allocator,
        path: []const u8,
        data: []const u8,
        Channel: type,
        channel: Channel,
    ) !?[]const u8 {
        inline for (router.actions) |action| {
            if (match(action, path, data)) {
                var d = jetzig.data.Data.init(allocator);
                defer d.deinit();

                // Format should be at least e.g.: `_invoke:foo:[]`
                if (data.len < prefix(action).len + 2) return error.InvalidChannelActionArguments;
                try d.fromJson(data[prefix(action).len..]);

                const received_args = switch (d.value.?.*) {
                    .array => |array| array.array.items,
                    else => return error.InvalidChannelActionArguments,
                };

                const view = router.routes.views.get(action.view).?;
                const func = @field(view.module.Channel.Actions, action.name);
                const Args = std.meta.ArgsTuple(@TypeOf(func));
                var args: Args = undefined;

                const expected_args = std.meta.fields(Args);
                if (expected_args.len < 1 or received_args.len != expected_args.len - 1) {
                    return error.InvalidChannelActionArguments;
                }

                args[0] = channel;
                if (comptime action.params.len > 1) {
                    inline for (action.params[1..], 0..) |param, index| {
                        args[index + 1] = try coerce(param.type.?, received_args[index].*);
                    }
                }
                try @call(.auto, func, args);
                return action.name;
            }
        }
        return null;
    }

    pub fn encodedParams(comptime router: ActionRouter, route: jetzig.channels.Route) ?[]const u8 {
        if (router.routes.channel_routes.get(route.path)) |matched_route| {
            _ = matched_route;
        }
    }
    fn match(comptime action: Action, path: []const u8, data: []const u8) bool {
        return (std.mem.eql(u8, action.view, path)) and std.mem.startsWith(
            u8,
            data,
            prefix(action),
        );
    }

    inline fn prefix(comptime action: Action) []const u8 {
        return "_invoke:" ++ action.name ++ ":";
    }

    fn coerce(T: type, value: jetzig.data.Value) !T {
        return switch (T) {
            []const u8 => switch (value) {
                .string => |v| v.value,
                else => error.InvalidChannelActionArguments,
            },
            else => switch (@typeInfo(T)) {
                .int => switch (value) {
                    .integer => |v| @intCast(v.value),
                    else => error.InvalidChannelActionArguments,
                },
                .float => switch (value) {
                    .float => |v| @floatCast(v.value),
                    else => error.InvalidChannelActionArguments,
                },
                .bool => switch (value) {
                    .boolean => |v| v.value,
                    else => error.InvalidChannelActionArguments,
                },
                else => error.InvalidChannelActionArguments,
            },
        };
    }
};

pub fn initComptime(Routes: type) ActionRouter {
    comptime {
        var len: usize = 0;
        for (Routes.views.values()) |view| {
            if (!@hasDecl(view.module, "Channel")) continue;
            if (!@hasDecl(view.module.Channel, "Actions")) continue;

            const actions = view.module.Channel.Actions;
            for (std.meta.declarations(actions)) |_| {
                len += 1;
            }
        }
        var actions: [len]Action = undefined;
        var index: usize = 0;
        for (Routes.views.values()) |view| {
            if (!@hasDecl(view.module, "Channel")) continue;
            if (!@hasDecl(view.module.Channel, "Actions")) continue;

            const channel_actions = view.module.Channel.Actions;
            const decls = std.meta.declarations(channel_actions);
            for (decls) |decl| {
                const params = @typeInfo(
                    @TypeOf(@field(view.module.Channel.Actions, decl.name)),
                ).@"fn".params;
                actions[index] = .{
                    .view = view.name,
                    .name = decl.name,
                    .params = params,
                };
                index += 1;
            }
        }

        const encoded_params = try encodeParams(Routes);
        const result = actions;
        return .{ .actions = &result, .routes = Routes, .encoded_params = encoded_params };
    }
}

fn encodeParams(Routes: type) !std.StaticStringMap([]const u8) {
    // We do a bit of awkward encoding here to ensure that we have a pre-compiled JSON string
    // that we can send to the websocket after intialization to give the Jetzig Javascript code a
    // spec for all available actions.
    comptime {
        const Spec = struct {
            actions: []ActionSpec,
            pub const ActionSpec = struct {
                name: []const u8,
                params: []const ParamSpec,

                pub const ParamSpec = struct {
                    type: []const u8,
                    name: []const u8,
                };
            };
        };
        const Tuple = std.meta.Tuple(&.{ []const u8, []const u8 });
        var map: [Routes.views.keys().len]Tuple = undefined;

        for (Routes.views.values(), 0..) |view, view_index| {
            const has_actions = @hasDecl(view.module, "Channel") and
                @hasDecl(view.module.Channel, "Actions");

            const channel_actions = if (has_actions) view.module.Channel.Actions else struct {};
            const decls = std.meta.declarations(channel_actions);

            var channel_params: Spec = undefined;
            var actions: [decls.len]Spec.ActionSpec = undefined;

            for (decls, 0..) |decl, decl_index| {
                switch (@typeInfo(@TypeOf(@field(view.module.Channel.Actions, decl.name)))) {
                    .@"fn" => |info| {
                        verifyParams(info.params, view.name, decl.name);
                        const route = Routes.channel_routes.get(view.name).?;
                        const action = for (route.actions) |action| {
                            if (std.mem.eql(u8, action.name, decl.name)) break action;
                        } else unreachable;
                        if (info.params.len > 1) {
                            var params: [info.params.len - 1]Spec.ActionSpec.ParamSpec = undefined;
                            for (info.params[1..], 0..) |param, param_index| {
                                params[param_index] = .{
                                    .type = jsonTypeName(param.type.?),
                                    .name = action.params[param_index].name,
                                };
                            }
                            actions[decl_index] = .{ .name = decl.name, .params = &params };
                        } else {
                            actions[decl_index] = .{ .name = decl.name, .params = &.{} };
                        }
                    },
                    else => {},
                }
            }

            channel_params.actions = &actions;
            var counting_stream = std.io.countingWriter(std.io.null_writer);
            try std.json.stringify(channel_params, .{}, counting_stream.writer());

            var buf: [counting_stream.bytes_written]u8 = undefined;
            var stream = std.io.fixedBufferStream(&buf);
            try std.json.stringify(channel_params, .{}, stream.writer());
            const written = buf;
            map[view_index] = .{ view.name, &written };
        }

        return std.StaticStringMap([]const u8).initComptime(map);
    }
}

fn verifyParams(
    params: []const std.builtin.Type.Fn.Param,
    view: []const u8,
    action: []const u8,
) void {
    const humanized = std.fmt.comptimePrint("Channel Action {s}:{s}", .{ view, action });
    const too_few_params = "Expected at least 1 parameter for " ++ humanized;
    const missing_param = "Incorrect first argument (must be jetzig.channels.Channel) for " ++ humanized;

    if (params.len < 1) @compileError(too_few_params);
    if (params[0].type.? != jetzig.channels.Channel) @compileError(missing_param);
}

fn jsonTypeName(T: type) []const u8 {
    return switch (T) {
        []const u8 => "string",
        else => switch (@typeInfo(T)) {
            .float, .comptime_float => "float",
            .int, .comptime_int => "integer",
            .bool => "bool",
            else => @compileError("Unsupported Channel Action argument type: " ++ @typeName(T)),
        },
    };
}
