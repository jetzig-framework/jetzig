const std = @import("std");
const Allocator = std.mem.Allocator;
const ArenaAllocator = std.heap.ArenaAllocator;
const ArrayList = std.ArrayList;
const Writer = std.Io.Writer;

pub const SMTPConfig = @import("mail/SMTPConfig.zig");
pub const MailParams = @import("mail/MailParams.zig");
pub const Address = MailParams.Address;
pub const components = @import("mail/components.zig");
pub const Job = @import("mail/Job.zig");
pub const MailerDefinition = @import("mail/MailerDefinition.zig");

const jetzig = @import("../jetzig.zig");
const JobEnv = jetzig.jobs.JobEnv;
const smtp = @import("smtp");

// renders email to []const u8
pub fn render(allocator: Allocator, params: MailParams) ![]const u8 {
    var arena: ArenaAllocator = .init(allocator);
    defer arena.deinit();
    const alloc = arena.allocator();

    const boundary = params.boundary orelse std.crypto.random.int(u8);

    try validate(params);

    var sections: ArrayList([]const u8) = try .initCapacity(alloc, 0);
    const from: MailParams.Address = params.get(.from) orelse return error.NoSender;
    const subject: []const u8 = params.get(.subject) orelse return error.NoSubject;
    const from_string = try std.fmt.allocPrint(alloc, "From: {f}", .{from});
    const subject_string = try std.fmt.allocPrint(alloc, "Subject: {s}", .{subject});
    try sections.append(alloc, from_string);
    try sections.append(alloc, subject_string);

    if (params.get(.cc)) |cc| {
        for (cc) |recipient| {
            const recipient_string = try std.fmt.allocPrint(alloc, "Cc: {f}", .{recipient});
            try sections.append(alloc, recipient_string);
        }
    }

    const body = try std.mem.concat(
        alloc,
        u8,
        &.{
            try header(alloc, boundary),
            try textPart(alloc, params, boundary),
            if (params.get(.html) != null and params.get(.text) != null) "\r\n" else "",
            try htmlPart(alloc, params, boundary),
            jetzig.mail.components.footer,
        },
    );

    try sections.append(alloc, body);
    const data = try std.mem.join(alloc, "\r\n", sections.items);
    return allocator.dupe(u8, data);
}

// renders and delivers email
pub fn deliver(
    allocator: Allocator,
    env: JobEnv,
    params: MailParams,
    config: SMTPConfig,
) !void {
    var arena: ArenaAllocator = .init(allocator);
    defer arena.deinit();
    const alloc = arena.allocator();
    const data = try render(alloc, params);

    const to = try alloc.alloc(smtp.Message.Address, params.to.?.len);
    defer alloc.free(to);

    for (params.to.?, 0..) |address, index| {
        to[index] = .{ .address = address.email, .name = address.name };
    }

    try smtp.send(.{
        .from = .{ .address = params.from.?.email, .name = params.from.?.name },
        .to = to,
        .data = data,
    }, try config.toSMTP(alloc, env));
}

fn validate(mail_params: MailParams) !void {
    if (mail_params.get(.from) == null) return error.JetzigMailMissingFromAddress;
    if (mail_params.get(.to) == null) return error.JetzigMailMissingFromAddress;
    if (mail_params.get(.subject) == null) return error.JetzigMailMissingSubject;
}

fn header(allocator: Allocator, boundary: u32) ![]const u8 {
    return std.fmt.allocPrint(
        allocator,
        jetzig.mail.components.header,
        .{boundary},
    );
}

fn footer(allocator: Allocator, boundary: u32) ![]const u8 {
    return std.fmt.allocPrint(
        allocator,
        jetzig.mail.components.footer,
        .{boundary},
    );
}

fn textPart(allocator: Allocator, params: MailParams, boundary: u32) ![]const u8 {
    if (params.get(.text)) |content| {
        return std.fmt.allocPrint(
            allocator,
            jetzig.mail.components.text,
            .{ boundary, try encode(allocator, content) },
        );
    } else return "";
}

fn htmlPart(allocator: Allocator, params: MailParams, boundary: u32) ![]const u8 {
    if (params.get(.html)) |content| {
        return std.fmt.allocPrint(
            allocator,
            jetzig.mail.components.html,
            .{ boundary, try encode(allocator, content) },
        );
    } else return "";
}

fn encode(allocator: Allocator, content: []const u8) ![]const u8 {
    var aw: Writer.Allocating = .init(allocator);
    defer aw.deinit();
    var line_len: u8 = 0;
    var writer = &aw.writer;

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

    return aw.toOwnedSlice();
}

fn isEncoded(char: u8) bool {
    return char == '=' or !std.ascii.isPrint(char);
}

