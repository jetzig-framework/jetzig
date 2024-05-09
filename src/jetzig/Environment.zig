const std = @import("std");

const args = @import("args");

const jetzig = @import("../jetzig.zig");

const Environment = @This();

allocator: std.mem.Allocator,

pub const EnvironmentName = enum { development, production };

const Options = struct {
    help: bool = false,
    bind: []const u8 = "127.0.0.1",
    port: u16 = 8080,
    environment: EnvironmentName = .development,
    log: []const u8 = "-",
    @"log-error": []const u8 = "-",
    @"log-level": ?jetzig.loggers.LogLevel = null,
    @"log-format": jetzig.loggers.LogFormat = .development,
    detach: bool = false,

    pub const shorthands = .{
        .h = "help",
        .b = "bind",
        .p = "port",
        .e = "environment",
        .d = "detach",
    };

    pub const wrap_len = 80;

    pub const meta = .{
        .option_docs = .{
            .bind = "IP address/hostname to bind to (default: 127.0.0.1)",
            .port = "Port to listen on (default: 8080)",
            .environment = "Set the server environment. Must be one of: { development, production } (default: development)",
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

pub fn init(allocator: std.mem.Allocator) Environment {
    return .{ .allocator = allocator };
}

/// Generate server initialization options using command line args with defaults.
pub fn getServerOptions(
    self: Environment,
    log_queue: *jetzig.loggers.LogQueue,
) !jetzig.http.Server.ServerOptions {
    const options = try args.parseForCurrentProcess(Options, self.allocator, .print);
    defer options.deinit();

    if (options.options.help) {
        const writer = std.io.getStdErr().writer();
        try args.printHelp(Options, options.executable_name orelse "<app-name>", writer);
        std.process.exit(0);
    }

    const environment = options.options.environment;

    var logger = switch (options.options.@"log-format") {
        .development, .json => jetzig.loggers.Logger{
            .development_logger = jetzig.loggers.DevelopmentLogger.init(
                self.allocator,
                resolveLogLevel(options.options.@"log-level", environment),
                log_queue,
                // try getLogFile(.stdout, options.options),
                // try getLogFile(.stderr, options.options),
            ),
        },
        // TODO
        // .json => jetzig.loggers.Logger{
        //     .json_logger = jetzig.loggers.JsonLogger.init(
        //         self.allocator,
        //         resolveLogLevel(options.options.@"log-level", environment),
        //         try getLogFile(.stdout, options.options),
        //         try getLogFile(.stderr, options.options),
        //     ),
        // },
    };

    if (options.options.detach and std.mem.eql(u8, options.options.log, "-")) {
        try logger.ERROR("Must pass `--log` when using `--detach`.", .{});
        std.process.exit(1);
    }

    const secret_len = jetzig.http.Session.Cipher.key_length;
    const secret = (try self.getSecret(&logger, secret_len, environment))[0..secret_len];

    if (secret.len != secret_len) {
        try logger.ERROR("Expected secret length: {}, found: {}.", .{ secret_len, secret.len });
        try logger.ERROR("Use `jetzig generate secret` to create a secure secret value.", .{});
        std.process.exit(1);
    }

    return .{
        .logger = logger,
        .secret = secret,
        .bind = try self.allocator.dupe(u8, options.options.bind),
        .port = options.options.port,
        .detach = options.options.detach,
        .environment = environment,
    };
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

fn getSecret(self: Environment, logger: *jetzig.loggers.Logger, comptime len: u10, environment: EnvironmentName) ![]const u8 {
    const env_var = "JETZIG_SECRET";

    return std.process.getEnvVarOwned(self.allocator, env_var) catch |err| {
        switch (err) {
            error.EnvironmentVariableNotFound => {
                if (environment != .development) {
                    try logger.ERROR("Environment variable `{s}` must be defined in production mode.", .{env_var});
                    try logger.ERROR("Run `jetzig generate secret` to generate an appropriate value.", .{});
                    std.process.exit(1);
                }

                const secret = try jetzig.util.generateSecret(self.allocator, len);
                try logger.WARN(
                    "Running in development mode, using auto-generated cookie encryption key: {s}",
                    .{secret},
                );
                try logger.WARN(
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
        .development => .DEBUG,
        .production => .INFO,
    };
}
