const std = @import("std");

const jetzig = @import("../../jetzig.zig");

const smtp = @import("smtp");

allocator: std.mem.Allocator,
config: jetzig.mail.SMTPConfig,
params: jetzig.mail.MailParams,
boundary: u32,
env: jetzig.jobs.JobEnv,

const Mail = @This();

pub fn init(
    allocator: std.mem.Allocator,
    env: jetzig.jobs.JobEnv,
    params: jetzig.mail.MailParams,
) Mail {
    return .{
        .allocator = allocator,
        .config = jetzig.config.get(jetzig.mail.SMTPConfig, "smtp"),
        .env = env,
        .params = params,
        .boundary = std.crypto.random.int(u32),
    };
}

pub fn deliver(self: Mail) !void {
    const data = try self.generateData();
    defer self.allocator.free(data);

    const to = try self.allocator.alloc(smtp.Message.Address, self.params.to.?.len);
    defer self.allocator.free(to);

    for (self.params.to.?, 0..) |address, index| {
        to[index] = .{ .address = address.email, .name = address.name };
    }

    try smtp.send(.{
        .from = .{ .address = self.params.from.?.email, .name = self.params.from.?.name },
        .to = to,
        .data = data,
    }, try self.config.toSMTP(self.allocator, self.env));
}

pub fn generateData(self: Mail) ![]const u8 {
    try self.validate();

    var arena = std.heap.ArenaAllocator.init(self.allocator);
    defer arena.deinit();

    const allocator = arena.allocator();

    var sections = std.ArrayList([]const u8).init(allocator);
    try sections.append(try std.fmt.allocPrint(allocator, "From: {s}", .{self.params.get(.from).?}));
    try sections.append(try std.fmt.allocPrint(allocator, "Subject: {s}", .{self.params.get(.subject).?}));

    if (self.params.get(.cc)) |cc| {
        for (cc) |recipient| {
            try sections.append(try std.fmt.allocPrint(allocator, "Cc: {s}", .{recipient}));
        }
    }

    const body = try std.mem.concat(allocator, u8, &.{
        try self.header(allocator),
        try self.textPart(allocator),
        if (self.params.get(.html) != null and self.params.get(.text) != null) "\r\n" else "",
        try self.htmlPart(allocator),
        jetzig.mail.components.footer,
    });

    try sections.append(body);

    return std.mem.join(self.allocator, "\r\n", sections.items);
}

fn validate(self: Mail) !void {
    if (self.params.get(.from) == null) return error.JetzigMailMissingFromAddress;
    if (self.params.get(.to) == null) return error.JetzigMailMissingFromAddress;
    if (self.params.get(.subject) == null) return error.JetzigMailMissingSubject;
}

fn header(self: Mail, allocator: std.mem.Allocator) ![]const u8 {
    return try std.fmt.allocPrint(
        allocator,
        jetzig.mail.components.header,
        .{self.boundary},
    );
}

fn footer(self: Mail, allocator: std.mem.Allocator) ![]const u8 {
    return try std.fmt.allocPrint(
        allocator,
        jetzig.mail.components.footer,
        .{self.boundary},
    );
}

fn textPart(self: Mail, allocator: std.mem.Allocator) ![]const u8 {
    if (self.params.get(.text)) |content| {
        return try std.fmt.allocPrint(
            allocator,
            jetzig.mail.components.text,
            .{ self.boundary, try encode(allocator, content) },
        );
    } else return "";
}

fn htmlPart(self: Mail, allocator: std.mem.Allocator) ![]const u8 {
    if (self.params.get(.html)) |content| {
        return try std.fmt.allocPrint(
            allocator,
            jetzig.mail.components.html,
            .{ self.boundary, try encode(allocator, content) },
        );
    } else return "";
}

fn encode(allocator: std.mem.Allocator, content: []const u8) ![]const u8 {
    var buf = std.ArrayList(u8).init(allocator);
    const writer = buf.writer();
    var line_len: u8 = 0;

    for (content) |char| {
        const encoded = isEncoded(char);
        const encoded_len: u2 = if (encoded) 3 else 1;

        if (encoded_len + line_len >= 76) {
            try writer.writeAll("=\r\n");
            line_len = encoded_len;
        } else {
            line_len += encoded_len;
        }

        if (encoded) {
            try writer.print("={X:0>2}", .{char});
        } else {
            try writer.writeByte(char);
        }
    }

    return buf.toOwnedSlice();
}

inline fn isEncoded(char: u8) bool {
    return char == '=' or !std.ascii.isPrint(char);
}

