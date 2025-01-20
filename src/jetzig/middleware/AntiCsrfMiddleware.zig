const std = @import("std");
const jetzig = @import("../../jetzig.zig");

pub const middleware_name = "anti_csrf";

const TokenParams = @Type(.{
    .@"struct" = .{
        .layout = .auto,
        .is_tuple = false,
        .decls = &.{},
        .fields = &.{.{
            .name = jetzig.authenticity_token_name ++ "",
            .type = []const u8,
            .is_comptime = false,
            .default_value_ptr = null,
            .alignment = @alignOf([]const u8),
        }},
    },
});

pub fn afterRequest(request: *jetzig.http.Request) !void {
    try verifyCsrfToken(request);
}

pub fn beforeRender(request: *jetzig.http.Request, route: jetzig.views.Route) !void {
    _ = route;
    try verifyCsrfToken(request);
}

fn logFailure(request: *jetzig.http.Request) !void {
    _ = request.fail(.forbidden);
    try request.server.logger.DEBUG("Anti-CSRF token validation failed. Request aborted.", .{});
}

fn verifyCsrfToken(request: *jetzig.http.Request) !void {
    switch (request.method) {
        .DELETE, .PATCH, .PUT, .POST => {},
        else => return,
    }

    switch (request.requestFormat()) {
        .HTML, .UNKNOWN => {},
        // We do not authenticate JSON requests. Users must implement their own authentication
        // system or disable JSON endpoints that should be protected.
        .JSON => return,
    }

    const session = try request.session();

    if (session.getT(.string, jetzig.authenticity_token_name)) |token| {
        const params = try request.expectParams(TokenParams) orelse {
            return logFailure(request);
        };

        if (token.len != 32 or @field(params, jetzig.authenticity_token_name).len != 32) {
            return try logFailure(request);
        }

        var actual: [32]u8 = undefined;
        var expected: [32]u8 = undefined;

        @memcpy(&actual, token[0..32]);
        @memcpy(&expected, @field(params, jetzig.authenticity_token_name)[0..32]);

        const valid = std.crypto.timing_safe.eql([32]u8, expected, actual);

        if (!valid) {
            return try logFailure(request);
        }
    } else {
        return try logFailure(request);
    }
}
