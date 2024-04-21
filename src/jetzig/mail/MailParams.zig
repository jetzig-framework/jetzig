subject: ?[]const u8 = null,
from: ?[]const u8 = null,
to: ?[]const []const u8 = null,
cc: ?[]const []const u8 = null,
bcc: ?[]const []const u8 = null, // TODO
html: ?[]const u8 = null,
text: ?[]const u8 = null,
defaults: ?DefaultMailParams = null,

pub const DefaultMailParams = struct {
    subject: ?[]const u8 = null,
    from: ?[]const u8 = null,
    to: ?[]const []const u8 = null,
    cc: ?[]const []const u8 = null,
    bcc: ?[]const []const u8 = null, // TODO
    html: ?[]const u8 = null,
    text: ?[]const u8 = null,
};

const MailParams = @This();

pub fn get(
    self: MailParams,
    comptime field: enum { subject, from, to, cc, bcc, html, text },
) ?switch (field) {
    .subject => []const u8,
    .from => []const u8,
    .to => []const []const u8,
    .cc => []const []const u8,
    .bcc => []const []const u8,
    .html => []const u8,
    .text => []const u8,
} {
    return @field(self, @tagName(field)) orelse if (self.defaults) |defaults|
        @field(defaults, @tagName(field))
    else
        null;
}
