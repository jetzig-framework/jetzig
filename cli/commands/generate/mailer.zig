const std = @import("std");

/// Run the mailer generator. Create a mailer in `src/app/mailers/`
pub fn run(allocator: std.mem.Allocator, cwd: std.fs.Dir, args: [][]const u8, help: bool) !void {
    if (help or args.len != 1) {
        std.debug.print(
            \\Generate a new Mailer. Mailers provide an interface for sending emails from a Jetzig application.
            \\
            \\Example:
            \\
            \\  jetzig generate mailer iguana
            \\
        , .{});

        if (help) return;

        return error.JetzigCommandError;
    }

    const name = args[0];

    const dir_path = try std.fs.path.join(allocator, &[_][]const u8{ "src", "app", "mailers" });
    defer allocator.free(dir_path);

    var dir = try cwd.makeOpenPath(dir_path, .{});
    defer dir.close();

    const filename = try std.mem.concat(allocator, u8, &[_][]const u8{ name, ".zig" });
    defer allocator.free(filename);

    const mailer_file = dir.createFile(filename, .{ .exclusive = true }) catch |err| {
        switch (err) {
            error.PathAlreadyExists => {
                std.debug.print("Mailer already exists: {s}\n", .{filename});
                return error.JetzigCommandError;
            },
            else => return err,
        }
    };

    try mailer_file.writeAll(
        \\const std = @import("std");
        \\const jetzig = @import("jetzig");
        \\
        \\// Default values for this mailer.
        \\pub const defaults: jetzig.mail.DefaultMailParams = .{
        \\    .from = "no-reply@example.com",
        \\    .subject = "Default subject",
        \\};
        \\
        \\// The `deliver` function is invoked every time this mailer is used to send an email.
        \\// Use this function to modify mail parameters before the mail is delivered, or simply
        \\// to log all uses of this mailer.
        \\//
        \\// To use this mailer from a request:
        \\//   ```
        \\//   const mail = request.mail("<mailer-name>", .{ .to = &.{"user@example.com"} });
        \\//   try mail.deliver(.background, .{});
        \\//   ```
        \\// A mailer can provide two Zmpl templates for rendering email content:
        \\// * `src/app/mailers/<mailer-name>/html.zmpl
        \\// * `src/app/mailers/<mailer-name>/text.zmpl
        \\//
        \\// Arguments:
        \\// * allocator: Arena allocator for use during the mail delivery process.
        \\// * mail:      Mail parameters. Inspect or override any values assigned when the mail was created.
        \\// * params:    Params assigned to a mail (from a request, any values added to `data`). Params
        \\//              can be modified before email delivery.
        \\// * env:       Provides the following fields:
        \\//              - logger:      Logger attached to the same stream as the Jetzig server.
        \\//              - environment: Enum of `{ production, development }`.
        \\pub fn deliver(
        \\    allocator: std.mem.Allocator,
        \\    mail: *jetzig.mail.MailParams,
        \\    params: *jetzig.data.Value,
        \\    env: jetzig.jobs.JobEnv,
        \\) !void {
        \\    _ = allocator;
        \\    _ = params;
        \\
        \\    try env.logger.INFO("Delivering email with subject: '{?s}'", .{mail.get(.subject)});
        \\}
        \\
    );

    mailer_file.close();

    const realpath = try dir.realpathAlloc(allocator, filename);
    defer allocator.free(realpath);

    std.debug.print("Generated mailer: {s}\n", .{realpath});

    const template_dir_path = try std.fs.path.join(allocator, &[_][]const u8{ "src", "app", "mailers", name });
    defer allocator.free(template_dir_path);

    var template_dir = try cwd.makeOpenPath(template_dir_path, .{});
    defer template_dir.close();

    const html_template_file: ?std.fs.File = template_dir.createFile(
        "html.zmpl",
        .{ .exclusive = true },
    ) catch |err| blk: {
        switch (err) {
            error.PathAlreadyExists => {
                std.debug.print("Template already exists: `{s}/html.zmpl` - skipping.\n", .{template_dir_path});
                break :blk null;
            },
            else => return err,
        }
    };

    const text_template_file: ?std.fs.File = template_dir.createFile(
        "text.zmpl",
        .{ .exclusive = true },
    ) catch |err| blk: {
        switch (err) {
            error.PathAlreadyExists => {
                std.debug.print("Template already exists: `{s}/text.zmpl` - skipping.\n", .{template_dir_path});
                break :blk null;
            },
            else => return err,
        }
    };

    if (html_template_file) |file| {
        try file.writeAll(
            \\<div>HTML content goes here</div>
            \\
        );
        file.close();
        const html_template_realpath = try template_dir.realpathAlloc(allocator, "html.zmpl");
        defer allocator.free(html_template_realpath);
        std.debug.print("Generated mailer template: {s}\n", .{html_template_realpath});
    }

    if (text_template_file) |file| {
        try file.writeAll(
            \\Text content goes here
            \\
        );
        file.close();
        const text_template_realpath = try template_dir.realpathAlloc(allocator, "text.zmpl");
        defer allocator.free(text_template_realpath);
        std.debug.print("Generated mailer template: {s}\n", .{text_template_realpath});
    }
}
