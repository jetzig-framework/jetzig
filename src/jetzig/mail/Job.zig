const std = @import("std");
const jetzig = @import("../../jetzig.zig");

/// Default Mail Job. Send an email with the given params in the background.
pub fn run(allocator: std.mem.Allocator, params: *jetzig.data.Value, env: jetzig.jobs.JobEnv) !void {
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

    var mail_params = jetzig.mail.MailParams{
        .subject = resolveSubject(subject),
        .from = resolveFrom(from),
        .to = to,
        .defaults = mailer.defaults,
    };

    try mailer.deliverFn(allocator, &mail_params, params.get("params").?, env);

    const mail = jetzig.mail.Mail.init(allocator, env, .{
        .subject = mail_params.get(.subject) orelse "(No subject)",
        .from = mail_params.get(.from) orelse return error.JetzigMailerMissingFromAddress,
        .to = mail_params.get(.to) orelse return error.JetzigMailerMissingToAddress,
        .html = mail_params.get(.html) orelse try resolveHtml(allocator, mailer, html, params),
        .text = mail_params.get(.text) orelse try resolveText(allocator, mailer, text, params),
    });

    if (env.environment == .development and !jetzig.config.get(bool, "force_development_email_delivery")) {
        try env.logger.INFO(
            \\Skipping mail delivery in development environment:
            \\To: {?s}
            \\{s}
        ,
            .{ mail.params.get(.to), try mail.generateData() },
        );
    } else {
        try mail.deliver();
        try env.logger.INFO("Delivered mail to: {s}", .{mail.params.to.?});
    }
}

fn resolveSubject(subject: ?*const jetzig.data.Value) ?[]const u8 {
    if (subject) |capture| {
        return switch (capture.*) {
            .null => null,
            .string => |string| string.value,
            else => unreachable,
        };
    } else {
        return null;
    }
}

fn resolveFrom(from: ?*const jetzig.data.Value) ?jetzig.mail.Address {
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

fn resolveTo(allocator: std.mem.Allocator, params: *const jetzig.data.Value) !?[]const jetzig.mail.Address {
    var to = std.ArrayList(jetzig.mail.Address).init(allocator);
    if (params.get("to")) |capture| {
        for (capture.items(.array)) |recipient| {
            const maybe_address: ?jetzig.mail.Address = switch (recipient.*) {
                .null => null,
                .string => |string| .{ .email = string.value },
                .object => |object| .{
                    .email = object.getT(.string, "email") orelse return error.JetzigMissingEmailField,
                    .name = object.getT(.string, "name"),
                },
                else => unreachable,
            };
            if (maybe_address) |address| try to.append(address);
        }
    }
    return if (to.items.len > 0) try to.toOwnedSlice() else null;
}

fn resolveText(
    allocator: std.mem.Allocator,
    mailer: jetzig.mail.MailerDefinition,
    text: ?*const jetzig.data.Value,
    params: *jetzig.data.Value,
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
    allocator: std.mem.Allocator,
    mailer: jetzig.mail.MailerDefinition,
    text: ?*const jetzig.data.Value,
    params: *jetzig.data.Value,
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
    allocator: std.mem.Allocator,
    mailer: jetzig.mail.MailerDefinition,
    params: *jetzig.data.Value,
) !?[]const u8 {
    var data = jetzig.data.Data.init(allocator);
    data.value = if (params.get("params")) |capture|
        capture
    else
        try jetzig.zmpl.Data.createObject(data.allocator);
    try data.addConst("jetzig_view", data.string(""));
    try data.addConst("jetzig_action", data.string(""));
    return if (jetzig.zmpl.findPrefixed("mailers", mailer.html_template)) |template|
        try template.render(&data, jetzig.TemplateContext, .{}, .{})
    else
        null;
}

fn defaultText(
    allocator: std.mem.Allocator,
    mailer: jetzig.mail.MailerDefinition,
    params: *jetzig.data.Value,
) !?[]const u8 {
    var data = jetzig.data.Data.init(allocator);
    data.value = if (params.get("params")) |capture|
        capture
    else
        try jetzig.zmpl.Data.createObject(data.allocator);
    try data.addConst("jetzig_view", data.string(""));
    try data.addConst("jetzig_action", data.string(""));
    return if (jetzig.zmpl.findPrefixed("mailers", mailer.text_template)) |template|
        try template.render(&data, jetzig.TemplateContext, .{}, .{})
    else
        null;
}

fn findMailer(name: []const u8, env: jetzig.jobs.JobEnv) ?jetzig.mail.MailerDefinition {
    for (env.mailers) |mailer| {
        if (std.mem.eql(u8, mailer.name, name)) return mailer;
    }
    return null;
}
