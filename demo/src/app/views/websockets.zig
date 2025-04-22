const std = @import("std");
const jetzig = @import("jetzig");

pub fn index(request: *jetzig.Request, data: *jetzig.Data) !jetzig.View {
    _ = data;
    return request.render(.ok);
}

pub fn get(id: []const u8, request: *jetzig.Request, data: *jetzig.Data) !jetzig.View {
    _ = data;
    _ = id;
    return request.render(.ok);
}

pub fn post(request: *jetzig.Request, data: *jetzig.Data) !jetzig.View {
    _ = data;
    return request.render(.created);
}

pub fn put(id: []const u8, request: *jetzig.Request, data: *jetzig.Data) !jetzig.View {
    _ = data;
    _ = id;
    return request.render(.ok);
}

pub fn patch(id: []const u8, request: *jetzig.Request, data: *jetzig.Data) !jetzig.View {
    _ = data;
    _ = id;
    return request.render(.ok);
}

pub fn delete(id: []const u8, request: *jetzig.Request, data: *jetzig.Data) !jetzig.View {
    _ = data;
    _ = id;
    return request.render(.ok);
}

pub const Channel = struct {
    pub fn open(channel: jetzig.channels.Channel) !void {
        if (channel.get("cells") == null) try initGame(channel);
        try channel.sync();
    }

    pub fn receive(message: jetzig.channels.Message) !void {
        const value = try message.value();

        if (value.getT(.boolean, "reset") == true) {
            try resetGame(message.channel);
            try message.channel.sync();
            return;
        }

        const cell: usize = if (value.getT(.integer, "cell")) |integer|
            @intCast(integer)
        else
            return;
        const cells = message.channel.getT(.array, "cells") orelse return;
        const items = cells.items();

        var grid: [9]Game.State = undefined;
        for (0..9) |id| {
            if (items[id].* != .null) {
                grid[id] = if (items[id].eql("player")) .player else .cpu;
            } else {
                grid[id] = .empty;
            }
        }

        var game = Game{ .grid = grid };
        game.evaluate();

        if (game.winner != null) {
            try message.channel.publish(.{ .err = "Game is already over." });
            return;
        }

        if (game.movePlayer(cell)) {
            items[cell] = message.data.string("player");
            if (game.winner == null) {
                items[game.moveCpu()] = message.data.string("cpu");
            }
            if (game.winner) |winner| {
                try message.channel.put("winner", @tagName(winner));
                var results = message.channel.getT(.object, "results") orelse return;
                const count = results.getT(.integer, @tagName(winner)) orelse return;
                try results.put(@tagName(winner), count + 1);
            }
        }

        try message.channel.sync();
    }

    fn resetGame(channel: jetzig.channels.Channel) !void {
        try channel.put("winner", null);
        var cells = try channel.put("cells", .array);
        for (0..9) |_| try cells.append(null);
    }

    fn initGame(channel: jetzig.channels.Channel) !void {
        var results = try channel.put("results", .object);
        try results.put("cpu", 0);
        try results.put("player", 0);
        try results.put("ties", 0);
        try resetGame(channel);
    }
};

const Game = struct {
    grid: [9]State,
    winner: ?State = null,

    pub const State = enum { empty, player, cpu, tie };

    pub fn movePlayer(game: *Game, cell: usize) bool {
        if (cell >= game.grid.len) return false;
        if (game.grid[cell] != .empty) return false;

        game.grid[cell] = .player;
        game.evaluate();
        return true;
    }

    pub fn moveCpu(game: *Game) usize {
        std.debug.assert(game.winner == null);
        var available: [9]usize = undefined;
        var available_len: usize = 0;
        for (game.grid, 0..) |cell, cell_index| {
            if (cell == .empty) {
                available[available_len] = cell_index;
                available_len += 1;
            }
        }
        std.debug.assert(available_len > 0);
        const choice = available[std.crypto.random.intRangeAtMost(usize, 0, available_len - 1)];
        game.grid[choice] = .cpu;
        game.evaluate();
        return choice;
    }

    fn evaluate(game: *Game) void {
        var full = true;
        for (game.grid) |cell| {
            if (cell == .empty) full = false;
        }
        if (full) {
            game.winner = .tie;
            return;
        }

        const patterns = [_][3]usize{
            .{ 0, 1, 2 },
            .{ 3, 4, 5 },
            .{ 6, 7, 8 },
            .{ 0, 3, 6 },
            .{ 1, 4, 7 },
            .{ 2, 5, 8 },
            .{ 0, 4, 8 },
            .{ 2, 4, 6 },
        };
        for (patterns) |pattern| {
            var cpu_winner = true;
            var player_winner = true;

            for (pattern) |cell_index| {
                if (game.grid[cell_index] != .cpu) cpu_winner = false;
                if (game.grid[cell_index] != .player) player_winner = false;
            }

            std.debug.assert(!(cpu_winner and player_winner));
            if (cpu_winner) game.winner = .cpu;
            if (player_winner) game.winner = .player;
        }
    }
};

test "index" {
    var app = try jetzig.testing.app(std.testing.allocator, @import("routes"));
    defer app.deinit();

    const response = try app.request(.GET, "/websockets", .{});
    try response.expectStatus(.ok);
}

test "get" {
    var app = try jetzig.testing.app(std.testing.allocator, @import("routes"));
    defer app.deinit();

    const response = try app.request(.GET, "/websockets/example-id", .{});
    try response.expectStatus(.ok);
}

test "post" {
    var app = try jetzig.testing.app(std.testing.allocator, @import("routes"));
    defer app.deinit();

    const response = try app.request(.POST, "/websockets", .{});
    try response.expectStatus(.created);
}

test "put" {
    var app = try jetzig.testing.app(std.testing.allocator, @import("routes"));
    defer app.deinit();

    const response = try app.request(.PUT, "/websockets/example-id", .{});
    try response.expectStatus(.ok);
}

test "patch" {
    var app = try jetzig.testing.app(std.testing.allocator, @import("routes"));
    defer app.deinit();

    const response = try app.request(.PATCH, "/websockets/example-id", .{});
    try response.expectStatus(.ok);
}

test "delete" {
    var app = try jetzig.testing.app(std.testing.allocator, @import("routes"));
    defer app.deinit();

    const response = try app.request(.DELETE, "/websockets/example-id", .{});
    try response.expectStatus(.ok);
}