test "HTML part only" {
    const mail = Mail{
        .allocator = std.testing.allocator,
        .env = undefined,
        .config = .{},
        .boundary = 123456789,
        .params = .{
            .from = .{ .name = "Bob", .email = "user@example.com" },
            .to = &.{.{ .name = "Alice", .email = "user@example.com" }},
            .subject = "Test subject",
            .html = "<div>Hello</div>",
        },
    };

    const actual = try generateData(mail);
    defer std.testing.allocator.free(actual);

    const expected = try std.mem.replaceOwned(u8, std.testing.allocator,
        \\From: <Bob> user@example.com
        \\Subject: Test subject
        \\MIME-Version: 1.0
        \\Content-Type: multipart/alternative; boundary="=_alternative_123456789"
        \\--=_alternative_123456789
        \\Content-Type: text/html; charset="UTF-8"
        \\Content-Transfer-Encoding: quoted-printable
        \\
        \\<div>Hello</div>
        \\
        \\.
        \\
    , "\n", "\r\n");
    defer std.testing.allocator.free(expected);

    try std.testing.expectEqualStrings(expected, actual);
}

test "text part only" {
    const mail = Mail{
        .allocator = std.testing.allocator,
        .env = undefined,
        .config = .{},
        .boundary = 123456789,
        .params = .{
            .from = .{ .name = "Bob", .email = "user@example.com" },
            .to = &.{.{ .name = "Alice", .email = "user@example.com" }},
            .subject = "Test subject",
            .text = "Hello",
        },
    };

    const actual = try generateData(mail);
    defer std.testing.allocator.free(actual);

    const expected = try std.mem.replaceOwned(u8, std.testing.allocator,
        \\From: <Bob> user@example.com
        \\Subject: Test subject
        \\MIME-Version: 1.0
        \\Content-Type: multipart/alternative; boundary="=_alternative_123456789"
        \\--=_alternative_123456789
        \\Content-Type: text/plain; charset="UTF-8"
        \\Content-Transfer-Encoding: quoted-printable
        \\
        \\Hello
        \\
        \\.
        \\
    , "\n", "\r\n");
    defer std.testing.allocator.free(expected);

    try std.testing.expectEqualStrings(expected, actual);
}

test "HTML and text parts" {
    const mail = Mail{
        .allocator = std.testing.allocator,
        .env = undefined,
        .config = .{},
        .boundary = 123456789,
        .params = .{
            .from = .{ .name = "Bob", .email = "user@example.com" },
            .to = &.{.{ .name = "Alice", .email = "user@example.com" }},
            .subject = "Test subject",
            .html = "<div>Hello</div>",
            .text = "Hello",
        },
    };

    const actual = try generateData(mail);
    defer std.testing.allocator.free(actual);

    const expected = try std.mem.replaceOwned(u8, std.testing.allocator,
        \\From: <Bob> user@example.com
        \\Subject: Test subject
        \\MIME-Version: 1.0
        \\Content-Type: multipart/alternative; boundary="=_alternative_123456789"
        \\--=_alternative_123456789
        \\Content-Type: text/plain; charset="UTF-8"
        \\Content-Transfer-Encoding: quoted-printable
        \\
        \\Hello
        \\
        \\--=_alternative_123456789
        \\Content-Type: text/html; charset="UTF-8"
        \\Content-Transfer-Encoding: quoted-printable
        \\
        \\<div>Hello</div>
        \\
        \\.
        \\
    , "\n", "\r\n");
    defer std.testing.allocator.free(expected);

    try std.testing.expectEqualStrings(expected, actual);
}

