subject: ?[]const u8 = null,
from: ?Address = null,
to: ?[]const Address = null,
cc: ?[]const Address = null,
bcc: ?[]const Address = null, // TODO
html: ?[]const u8 = null,
text: ?[]const u8 = null,
defaults: ?DefaultMailParams = null,

pub const DefaultMailParams = struct {
    subject: ?[]const u8 = null,
    from: ?Address = null,
    to: ?[]const Address = null,
    cc: ?[]const Address = null,
    bcc: ?[]const Address = null, // TODO
    html: ?[]const u8 = null,
    text: ?[]const u8 = null,
};

pub const Address = struct {
    name: ?[]const u8 = null,
    email: []const u8,

    pub fn format(address: Address, _: anytype, _: anytype, writer: anytype) !void {
        try writer.print("<{?s}> {s}", .{ address.name, address.email });
    }
};

const MailParams = @This();

pub fn get(
    self: MailParams,
    comptime field: enum { subject, from, to, cc, bcc, html, text },
) ?switch (field) {
    .subject => []const u8,
    .from => Address,
    .to => []const Address,
    .cc => []const Address,
    .bcc => []const Address,
    .html => []const u8,
    .text => []const u8,
} {
    return @field(self, @tagName(field)) orelse if (self.defaults) |defaults|
        @field(defaults, @tagName(field))
    else
        null;
}
