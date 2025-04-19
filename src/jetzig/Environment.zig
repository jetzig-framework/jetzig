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
    env_file: ?EnvFile,

    pub const EnvFile = struct {
        allocator: std.mem.Allocator,
        hashmap: *std.StringHashMap([]const u8),
        content: []const u8,

        pub fn init(allocator: std.mem.Allocator, file: std.fs.File) !EnvFile {
            const stat = try file.stat();
            const content = try file.readToEndAlloc(allocator, stat.size);
            file.close();
            const hashmap = try allocator.create(std.StringHashMap([]const u8));
            hashmap.* = std.StringHashMap([]const u8).init(allocator);
            var it = std.mem.tokenizeScalar(u8, content, '\n');
            while (it.next()) |line| {
                const stripped = jetzig.util.strip(line);
                if (std.mem.startsWith(u8, stripped, "#")) continue;
                const equals_index = std.mem.indexOfScalar(u8, stripped, '=') orelse continue;
                const name = stripped[0..equals_index];
                const value = if (equals_index + 1 < stripped.len) stripped[equals_index + 1 ..] else "";
                try hashmap.put(name, jetzig.util.unquote(value));
            }

            return .{ .allocator = allocator, .hashmap = hashmap, .content = content };
        }

        pub fn deinit(self: EnvFile) void {
            self.hashmap.deinit();
            self.allocator.destroy(self.hashmap);
            self.allocator.free(self.content);
        }
    };

    pub fn init(allocator: std.mem.Allocator, env_file: ?std.fs.File) !Vars {
        return .{
            .env_file = if (env_file) |file| try EnvFile.init(allocator, file) else null,
            .env_map = try std.process.getEnvMap(allocator),
        };
    }

    pub fn deinit(self: Vars) void {
        var env_map = self.env_map;
        env_map.deinit();
    }

    pub fn get(self: Vars, key: []const u8) ?[]const u8 {
        const env_file = self.env_file orelse return self.env_map.get(key);
        return env_file.hashmap.get(key) orelse self.env_map.get(key);
    }

    pub fn getT(self: Vars, T: type, key: []const u8) !switch (@typeInfo(T)) {
        .bool => T,
        else => ?T,
    } {
        const value = self.get(key) orelse return if (@typeInfo(T) == .bool)
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
    @"log-format": jetzig.loggers.LogFormat = switch (jetzig.environment) {
        .development, .testing => .development,
        .production => .production,
    },
    @"env-file": []const u8 = ".env",
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
            \\Output logs in the given format. Must be one of: { development, production, json, null } (default: development)
            ,
            .detach =
            \\Run the server in the background. Must be used in conjunction with --log (default: false)
            ,
            .@"env-file" =
            \\Load environment variables from a file. Variables defined in this file take precedence over process environment variables.
            ,
            .help = "Print help and exit",
        },
    };
};

const LaunchLogger = struct {
    stdout: std.fs.File,
    stderr: std.fs.File,
    silent: bool = false,

    pub fn log(
        self: LaunchLogger,
        comptime level: jetzig.loggers.LogLevel,
        comptime message: []const u8,
        log_args: anytype,
    ) !void {
        if (self.silent) return;

        const target = @field(self, @tagName(jetzig.loggers.logTarget(level)));
        const writer = target.writer();
        try writer.print(
            std.fmt.comptimePrint("[startup:{s}] {s}\n", .{ @tagName(level), message }),
            log_args,
        );
    }
};

pub const EnvironmentOptions = struct {
    silent: bool = false,
};

pub fn init(parent_allocator: std.mem.Allocator, env_options: EnvironmentOptions) !Environment {
    const arena = try parent_allocator.create(std.heap.ArenaAllocator);
    arena.* = std.heap.ArenaAllocator.init(parent_allocator);
    const allocator = arena.allocator();

    const options = try args.parseForCurrentProcess(Options, allocator, .print);
    defer options.deinit();

    const stdout = try getLogFile(.stdout, options.options);
    const stderr = try getLogFile(.stdout, options.options);

    const log_queue = try allocator.create(jetzig.loggers.LogQueue);
    log_queue.* = jetzig.loggers.LogQueue.init(allocator);

    try log_queue.setFiles(stdout, stderr);

    if (options.options.help) {
        const writer = std.io.getStdErr().writer();
        try args.printHelp(Options, options.executable_name orelse "<app-name>", writer);
        std.process.exit(0);
    }

    const env_file = std.fs.cwd().openFile(options.options.@"env-file", .{}) catch |err|
        switch (err) {
            error.FileNotFound => null,
            else => return err,
        };

    const vars = try Vars.init(allocator, env_file);

    var launch_logger = LaunchLogger{
        .stdout = stdout.file,
        .stderr = stderr.file,
        .silent = env_options.silent,
    };

    const logger = switch (options.options.@"log-format") {
        .development => jetzig.loggers.Logger{
            .development_logger = jetzig.loggers.DevelopmentLogger.init(
                allocator,
                resolveLogLevel(options.options.@"log-level", jetzig.environment),
                stdout.file,
                stderr.file,
            ),
        },
        .production => jetzig.loggers.Logger{
            .production_logger = jetzig.loggers.ProductionLogger.init(
                allocator,
                resolveLogLevel(options.options.@"log-level", jetzig.environment),
                log_queue,
            ),
        },
        .json => jetzig.loggers.Logger{
            .json_logger = jetzig.loggers.JsonLogger.init(
                allocator,
                resolveLogLevel(options.options.@"log-level", jetzig.environment),
                log_queue,
            ),
        },
        .null => jetzig.loggers.Logger{
            .null_logger = jetzig.loggers.NullLogger{},
        },
    };

    if (options.options.detach and std.mem.eql(u8, options.options.log, "-")) {
        try launch_logger.log(.ERROR, "Must pass `--log` when using `--detach`.", .{});
        std.process.exit(1);
    }

    const secret_len = jetzig.http.Session.Cipher.key_length;
    const secret_value = try getSecret(allocator, launch_logger, jetzig.environment);
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
                switch (jetzig.environment) {
                    inline else => |tag| vars.get("JETQUERY_DATABASE") orelse blk: {
                        const config = @field(jetzig.jetquery.config.database, @tagName(tag));
                        break :blk if (comptime @hasField(@TypeOf(config), "database"))
                            config.database
                        else
                            "[no database]";
                    },
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
        .environment = jetzig.environment,
        .vars = vars,
        .log_queue = log_queue,
    };
}

pub fn deinit(self: Environment) void {
    self.arena.deinit();
    self.parent_allocator.destroy(self.arena);
}

fn getLogFile(stream: enum { stdout, stderr }, options: Options) !jetzig.loggers.LogFile {
    const path = switch (stream) {
        .stdout => options.log,
        .stderr => options.@"log-error",
    };

    if (std.mem.eql(u8, path, "-")) return switch (stream) {
        .stdout => .{ .file = std.io.getStdOut(), .sync = false },
        .stderr => if (std.mem.eql(u8, options.log, "-"))
            .{ .file = std.io.getStdErr(), .sync = false }
        else
            .{
                .file = try std.fs.createFileAbsolute(options.log, .{ .truncate = false }),
                .sync = true,
            },
    };

    const file = try std.fs.createFileAbsolute(path, .{ .truncate = false });
    try file.seekFromEnd(0);
    return .{ .file = file, .sync = true };
}

fn getSecret(
    allocator: std.mem.Allocator,
    logger: LaunchLogger,
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

                const secret = "jetzig-development-cookie-secret";

                try logger.log(
                    .WARN,
                    "Running in {s} mode, using default development cookie encryption key: `{s}`",
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
