const std = @import("std");

const jetquery = @import("jetquery");
const Migrate = @import("jetquery_migrate");
// const migrations = @import("migrations").migrations;

pub fn main() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer std.debug.assert(gpa.deinit() == .ok);

    const gpa_allocator = gpa.allocator();
    var arena = std.heap.ArenaAllocator.init(gpa_allocator);
    defer arena.deinit();

    const allocator = arena.allocator();

    var repo = try jetquery.Repo.loadConfig(allocator, .{});
    defer repo.deinit();

    const migrate = Migrate.init(&repo);
    try migrate.run();
}
