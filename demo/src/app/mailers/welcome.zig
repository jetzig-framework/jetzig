const std = @import("std");
const jetzig = @import("jetzig");

// Default values for this mailer.
pub const defaults: jetzig.mail.DefaultMailParams = .{
    .from = .{ .email = "no-reply@example.com" },
    .subject = "Default subject",
};

// The `deliver` function is invoked every time this mailer is used to send an email.
// Use this function to set default mail params (e.g. a default `from` address or
// `subject`) before the mail is delivered.
//
// A mailer can provide two Zmpl templates for rendering email content:
// * `src/app/mailers/<mailer-name>/html.zmpl
// * `src/app/mailers/<mailer-name>/text.zmpl
//
// Arguments:
// * allocator: Arena allocator for use during the mail delivery process.
// * mail:      Mail parameters (from, to, subject, etc.). Inspect or override any values
//              assigned when the mail was created.
// * data:      Provides `data.string()` etc. for generating Jetzig Values.
// * params:    Template data for `text.zmpl` and `html.zmpl`. Inherits all response data
//              assigned in a view function and can be modified for email-specific content.
// * env:       Provides the following fields:
//              - logger:      Logger attached to the same stream as the Jetzig server.
//              - environment: Enum of `{ production, development }`.
pub fn deliver(
    allocator: std.mem.Allocator,
    mail: *jetzig.mail.MailParams,
    params: *jetzig.data.Value,
    env: jetzig.jobs.JobEnv,
) !void {
    _ = allocator;
    try params.put("email_message", "Custom email message");

    try env.logger.INFO("Delivering email with subject: '{?s}'", .{mail.get(.subject)});
}
