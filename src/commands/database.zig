const std = @import("std");

const build_options = @import("build_options");

const jetquery = @import("jetquery");
const Migrate = @import("jetquery_migrate").Migrate;
const MigrateSchema = @import("jetquery_migrate").MigrateSchema;

const confirm_drop_env = "JETZIG_DROP_PRODUCTION_DATABASE";
const production_drop_failure_message = "To drop a production database, " ++
    "set `JETZIG_DROP_PRODUCTION_DATABASE={s}`. Exiting.";

pub fn main() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer std.debug.assert(gpa.deinit() == .ok);

    const gpa_allocator = gpa.allocator();
    var arena = std.heap.ArenaAllocator.init(gpa_allocator);
    defer arena.deinit();

    const allocator = arena.allocator();

    const args = try std.process.argsAlloc(allocator);

    if (args.len < 2) return error.JetzigMissingDatabaseArgument;

    const Action = enum { migrate, rollback, create, drop };
    const map = std.StaticStringMap(Action).initComptime(.{
        .{ "migrate", .migrate },
        .{ "rollback", .rollback },
        .{ "create", .create },
        .{ "drop", .drop },
    });
    const action = map.get(args[1]) orelse return error.JetzigUnrecognizedDatabaseArgument;

    const environment = build_options.environment;
    const config = @field(jetquery.config.database, @tagName(environment));

    const Repo = jetquery.Repo(config.adapter, MigrateSchema);
    var repo = try Repo.loadConfig(
        allocator,
        std.enums.nameCast(jetquery.Environment, environment),
        .{
            .admin = switch (action) {
                .migrate, .rollback => false,
                .create, .drop => true,
            },
            .context = .migration,
        },
    );
    defer repo.deinit();

    switch (action) {
        .migrate => {
            try Migrate(config.adapter).init(&repo).migrate();
        },
        .rollback => {
            try Migrate(config.adapter).init(&repo).rollback();
        },
        .create => {
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
                    try repo.dropDatabase(config.database, .{});
                } else {
                    std.log.err(production_drop_failure_message, .{config.database});
                    std.process.exit(1);
                }
            } else {
                try repo.dropDatabase(config.database, .{});
            }
        },
    }
}
