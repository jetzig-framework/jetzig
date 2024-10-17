const std = @import("std");

const smtp = @import("smtp");

const jetzig = @import("../../jetzig.zig");

port: u16 = 25,
encryption: enum { none, insecure, tls, start_tls } = .none,
host: []const u8 = "localhost",
username: ?[]const u8 = null,
password: ?[]const u8 = null,

const SMTPConfig = @This();

pub fn toSMTP(
    self: SMTPConfig,
    allocator: std.mem.Allocator,
    env: jetzig.jobs.JobEnv,
) !smtp.Config {
    return smtp.Config{
        .allocator = allocator,
        .port = try env.vars.getT(u16, "JETZIG_SMTP_PORT") orelse self.port,
        .encryption = try env.vars.getT(smtp.Encryption, "JETZIG_SMTP_ENCRYPTION") orelse
            self.getEncryption(),
        .host = env.vars.get("JETZIG_SMTP_HOST") orelse self.host,
        .username = env.vars.get("JETZIG_SMTP_USERNAME") orelse self.username,
        .password = env.vars.get("JETZIG_SMTP_PASSWORD") orelse self.password,
    };
}

fn getEncryption(self: SMTPConfig) smtp.Encryption {
    return switch (self.encryption) {
        .none => smtp.Encryption.none,
        .insecure => smtp.Encryption.insecure,
        .tls => smtp.Encryption.tls,
        .start_tls => smtp.Encryption.start_tls,
    };
}
