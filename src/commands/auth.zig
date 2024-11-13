const std = @import("std");

const build_options = @import("build_options");

const jetquery = @import("jetquery");
const jetzig = @import("jetzig");
const Schema = @import("Schema");
const Action = enum { @"user:create" };

pub fn main() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer std.debug.assert(gpa.deinit() == .ok);

    const gpa_allocator = gpa.allocator();
    var arena = std.heap.ArenaAllocator.init(gpa_allocator);
    defer arena.deinit();

    const allocator = arena.allocator();

    const args = try std.process.argsAlloc(allocator);

    if (args.len < 3) return error.JetzigMissingArgument;

    const map = std.StaticStringMap(Action).initComptime(.{
        .{ "user:create", .@"user:create" },
    });

    const action = map.get(args[1]) orelse return error.JetzigUnrecognizedArgument;
    const env = try jetzig.Environment.init(allocator, .{ .silent = true });

    switch (action) {
        .@"user:create" => {
            const Repo = jetzig.jetquery.Repo(jetzig.database.adapter, Schema);
            var repo = try Repo.loadConfig(
                allocator,
                std.enums.nameCast(jetzig.jetquery.Environment, jetzig.environment),
                .{ .env = try jetzig.database.repoEnv(env), .context = .cli },
            );
            defer repo.deinit();

            const model = comptime jetzig.config.get(jetzig.auth.AuthOptions, "auth").user_model;
            const stdin = std.io.getStdIn();
            const reader = stdin.reader();

            const password = if (stdin.isTty() and args.len < 4) blk: {
                std.debug.print("Enter password: ", .{});
                var buf: [1024]u8 = undefined;
                if (try reader.readUntilDelimiterOrEof(&buf, '\n')) |input| {
                    break :blk std.mem.trim(u8, input, &std.ascii.whitespace);
                } else {
                    std.debug.print("Blank password. Exiting.\n", .{});
                    return;
                }
            } else if (args.len >= 4)
                args[3]
            else {
                std.debug.print("Blank password. Exiting.\n", .{});
                return;
            };

            const email = args[2];

            try repo.insert(std.enums.nameCast(std.meta.DeclEnum(Schema), model), .{
                .email = email,
                .password_hash = try hashPassword(allocator, password),
            });
            std.debug.print("Created user: `{s}`.\n", .{email});
        },
    }
}

fn hashPassword(allocator: std.mem.Allocator, password: []const u8) ![]const u8 {
    const buf = try allocator.alloc(u8, 128);
    return try std.crypto.pwhash.argon2.strHash(
        password,
        .{
            .allocator = allocator,
            .params = .{ .t = 3, .m = 32, .p = 4 },
        },
        buf,
    );
}
