const std = @import("std");

const args = @import("args");

const jetzig = @import("../jetzig.zig");

const Environment = @This();

allocator: std.mem.Allocator,
parent_allocator: std.mem.Allocator,
arena: *std.heap.ArenaAllocator,
logger: jetzig.loggers.Logger,
bind: []const u8,
port: u16,
secret: []const u8,
detach: bool,
environment: jetzig.Environment.EnvironmentName,
vars: jetzig.Environment.Vars,
log_queue: *jetzig.loggers.LogQueue,

pub const EnvironmentName = enum { development, production, testing };
pub const Vars = struct {
    env_map: std.process.EnvMap,

    pub fn get(self: Vars, key: []const u8) ?[]const u8 {
        return self.env_map.get(key);
    }

    pub fn getT(self: Vars, T: type, key: []const u8) !switch (@typeInfo(T)) {
        .bool => T,
        else => ?T,
    } {
        const value = self.env_map.get(key) orelse return if (@typeInfo(T) == .bool)
            false
        else
            null;

        return switch (@typeInfo(T)) {
            .int => try std.fmt.parseInt(T, value, 10),
            .bool => if (std.mem.eql(u8, value, "1"))
                true
            else if (std.mem.eql(u8, value, "0"))
                false
            else
                error.JetzigInvalidEnvironmentVariableBooleanValue,
            .@"enum" => parseEnum(T, value),
            else => @compileError("Unsupported environment value type: `" ++ @typeName(T) ++ "`"),
        };
    }

    pub fn deinit(self: Vars) void {
        var env_map = self.env_map;
        env_map.deinit();
    }

    fn parseEnum(E: type, value: []const u8) ?E {
        return std.meta.stringToEnum(E, value);
    }
};

const Options = struct {
    help: bool = false,
    bind: []const u8 = "127.0.0.1",
    port: u16 = 8080,
    log: []const u8 = "-",
    @"log-error": []const u8 = "-",
    @"log-level": ?jetzig.loggers.LogLevel = null,
    // TODO: Create a production logger and select default logger based on environment.
    @"log-format": jetzig.loggers.LogFormat = .development,
    detach: bool = false,

    pub const shorthands = .{
        .h = "help",
        .b = "bind",
        .p = "port",
        .d = "detach",
    };

    pub const wrap_len = 80;

    pub const meta = .{
        .option_docs = .{
            .bind = "IP address/hostname to bind to (default: 127.0.0.1)",
            .port = "Port to listen on (default: 8080)",
            .log = "Path to log file. Use '-' for stdout (default: '-')",
            .@"log-error" =
            \\Optional path to separate error log file. Use '-' for stderr. If omitted, errors are logged to the location specified by the `log` option (or stderr if `log` is '-').
            ,
            .@"log-level" =
            \\Minimum log level. Log events below the given level are ignored. Must be one of: { TRACE, DEBUG, INFO, WARN, ERROR, FATAL } (default: DEBUG in development, INFO in production)
            ,
            .@"log-format" =
            \\Output logs in the given format. Must be one of: { development, json } (default: development)
            ,
            .detach =
            \\Run the server in the background. Must be used in conjunction with --log (default: false)
            ,
            .help = "Print help and exit",
        },
    };
};

const LaunchLogger = struct {
    stdout: std.fs.File,
    stderr: std.fs.File,

    pub fn log(
        self: LaunchLogger,
        comptime level: jetzig.loggers.LogLevel,
        comptime message: []const u8,
        log_args: anytype,
    ) !void {
        const target = @field(self, @tagName(jetzig.loggers.logTarget(level)));
        const writer = target.writer();
        try writer.print(
            std.fmt.comptimePrint("[startup:{s}] {s}\n", .{ @tagName(level), message }),
            log_args,
        );
    }
};

