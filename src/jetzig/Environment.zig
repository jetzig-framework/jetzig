const std = @import("std");

const args = @import("args");

const jetzig = @import("../jetzig.zig");

const Environment = @This();

allocator: std.mem.Allocator,

const Options = struct {
    help: bool = false,
    bind: []const u8 = "127.0.0.1",
    port: u16 = 8080,
    environment: []const u8 = "development",
    log: []const u8 = "-",
    @"log-error": []const u8 = "-",
    @"log-level": jetzig.loggers.LogLevel = .DEBUG,
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
            .environment = "Load an environment configuration from src/app/environments/<environment>.zig",
            .log = "Path to log file. Use '-' for stdout (default: -)",
            .@"log-error" =
            \\Optional path to separate error log file. Use '-' for stdout. If omitted, errors are logged to the location specified by the `log` option.
            ,
            .@"log-level" =
            \\Specify the minimum log level. Log events below the given level are ignored. Must be one of: TRACE, DEBUG, INFO, WARN, ERROR, FATAL (default: DEBUG)
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
pub fn getServerOptions(self: Environment) !jetzig.http.Server.ServerOptions {
    const options = try args.parseForCurrentProcess(Options, self.allocator, .print);

    if (options.options.help) {
        const writer = std.io.getStdErr().writer();
        try args.printHelp(Options, options.executable_name orelse "<app-name>", writer);
        std.process.exit(0);
    }

    var logger = jetzig.loggers.Logger{
        .development_logger = jetzig.loggers.DevelopmentLogger.init(
            self.allocator,
            try getLogFile(options.options.log),
        ),
    };

    if (options.options.detach and std.mem.eql(u8, options.options.log, "-")) {
        try logger.ERROR("Must pass `--log` when using `--detach`.", .{});
        std.process.exit(1);
    }

    // TODO: Generate nonce per session - do research to confirm correct best practice.
    const secret_len = jetzig.http.Session.Cipher.key_length + jetzig.http.Session.Cipher.nonce_length;
    const secret = try self.getSecret(&logger, secret_len);

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
    };
}

fn getLogFile(path: []const u8) !std.fs.File {
    if (std.mem.eql(u8, path, "-")) return std.io.getStdOut();

    const file = try std.fs.createFileAbsolute(path, .{ .truncate = false });
    try file.seekFromEnd(0);
    return file;
}

fn getSecret(self: Environment, logger: *jetzig.loggers.Logger, comptime len: u10) ![]const u8 {
    return std.process.getEnvVarOwned(self.allocator, "JETZIG_SECRET") catch |err| {
        switch (err) {
            error.EnvironmentVariableNotFound => {
                // TODO: Make this a failure when running in non-development mode.
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
