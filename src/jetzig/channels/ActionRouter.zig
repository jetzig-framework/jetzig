const std = @import("std");

pub fn initComptime(T: type) ActionRouter {
    comptime {
        var len: usize = 0;
        for (T.views) |view| {
            if (!@hasDecl(view.module, "Channel")) continue;
            if (!@hasDecl(view.module.Channel, "Actions")) continue;

            const actions = view.module.Channel.Actions;
            for (std.meta.declarations(actions)) |_| {
                len += 1;
            }
        }
        var actions: [len]Action = undefined;
        var index: usize = 0;
        for (T.views) |view| {
            if (!@hasDecl(view.module, "Channel")) continue;
            if (!@hasDecl(view.module.Channel, "Actions")) continue;

            const channel_actions = view.module.Channel.Actions;
            for (std.meta.declarations(channel_actions)) |decl| {
                actions[index] = .{
                    .view = view.name,
                    .name = decl.name,
                    .params = &.{}, //@typeInfo(@TypeOf(@field(view.module.Channel.Actions, decl.name))).@"fn".params,
                };
                index += 1;
            }
        }

        const result = actions;
        return .{ .actions = &result };
    }
}

pub const Action = struct {
    view: []const u8,
    name: []const u8,
    params: []const u8,
};

pub const ActionRouter = struct {
    actions: []const Action,
};
