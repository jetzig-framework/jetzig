const std = @import("std");
const jetzig = @import("jetzig");

pub fn index(request: *jetzig.Request) !jetzig.View {
    var root = try request.data(.object);
    try root.put("message", "Welcome to Jetzig!");

    // Create a new mail using `src/app/mailers/welcome.zig`.
    // HTML and text parts are rendered using Zmpl templates:
    // * `src/app/mailers/welcome/html.zmpl`
    // * `src/app/mailers/welcome/text.zmpl`
    // All mailer templates have access to the same template data as a view template.
    const mail = request.mail("welcome", .{ .to = &.{.{ .email = "hello@jetzig.dev" }} });

    // Deliver the email asynchronously via a built-in mail Job. Use `.now` to send the email
    // synchronously (i.e. before the request has returned).
    try mail.deliver(.background, .{});

    return request.render(.ok);
}
