const std = @import("std");
const jetzig = @import("jetzig");

grid: Grid,
victor: ?State = null,

pub const Grid = [9]State;
pub const State = enum { empty, player, cpu, tie };

const Game = @This();

pub fn gridFromValues(values: []*jetzig.data.Value) Grid {
    var grid: [9]Game.State = undefined;
    for (0..9) |id| {
        if (values[id].* != .null) {
            grid[id] = if (values[id].eql("player")) .player else .cpu;
        } else {
            grid[id] = .empty;
        }
    }
    return grid;
}

pub fn movePlayer(game: *Game, cell: usize) bool {
    if (cell >= game.grid.len) return false;
    if (game.grid[cell] != .empty) return false;

    game.grid[cell] = .player;
    game.evaluate();
    return true;
}

pub fn moveCpu(game: *Game) usize {
    std.debug.assert(game.victor == null);
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

pub fn evaluate(game: *Game) void {
    var full = true;
    for (game.grid) |cell| {
        if (cell == .empty) full = false;
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
        var cpu_victor = true;
        var player_victor = true;

        for (pattern) |cell_index| {
            if (game.grid[cell_index] != .cpu) cpu_victor = false;
            if (game.grid[cell_index] != .player) player_victor = false;
        }

        std.debug.assert(!(cpu_victor and player_victor));
        if (cpu_victor) {
            game.victor = .cpu;
            break;
        }
        if (player_victor) {
            game.victor = .player;
            break;
        }
    } else if (full) {
        game.victor = .tie;
    }
}
