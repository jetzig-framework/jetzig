const std = @import("std");
const jetzig = @import("jetzig");

const Game = @import("../lib/Game.zig");

pub const layout = "application";

pub fn index(request: *jetzig.Request) !jetzig.View {
    return request.render(.ok);
}

pub const Channel = struct {
    pub fn open(channel: jetzig.channels.Channel) !void {
        if (channel.get("cells") == null) try initGame(channel);
        try channel.sync();
    }

    pub const Actions = struct {
        pub fn move(channel: jetzig.channels.Channel, cell: usize) !void {
            const cells = channel.getT(.array, "cells") orelse return;
            const grid = Game.gridFromValues(cells.items());
            var game = Game{ .grid = grid };
            game.evaluate();

            if (game.victor != null) {
                try channel.invoke(.game_over, .{});
                return;
            } else {
                try movePlayer(channel, &game, cells, cell);
                try channel.sync();
            }
        }

        pub fn reset(channel: jetzig.channels.Channel) !void {
            try resetGame(channel);
            try channel.sync();
        }
    };

    fn resetGame(channel: jetzig.channels.Channel) !void {
        try channel.put("victor", null);
        var cells = try channel.put("cells", .array);
        for (0..9) |_| try cells.append(null);
    }

    fn initGame(channel: jetzig.channels.Channel) !void {
        var results = try channel.put("results", .object);
        try results.put("cpu", 0);
        try results.put("player", 0);
        try results.put("tie", 0);
        try resetGame(channel);
    }

    fn movePlayer(
        channel: jetzig.channels.Channel,
        game: *Game,
        cells: *const jetzig.data.Array,
        cell: usize,
    ) !void {
        const values = cells.items();
        if (game.movePlayer(cell)) {
            values[cell] = channel.data.string("player");
            if (game.victor == null) {
                values[game.moveCpu()] = channel.data.string("cpu");
            }
            if (game.victor) |victor| try setVictor(channel, victor);
        }
    }

    fn setVictor(channel: jetzig.channels.Channel, victor: Game.State) !void {
        try channel.put("victor", @tagName(victor));
        var results = channel.getT(.object, "results") orelse return;
        const count = results.getT(.integer, @tagName(victor)) orelse return;
        try results.put(@tagName(victor), count + 1);
        try channel.invoke(.victor, .{ .type = @tagName(victor) });
    }
};
