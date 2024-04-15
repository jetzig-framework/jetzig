const std = @import("std");

const smtp = @import("smtp");

port: u16 = 25,
encryption: enum { none, insecure, tls, start_tls } = .none,
host: []const u8 = "localhost",
username: ?[]const u8 = null,
password: ?[]const u8 = null,

const SMTPConfig = @This();

pub fn toSMTP(self: SMTPConfig, allocator: std.mem.Allocator) smtp.Config {
    return smtp.Config{
        .allocator = allocator,
        .port = self.port,
        .encryption = self.getEncryption(),
        .host = self.host,
        .username = self.username,
        .password = self.password,
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
