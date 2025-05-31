const std = @import("std");

const build_options = @import("build_options");

const jetquery = @import("jetquery");
const jetzig = @import("jetzig");
const Migrate = @import("jetquery_migrate").Migrate;
const MigrateSchema = @import("jetquery_migrate").MigrateSchema;
const Seeder = @import("jetquery_seeder").Seed;
const SeederSchema = @import("jetquery_seeder").SeederSchema;
const Schema = @import("Schema");
const util = @import("util.zig");

const confirm_drop_env = "JETZIG_DROP_PRODUCTION_DATABASE";
const production_drop_failure_message = "To drop a production database, " ++
    "set `" ++ confirm_drop_env ++ "={s}`. Exiting.";

const environment = jetzig.build_options.environment;
const config = @field(jetquery.config.database, @tagName(environment));
const Action = enum { migrate, rollback, create, drop, reflect, setup, update, seed };

pub fn main() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer std.debug.assert(gpa.deinit() == .ok);

    if (comptime !@hasField(@TypeOf(config), "adapter") or config.adapter == .null) {
        try util.print(
            .failure,
            "Database is currently not configured. Update `config/database.zig` before running database commands.",
            .{},
        );
        std.process.exit(1);
    }

    const gpa_allocator = gpa.allocator();
    var arena = std.heap.ArenaAllocator.init(gpa_allocator);
    defer arena.deinit();

    const allocator = arena.allocator();

    const args = try std.process.argsAlloc(allocator);

    if (args.len < 2) return error.JetzigMissingArgument;

    const map = std.StaticStringMap(Action).initComptime(.{
        .{ "migrate", .migrate },
        .{ "seed", .seed },
        .{ "rollback", .rollback },
        .{ "create", .create },
        .{ "drop", .drop },
        .{ "reflect", .reflect },
        .{ "setup", .setup },
        .{ "update", .update },
    });
    const action = map.get(args[1]) orelse return error.JetzigUnrecognizedArgument;

    const env = try jetzig.Environment.init(allocator, .{ .silent = true });
    const repo_env = try jetzig.database.repoEnv(env);
    const maybe_database = repo_env.database orelse
        if (comptime @hasField(@TypeOf(config), "database")) @as(?[]const u8, config.database) else null;

    const database = maybe_database orelse {
        std.debug.print("Missing `database` option in `config/database.zig` " ++
            "for current environment or `JETQUERY_DATABASE` environment variable.\n", .{});
        std.process.exit(1);
        return;
    };

    switch (action) {
        .migrate => {
            var repo = try migrationsRepo(action, allocator, repo_env);
            defer repo.deinit();
            try Migrate(config.adapter).init(&repo).migrate();
        },
        .seed => {
            var repo = try seedersRepo(action, allocator, repo_env);
            defer repo.deinit();
            try Seeder(config.adapter, Schema).init(&repo).seed();
        },
        .rollback => {
            var repo = try migrationsRepo(action, allocator, repo_env);
            defer repo.deinit();
            try Migrate(config.adapter).init(&repo).rollback();
        },
        .create => {
            var repo = try migrationsRepo(action, allocator, repo_env);
            defer repo.deinit();
            try repo.createDatabase(database, .{});
        },
        .setup => {
            {
                var repo = try migrationsRepo(.create, allocator, repo_env);
                defer repo.deinit();
                try repo.createDatabase(database, .{});
            }
            {
                var repo = try migrationsRepo(.update, allocator, repo_env);
                defer repo.deinit();
                try Migrate(config.adapter).init(&repo).migrate();
                try reflectSchema(allocator, repo_env);
            }
        },
        .update => {
            var repo = try migrationsRepo(action, allocator, repo_env);
            defer repo.deinit();
            try Migrate(config.adapter).init(&repo).migrate();
            try reflectSchema(allocator, repo_env);
        },
        .drop => {
            if (environment == .production) {
                const confirm = std.process.getEnvVarOwned(allocator, confirm_drop_env) catch |err| {
                    switch (err) {
                        error.EnvironmentVariableNotFound => {
                            std.log.err(production_drop_failure_message, .{database});
                            std.process.exit(1);
                        },
                        else => return err,
                    }
                };
                if (std.mem.eql(u8, confirm, database)) {
                    var repo = try migrationsRepo(action, allocator, repo_env);
                    defer repo.deinit();
                    try repo.dropDatabase(database, .{});
                } else {
                    std.log.err(production_drop_failure_message, .{database});
                    std.process.exit(1);
                }
            } else {
                var repo = try migrationsRepo(action, allocator, repo_env);
                defer repo.deinit();
                try repo.dropDatabase(database, .{});
            }
        },
        .reflect => {
            try reflectSchema(allocator, repo_env);
        },
    }
}

const MigrationsRepo = jetquery.Repo(config.adapter, MigrateSchema);
fn migrationsRepo(action: Action, allocator: std.mem.Allocator, repo_env: anytype) !MigrationsRepo {
    return try MigrationsRepo.loadConfig(
        allocator,
        @field(jetquery.Environment, @tagName(environment)),
        .{
            .admin = switch (action) {
                .migrate, .seed, .rollback, .update => false,
                .create, .drop => true,
                .reflect => unreachable, // We use a separate repo for schema reflection.
                .setup => unreachable, // Setup uses `create` and then `update`
            },
            .context = .migration,
            .env = repo_env,
        },
    );
}

const SeedersRepo = jetquery.Repo(config.adapter, Schema);
fn seedersRepo(action: Action, allocator: std.mem.Allocator, repo_env: anytype) !SeedersRepo {
    return try SeedersRepo.loadConfig(
        allocator,
        @field(jetquery.Environment, @tagName(environment)),
        .{
            .admin = switch (action) {
                .migrate, .seed, .rollback, .update => false,
                .create, .drop => false,
                .reflect => unreachable, // We use a separate repo for schema reflection.
                .setup => unreachable, // Setup uses `create` and then `update`
            },
            .context = .seed,
            .env = repo_env,
        },
    );
}

fn reflectSchema(allocator: std.mem.Allocator, repo_env: anytype) !void {
    var cwd = try jetzig.util.detectJetzigProjectDir();
    defer cwd.close();

    const Repo = jetquery.Repo(config.adapter, Schema);
    var repo = try Repo.loadConfig(
        allocator,
        @field(jetquery.Environment, @tagName(environment)),
        .{ .context = .migration, .env = repo_env },
    );
    const reflect = @import("jetquery_reflect").Reflect(config.adapter, Schema).init(
        allocator,
        &repo,
        .{
            .import_jetquery =
            \\@import("jetzig").jetquery
            ,
        },
    );
    const schema = try reflect.generateSchema();
    const project_dir = try jetzig.util.detectJetzigProjectDir();
    const project_dir_realpath = try project_dir.realpathAlloc(allocator, ".");
    const path = try std.fs.path.join(
        allocator,
        &.{ project_dir_realpath, "src", "app", "database", "Schema.zig" },
    );
    try jetzig.util.createFile(path, schema);
    std.log.info("Database schema written to `{s}`.", .{path});
}
