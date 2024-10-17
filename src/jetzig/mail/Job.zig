const std = @import("std");
const jetzig = @import("../../jetzig.zig");

/// Default Mail Job. Send an email with the given params in the background.
pub fn run(allocator: std.mem.Allocator, params: *jetzig.data.Value, env: jetzig.jobs.JobEnv) !void {
    const mailer_name = if (params.get("mailer_name")) |param| switch (param.*) {
        .Null => null,
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

    var data = jetzig.data.Data.init(allocator);

    try mailer.deliverFn(allocator, &mail_params, &data, params.get("params").?, env);

    const mail = jetzig.mail.Mail.init(allocator, env, .{
        .subject = mail_params.get(.subject) orelse "(No subject)",
        .from = mail_params.get(.from) orelse return error.JetzigMailerMissingFromAddress,
        .to = mail_params.get(.to) orelse return error.JetzigMailerMissingToAddress,
        .html = mail_params.get(.html) orelse try resolveHtml(allocator, mailer, html, params),
        .text = mail_params.get(.text) orelse try resolveText(allocator, mailer, text, params),
    });

    if (env.environment == .development and !jetzig.config.get(bool, "force_development_email_delivery")) {
        try env.logger.INFO(
            "Skipping mail delivery in development environment:\n{s}",
            .{try mail.generateData()},
        );
    } else {
        try mail.deliver();
        try env.logger.INFO("Delivered mail to: {s}", .{
            try std.mem.join(allocator, ", ", mail.params.to.?),
        });
    }
}

fn resolveSubject(subject: ?*const jetzig.data.Value) ?[]const u8 {
    if (subject) |capture| {
        return switch (capture.*) {
            .Null => null,
            .string => |string| string.value,
            else => unreachable,
        };
    } else {
        return null;
    }
}

fn resolveFrom(from: ?*const jetzig.data.Value) ?[]const u8 {
    return if (from) |capture| switch (capture.*) {
        .Null => null,
        .string => |string| string.value,
        else => unreachable,
    } else null;
}

fn resolveTo(allocator: std.mem.Allocator, params: *const jetzig.data.Value) !?[]const []const u8 {
    var to = std.ArrayList([]const u8).init(allocator);
    if (params.get("to")) |capture| {
        for (capture.items(.array)) |recipient| {
            try to.append(recipient.string.value);
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
            .Null => try defaultText(allocator, mailer, params),
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
            .Null => try defaultHtml(allocator, mailer, params),
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
    data.value = if (params.get("params")) |capture| capture else try data.createObject();
    try data.addConst("jetzig_view", data.string(""));
    try data.addConst("jetzig_action", data.string(""));
    return if (jetzig.zmpl.findPrefixed("mailers", mailer.html_template)) |template|
        try template.render(&data)
    else
        null;
}

fn defaultText(
    allocator: std.mem.Allocator,
    mailer: jetzig.mail.MailerDefinition,
    params: *jetzig.data.Value,
) !?[]const u8 {
    var data = jetzig.data.Data.init(allocator);
    data.value = if (params.get("params")) |capture| capture else try data.createObject();
    try data.addConst("jetzig_view", data.string(""));
    try data.addConst("jetzig_action", data.string(""));
    return if (jetzig.zmpl.findPrefixed("mailers", mailer.text_template)) |template|
        try template.render(&data)
    else
        null;
}

fn findMailer(name: []const u8, env: jetzig.jobs.JobEnv) ?jetzig.mail.MailerDefinition {
    for (env.mailers) |mailer| {
        if (std.mem.eql(u8, mailer.name, name)) return mailer;
    }
    return null;
}
