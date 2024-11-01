const std = @import("std");

const build_options = @import("build_options");

const jetquery = @import("jetquery");
const jetzig = @import("jetzig");
const Migrate = @import("jetquery_migrate").Migrate;
const MigrateSchema = @import("jetquery_migrate").MigrateSchema;
const Schema = @import("Schema");

const confirm_drop_env = "JETZIG_DROP_PRODUCTION_DATABASE";
const production_drop_failure_message = "To drop a production database, " ++
    "set `" ++ confirm_drop_env ++ "={s}`. Exiting.";

const environment = jetzig.build_options.environment;
const config = @field(jetquery.config.database, @tagName(environment));
const Action = enum { migrate, rollback, create, drop, schema };

pub fn main() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer std.debug.assert(gpa.deinit() == .ok);

    const gpa_allocator = gpa.allocator();
    var arena = std.heap.ArenaAllocator.init(gpa_allocator);
    defer arena.deinit();

    const allocator = arena.allocator();

    const args = try std.process.argsAlloc(allocator);

    if (args.len < 2) return error.JetzigMissingDatabaseArgument;

    const map = std.StaticStringMap(Action).initComptime(.{
        .{ "migrate", .migrate },
        .{ "rollback", .rollback },
        .{ "create", .create },
        .{ "drop", .drop },
        .{ "schema", .schema },
    });
    const action = map.get(args[1]) orelse return error.JetzigUnrecognizedDatabaseArgument;

    switch (action) {
        .migrate => {
            var repo = try migrationsRepo(action, allocator);
            defer repo.deinit();
            try Migrate(config.adapter).init(&repo).migrate();
        },
        .rollback => {
            var repo = try migrationsRepo(action, allocator);
            defer repo.deinit();
            try Migrate(config.adapter).init(&repo).rollback();
        },
        .create => {
            var repo = try migrationsRepo(action, allocator);
            defer repo.deinit();
            try repo.createDatabase(config.database, .{});
        },
        .drop => {
            if (environment == .production) {
                const confirm = std.process.getEnvVarOwned(allocator, confirm_drop_env) catch |err| {
                    switch (err) {
                        error.EnvironmentVariableNotFound => {
                            std.log.err(production_drop_failure_message, .{config.database});
                            std.process.exit(1);
                        },
                        else => return err,
                    }
                };
                if (std.mem.eql(u8, confirm, config.database)) {
                    var repo = try migrationsRepo(action, allocator);
                    defer repo.deinit();
                    try repo.dropDatabase(config.database, .{});
                } else {
                    std.log.err(production_drop_failure_message, .{config.database});
                    std.process.exit(1);
                }
            } else {
                var repo = try migrationsRepo(action, allocator);
                defer repo.deinit();
                try repo.dropDatabase(config.database, .{});
            }
        },
        .schema => {
            const Repo = jetquery.Repo(config.adapter, Schema);
            var repo = try Repo.loadConfig(
                allocator,
                std.enums.nameCast(jetquery.Environment, environment),
                .{ .context = .migration },
            );
            const reflect = @import("jetquery_reflect").Reflect(config.adapter, Schema).init(
                allocator,
                &repo,
            );
            const schema = try reflect.generateSchema();
            std.debug.print("{s}\n", .{schema});
        },
    }
}

const MigrationsRepo = jetquery.Repo(config.adapter, MigrateSchema);
fn migrationsRepo(action: Action, allocator: std.mem.Allocator) !MigrationsRepo {
    return try MigrationsRepo.loadConfig(
        allocator,
        std.enums.nameCast(jetquery.Environment, environment),
        .{
            .admin = switch (action) {
                .migrate, .rollback => false,
                .create, .drop => true,
                .schema => undefined, // We use a separate repo for schema reflection.
            },
            .context = .migration,
        },
    );
}
