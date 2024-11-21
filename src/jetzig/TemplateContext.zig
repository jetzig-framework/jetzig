const std = @import("std");

pub const http = @import("http.zig");
pub const config = @import("config.zig");

/// Context available in every Zmpl template as `context`.
pub const TemplateContext = @This();

request: ?*http.Request = null,

pub fn authenticityToken(self: TemplateContext) !?[]const u8 {
    return if (self.request) |request|
        try request.authenticityToken()
    else
        null;
}

pub fn authenticityFormElement(self: TemplateContext) !?[]const u8 {
    return if (self.request) |request| blk: {
        const token = try request.authenticityToken();
        break :blk try std.fmt.allocPrint(request.allocator,
            \\<input type="hidden" name="{s}" value="{s}" />
        , .{ config.get([]const u8, "authenticity_token_name"), token });
    } else null;
}
