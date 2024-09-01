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

    var repo = try jetquery.Repo.init(
        allocator,
        .{
            .adapter = .{
                .postgresql = .{
                    .database = "postgres",
                    .username = "postgres",
                    .hostname = "127.0.0.1",
                    .password = "password",
                    .port = 5432,
                },
            },
        },
    );
    defer repo.deinit();

    const migrate = Migrate.init(&repo);
    try migrate.run();
}
