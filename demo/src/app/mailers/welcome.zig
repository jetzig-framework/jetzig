const std = @import("std");
const jetzig = @import("jetzig");

// Default values for this mailer.
pub const defaults: jetzig.mail.DefaultMailParams = .{
    .from = "no-reply@example.com",
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
// * mail:      Mail parameters. Inspect or override any values assigned when the mail was created.
// * params:    Params assigned to a mail (from a request, any values added to `data`). Params
//              can be modified before email delivery.
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
    _ = params;

    try env.logger.INFO("Delivering email with subject: '{?s}'", .{mail.get(.subject)});
}