pub fn init(parent_allocator: std.mem.Allocator) !Environment {
    const arena = try parent_allocator.create(std.heap.ArenaAllocator);
    arena.* = std.heap.ArenaAllocator.init(parent_allocator);
    const allocator = arena.allocator();

    const options = try args.parseForCurrentProcess(Options, allocator, .print);
    defer options.deinit();

    const log_queue = try allocator.create(jetzig.loggers.LogQueue);
    log_queue.* = jetzig.loggers.LogQueue.init(allocator);
    try log_queue.setFiles(
        try getLogFile(.stdout, options.options),
        try getLogFile(.stderr, options.options),
    );

    if (options.options.help) {
        const writer = std.io.getStdErr().writer();
        try args.printHelp(Options, options.executable_name orelse "<app-name>", writer);
        std.process.exit(0);
    }

    const environment = std.enums.nameCast(EnvironmentName, jetzig.environment);
    const vars = Vars{ .env_map = try std.process.getEnvMap(allocator) };

    var launch_logger = LaunchLogger{
        .stdout = try getLogFile(.stdout, options.options),
        .stderr = try getLogFile(.stdout, options.options),
    };

    const logger = switch (options.options.@"log-format") {
        .development => jetzig.loggers.Logger{
            .development_logger = jetzig.loggers.DevelopmentLogger.init(
                allocator,
                resolveLogLevel(options.options.@"log-level", environment),
                log_queue,
            ),
        },
        .json => jetzig.loggers.Logger{
            .json_logger = jetzig.loggers.JsonLogger.init(
                allocator,
                resolveLogLevel(options.options.@"log-level", environment),
                log_queue,
            ),
        },
    };

    if (options.options.detach and std.mem.eql(u8, options.options.log, "-")) {
        try launch_logger.log(.ERROR, "Must pass `--log` when using `--detach`.", .{});
        std.process.exit(1);
    }

    const secret_len = jetzig.http.Session.Cipher.key_length;
    const secret_value = try getSecret(allocator, launch_logger, secret_len, environment);
    const secret = if (secret_value.len > secret_len) secret_value[0..secret_len] else secret_value;

    if (secret.len != secret_len) {
        try launch_logger.log(
            .ERROR,
            "Expected secret length: {}, found: {}.",
            .{ secret_len, secret.len },
        );
        try launch_logger.log(
            .ERROR,
            "Use `jetzig generate secret` to create a secure secret value.",
            .{},
        );
        std.process.exit(1);
    }

    if (jetzig.database.adapter == .null) {
        try launch_logger.log(
            .WARN,
            "No database configured in `config/database.zig`. Database operations are not available.",
            .{},
        );
    } else {
        try launch_logger.log(
            .INFO,
            "Using `{s}` database adapter with database: `{s}`.",
            .{
                @tagName(jetzig.database.adapter),
                switch (environment) {
                    inline else => |tag| @field(jetzig.jetquery.config.database, @tagName(tag)).database,
                },
            },
        );
    }

    return .{
        .allocator = allocator,
        .parent_allocator = parent_allocator,
        .arena = arena,
        .logger = logger,
        .secret = secret,
        .bind = try allocator.dupe(u8, options.options.bind),
        .port = options.options.port,
        .detach = options.options.detach,
        .environment = environment,
        .vars = vars,
        .log_queue = log_queue,
    };
}

pub fn deinit(self: Environment) void {
    self.arena.deinit();
    self.parent_allocator.destroy(self.arena);
}

fn getLogFile(stream: enum { stdout, stderr }, options: Options) !std.fs.File {
    const path = switch (stream) {
        .stdout => options.log,
        .stderr => options.@"log-error",
    };

    if (std.mem.eql(u8, path, "-")) return switch (stream) {
        .stdout => std.io.getStdOut(),
        .stderr => if (std.mem.eql(u8, options.log, "-"))
            std.io.getStdErr()
        else
            try std.fs.createFileAbsolute(options.log, .{ .truncate = false }),
    };

    const file = try std.fs.createFileAbsolute(path, .{ .truncate = false });
    try file.seekFromEnd(0);
    return file;
}

fn getSecret(
    allocator: std.mem.Allocator,
    logger: LaunchLogger,
    comptime len: u10,
    environment: EnvironmentName,
) ![]const u8 {
    const env_var = "JETZIG_SECRET";

    return std.process.getEnvVarOwned(allocator, env_var) catch |err| {
        switch (err) {
            error.EnvironmentVariableNotFound => {
                if (environment == .production) {
                    try logger.log(
                        .ERROR,
                        "Environment variable `{s}` must be defined in production mode.",
                        .{env_var},
                    );
                    try logger.log(
                        .ERROR,
                        "Run `jetzig generate secret` to generate an appropriate value.",
                        .{},
                    );
                    std.process.exit(1);
                }

                const secret = try jetzig.util.generateSecret(allocator, len);
                try logger.log(
                    .WARN,
                    "Running in {s} mode, using auto-generated cookie encryption key: {s}",
                    .{ @tagName(environment), secret },
                );
                try logger.log(
                    .WARN,
                    "Run `jetzig generate secret` and set `JETZIG_SECRET` to remove this warning.",
                    .{},
                );

                return secret;
            },
            else => return err,
        }
    };
}

fn resolveLogLevel(level: ?jetzig.loggers.LogLevel, environment: EnvironmentName) jetzig.loggers.LogLevel {
    return level orelse switch (environment) {
        .testing => .DEBUG,
        .development => .DEBUG,
        .production => .DEBUG,
    };
}
