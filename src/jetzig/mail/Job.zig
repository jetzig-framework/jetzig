const std = @import("std");
const Allocator = std.mem.Allocator;
const ArrayList = std.ArrayList;

const jetzig = @import("../../jetzig.zig");
const JobEnv = jetzig.jobs.JobEnv;
const Value = jetzig.data.Value;
const MailParams = jetzig.mail.MailParams;
const Address = MailParams.Address;
const MailerDefinition = jetzig.mail.MailerDefinition;

/// Default Mail Job. Send an email with the given params in the background.
pub fn run(allocator: Allocator, params: *Value, env: JobEnv) !void {
    const mailer_name = if (params.get("mailer_name")) |param| switch (param.*) {
        .null => null,
        .string => |string| string.value,
        else => null,
    } else null;

    if (mailer_name == null) {
        try env.logger.ERROR("Missing mailer name parameter", .{});
        return error.JetzigMissingMailerName;
    }

    const mailer = findMailer(mailer_name.?, env) orelse {
        try env.logger.ERROR("Unknown mailer: `{s}`", .{mailer_name.?});
        return error.JetzigUnknownMailerName;
    };

    const subject = params.get("subject");
    const from = params.get("from");

    const html = params.get("html");
    const text = params.get("text");

    const to = try resolveTo(allocator, params);

    var mail_params: MailParams = .{
        .subject = resolveSubject(subject),
        .from = resolveFrom(from),
        .to = to,
    };

    try mailer.deliverFn(allocator, &mail_params, params.get("params").?, env);

    const test_mail: MailParams = .{
        .subject = mail_params.get(.subject) orelse "(No subject)",
        .from = mail_params.get(.from) orelse return error.JetzigMailerMissingFromAddress,
        .to = mail_params.get(.to) orelse return error.JetzigMailerMissingToAddress,
        .html = mail_params.get(.html) orelse try resolveHtml(allocator, mailer, html, params),
        .text = mail_params.get(.text) orelse try resolveText(allocator, mailer, text, params),
    };

    if (env.environment == .development and !jetzig.config.get(bool, "force_development_email_delivery")) {
        try env.logger.INFO(
            \\Skipping mail delivery in development environment:
            \\To: {?s}
            \\{s}
        ,
            .{ test_mail.get(.to), try jetzig.mail.render(allocator, test_mail) },
        );
    } else {
        try jetzig.mail.deliver(allocator, env, .{
            .subject = mail_params.get(.subject) orelse "(No subject)",
            .from = mail_params.get(.from) orelse return error.JetzigMailerMissingFromAddress,
            .to = mail_params.get(.to) orelse return error.JetzigMailerMissingToAddress,
            .html = mail_params.get(.html) orelse try resolveHtml(allocator, mailer, html, params),
            .text = mail_params.get(.text) orelse try resolveText(allocator, mailer, text, params),
        }, .{});
        try env.logger.INFO("Delivered mail to: {f}", .{test_mail.to.?});
    }
}

fn resolveSubject(subject: ?*const Value) ?[]const u8 {
    if (subject) |capture| {
        return switch (capture.*) {
            .null => null,
            .string => |string| string.value,
            else => unreachable,
        };
    } else return null;
}

fn resolveFrom(from: ?*const Value) ?Address {
    return if (from) |capture| switch (capture.*) {
        .null => null,
        .string => |string| .{ .email = string.value },
        .object => |object| .{
            .email = object.getT(.string, "email") orelse return null,
            .name = object.getT(.string, "name") orelse return null,
        },
        else => unreachable,
    } else null;
}

fn resolveTo(allocator: Allocator, params: *const Value) !?[]const Address {
    var to: ArrayList(Address) = try .initCapacity(allocator, 0);
    defer to.deinit(allocator);
    if (params.get("to")) |capture| {
        for (capture.items(.array)) |recipient| {
            const maybe_address: ?Address = switch (recipient.*) {
                .null => null,
                .string => |string| .{ .email = string.value },
                .object => |object| .{
                    .email = object.getT(.string, "email") orelse return error.JetzigMissingEmailField,
                    .name = object.getT(.string, "name"),
                },
                else => unreachable,
            };
            if (maybe_address) |address| try to.append(allocator, address);
        }
    }
    return if (to.items.len > 0) try to.toOwnedSlice(allocator) else null;
}

fn resolveText(
    allocator: Allocator,
    mailer: MailerDefinition,
    text: ?*const Value,
    params: *Value,
) !?[]const u8 {
    if (text) |capture| {
        return switch (capture.*) {
            .null => try defaultText(allocator, mailer, params),
            .string => |string| string.value,
            else => unreachable,
        };
    } else {
        return try defaultText(allocator, mailer, params);
    }
}

fn resolveHtml(
    allocator: Allocator,
    mailer: MailerDefinition,
    text: ?*const Value,
    params: *Value,
) !?[]const u8 {
    if (text) |capture| {
        return switch (capture.*) {
            .null => try defaultHtml(allocator, mailer, params),
            .string => |string| string.value,
            else => unreachable,
        };
    } else {
        return try defaultHtml(allocator, mailer, params);
    }
}

fn defaultHtml(
    allocator: Allocator,
    mailer: MailerDefinition,
    params: *Value,
) !?[]const u8 {
    var data = jetzig.data.Data.init(allocator);
    data.value = if (params.get("params")) |capture|
        capture
    else
        try jetzig.zmpl.Data.createObject(data.allocator);
    try data.addConst("jetzig_view", data.string(""));
    try data.addConst("jetzig_action", data.string(""));
    return if (jetzig.zmpl.findPrefixed("mailers", mailer.html_template)) |template|
        try template.render(&data, jetzig.TemplateContext, .{}, &.{}, .{})
    else
        null;
}

fn defaultText(
    allocator: Allocator,
    mailer: MailerDefinition,
    params: *Value,
) !?[]const u8 {
    var data = jetzig.data.Data.init(allocator);
    data.value = if (params.get("params")) |capture|
        capture
    else
        try jetzig.zmpl.Data.createObject(data.allocator);
    try data.addConst("jetzig_view", data.string(""));
    try data.addConst("jetzig_action", data.string(""));
    return if (jetzig.zmpl.findPrefixed("mailers", mailer.text_template)) |template|
        try template.render(&data, jetzig.TemplateContext, .{}, &.{}, .{})
    else
        null;
}

fn findMailer(name: []const u8, env: JobEnv) ?MailerDefinition {
    for (env.mailers) |mailer| {
        if (std.mem.eql(u8, mailer.name, name)) return mailer;
    }
    return null;
}