test "HTML part only" {
    const actual = try render(std.testing.allocator, .{
        .from = .{ .name = "Bob", .email = "user@example.com" },
        .to = &.{.{ .name = "Alice", .email = "user@example.com" }},
        .subject = "Test subject",
        .html = "<div>Hello</div>",
        .boundary = 123456789,
    });
    defer std.testing.allocator.free(actual);

    const expected = try std.mem.replaceOwned(u8, std.testing.allocator,
        \\From: Bob <user@example.com>
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
    const actual = try render(std.testing.allocator, .{
        .from = .{ .name = "Bob", .email = "user@example.com" },
        .to = &.{.{ .name = "Alice", .email = "user@example.com" }},
        .subject = "Test subject",
        .text = "Hello",
        .boundary = 123456789,
    });
    defer std.testing.allocator.free(actual);

    const expected = try std.mem.replaceOwned(u8, std.testing.allocator,
        \\From: Bob <user@example.com>
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
    const actual = try render(std.testing.allocator, .{
        .from = .{ .name = "Bob", .email = "user@example.com" },
        .to = &.{.{ .name = "Alice", .email = "user@example.com" }},
        .subject = "Test subject",
        .html = "<div>Hello</div>",
        .text = "Hello",
        .boundary = 123456789,
    });
    defer std.testing.allocator.free(actual);

    const expected = try std.mem.replaceOwned(u8, std.testing.allocator,
        \\From: Bob <user@example.com>
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

test "default email address name" {
    const actual = try render(std.testing.allocator, .{
        .from = .{ .email = "user@example.com" },
        .to = &.{.{ .email = "user@example.com" }},
        .subject = "Test subject",
        .text = "Hello",
        .boundary = 123456789,
    });
    defer std.testing.allocator.free(actual);

    const expected = try std.mem.replaceOwned(u8, std.testing.allocator,
        \\From: user@example.com <user@example.com>
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
test "long content encoding" {
    const actual = try render(std.testing.allocator, .{
        .from = .{ .name = "Bob", .email = "user@example.com" },
        .to = &.{.{ .name = "Alice", .email = "user@example.com" }},
        .subject = "Test subject",
        .html = "<html><body><div style=\"background-color: black; color: #ff00ff;\">Hellooooooooooooooooooooooooooooooooooooooooooooooooooooooooooooooooooooooooooooooooooooooooooooooooooooooooooooooooooooooooooooooooooooooooooooooooooooooooooooooooooooooooooooooooooooooooooooooooooooooooooooooooooooooooooooooooooooooooooooooooooooooooooooooooooooooooooooooooooooooooooooooooooooooooooooooooooooooooooooooooooooooooooooooooooooooooooooooooooooooooooooooooooooooooooooooooooooooooooooooooooooooooooooooooooooooooooooooooooooooo!!!</div></body></html>",
        .text = "Hello",
        .boundary = 123456789,
    });
    defer std.testing.allocator.free(actual);

    const expected = try std.mem.replaceOwned(u8, std.testing.allocator,
        \\From: Bob <user@example.com>
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
    const actual = try render(std.testing.allocator, .{
        .from = .{ .name = "Bob", .email = "user@example.com" },
        .to = &.{.{ .name = "Alice", .email = "user@example.com" }},
        .subject = "Test subject",
        .html = "<html><body><div>你爱学习 Zig 吗？</div></body></html>",
        .text = "Hello",
        .boundary = 123456789,
    });
    defer std.testing.allocator.free(actual);

    const expected = try std.mem.replaceOwned(u8, std.testing.allocator,
        \\From: Bob <user@example.com>
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
    var env: JobEnv = undefined;
    var env_map = std.process.EnvMap.init(std.testing.allocator);
    defer env_map.deinit();

    try env_map.put("JETZIG_SMTP_PORT", "999");
    try env_map.put("JETZIG_SMTP_ENCRYPTION", "start_tls");
    try env_map.put("JETZIG_SMTP_HOST", "smtp.example.com");
    try env_map.put("JETZIG_SMTP_USERNAME", "example-username");
    try env_map.put("JETZIG_SMTP_PASSWORD", "example-password");

    env.vars = jetzig.Environment.Vars{ .env_map = env_map, .env_file = null };

    const smtp_config: SMTPConfig = .{};
    const config = try smtp_config.toSMTP(std.testing.allocator, env);
    try std.testing.expect(config.port == 999);
    try std.testing.expect(config.encryption == .start_tls);
    try std.testing.expectEqualStrings("smtp.example.com", config.host);
    try std.testing.expectEqualStrings("example-username", config.username.?);
    try std.testing.expectEqualStrings("example-password", config.password.?);
}
