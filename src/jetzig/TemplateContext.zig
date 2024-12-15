const std = @import("std");

pub const http = @import("http.zig");
pub const views = @import("views.zig");
pub const config = @import("config.zig");

/// Context available in every Zmpl template as `context`.
pub const TemplateContext = @This();

request: ?*http.Request = null,
route: ?views.Route = null,

/// Return an authenticity token stored in the current request's session. If no token exists,
/// generate and store before returning.
/// Use to create a form element which can be verified by `AntiCsrfMiddleware`.
pub fn authenticityToken(self: TemplateContext) !?[]const u8 {
    return if (self.request) |request|
        try request.authenticityToken()
    else
        null;
}

/// Generate a hidden form element containing an authenticity token provided by
/// `authenticityToken`. Use as `{{context.authenticityFormElement()}}` in a Zmpl template.
pub fn authenticityFormElement(self: TemplateContext) !?[]const u8 {
    return if (self.request) |request| blk: {
        const token = try request.authenticityToken();
        break :blk try std.fmt.allocPrint(request.allocator,
            \\<input type="hidden" name="{s}" value="{s}" />
        , .{ config.get([]const u8, "authenticity_token_name"), token });
    } else null;
}

pub fn path(self: TemplateContext) ?[]const u8 {
    return if (self.request) |request|
        request.path.path
    else
        null;
}