test "long content encoding" {
    const mail = Mail{
        .allocator = std.testing.allocator,
        .env = undefined,
        .config = .{},
        .boundary = 123456789,
        .params = .{
            .from = .{ .name = "Bob", .email = "user@example.com" },
            .to = &.{.{ .name = "Alice", .email = "user@example.com" }},
            .subject = "Test subject",
            .html = "<html><body><div style=\"background-color: black; color: #ff00ff;\">Hellooooooooooooooooooooooooooooooooooooooooooooooooooooooooooooooooooooooooooooooooooooooooooooooooooooooooooooooooooooooooooooooooooooooooooooooooooooooooooooooooooooooooooooooooooooooooooooooooooooooooooooooooooooooooooooooooooooooooooooooooooooooooooooooooooooooooooooooooooooooooooooooooooooooooooooooooooooooooooooooooooooooooooooooooooooooooooooooooooooooooooooooooooooooooooooooooooooooooooooooooooooooooooooooooooooooooooooooooooooooo!!!</div></body></html>",
            .text = "Hello",
        },
    };

    const actual = try generateData(mail);
    defer std.testing.allocator.free(actual);

    const expected = try std.mem.replaceOwned(u8, std.testing.allocator,
        \\From: <Bob> user@example.com
        \\Subject: Test subject
        \\MIME-Version: 1.0
        \\Content-Type: multipart/alternative; boundary="=_alternative_123456789"
        \\--=_alternative_123456789
        \\Content-Type: text/plain; charset="UTF-8"
        \\Content-Transfer-Encoding: quoted-printable
        \\
        \\Hello
        \\
        \\--=_alternative_123456789
        \\Content-Type: text/html; charset="UTF-8"
        \\Content-Transfer-Encoding: quoted-printable
        \\
        \\<html><body><div style=3D"background-color: black; color: #ff00ff;">Hellooo=
        \\ooooooooooooooooooooooooooooooooooooooooooooooooooooooooooooooooooooooooooo=
        \\ooooooooooooooooooooooooooooooooooooooooooooooooooooooooooooooooooooooooooo=
        \\ooooooooooooooooooooooooooooooooooooooooooooooooooooooooooooooooooooooooooo=
        \\ooooooooooooooooooooooooooooooooooooooooooooooooooooooooooooooooooooooooooo=
        \\ooooooooooooooooooooooooooooooooooooooooooooooooooooooooooooooooooooooooooo=
        \\ooooooooooooooooooooooooooooooooooooooooooooooooooooooooooooo!!!</div></bod=
        \\y></html>
        \\
        \\.
        \\
    , "\n", "\r\n");
    defer std.testing.allocator.free(expected);

    try std.testing.expectEqualStrings(expected, actual);
}

test "non-latin alphabet encoding" {
    const mail = Mail{
        .allocator = std.testing.allocator,
        .env = undefined,
        .config = .{},
        .boundary = 123456789,
        .params = .{
            .from = .{ .name = "Bob", .email = "user@example.com" },
            .to = &.{.{ .name = "Alice", .email = "user@example.com" }},
            .subject = "Test subject",
            .html = "<html><body><div>你爱学习 Zig 吗？</div></body></html>",

            .text = "Hello",
        },
    };

    const actual = try generateData(mail);
    defer std.testing.allocator.free(actual);

    const expected = try std.mem.replaceOwned(u8, std.testing.allocator,
        \\From: <Bob> user@example.com
        \\Subject: Test subject
        \\MIME-Version: 1.0
        \\Content-Type: multipart/alternative; boundary="=_alternative_123456789"
        \\--=_alternative_123456789
        \\Content-Type: text/plain; charset="UTF-8"
        \\Content-Transfer-Encoding: quoted-printable
        \\
        \\Hello
        \\
        \\--=_alternative_123456789
        \\Content-Type: text/html; charset="UTF-8"
        \\Content-Transfer-Encoding: quoted-printable
        \\
        \\<html><body><div>=E4=BD=A0=E7=88=B1=E5=AD=A6=E4=B9=A0 Zig =E5=90=97=EF=BC=
        \\=9F</div></body></html>
        \\
        \\.
        \\
    , "\n", "\r\n");
    defer std.testing.allocator.free(expected);

    try std.testing.expectEqualStrings(expected, actual);
}

test "environment SMTP config" {
    var env: jetzig.jobs.JobEnv = undefined;
    var env_map = std.process.EnvMap.init(std.testing.allocator);
    defer env_map.deinit();

    try env_map.put("JETZIG_SMTP_PORT", "999");
    try env_map.put("JETZIG_SMTP_ENCRYPTION", "start_tls");
    try env_map.put("JETZIG_SMTP_HOST", "smtp.example.com");
    try env_map.put("JETZIG_SMTP_USERNAME", "example-username");
    try env_map.put("JETZIG_SMTP_PASSWORD", "example-password");

    env.vars = jetzig.Environment.Vars{ .env_map = env_map, .env_file = null };

    const mail = Mail{
        .allocator = undefined,
        .env = undefined,
        .config = .{},
        .boundary = undefined,
        .params = undefined,
    };

    const config = try mail.config.toSMTP(std.testing.allocator, env);
    try std.testing.expect(config.port == 999);
    try std.testing.expect(config.encryption == .start_tls);
    try std.testing.expectEqualStrings("smtp.example.com", config.host);
    try std.testing.expectEqualStrings("example-username", config.username.?);
    try std.testing.expectEqualStrings("example-password", config.password.?);
}
