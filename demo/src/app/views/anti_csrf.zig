const std = @import("std");
const jetzig = @import("jetzig");

// Anti-CSRF middleware can be included in the view's `actions` declaration to apply CSRF
// protection just to this specific view, or it can be added to your application's global
// middleware stack defined in `jetzig_options` in `src/main.zig`.
//
// Use `{{context.authenticityToken()}}` or `{{context.authenticityFormField()}}` in a Zmpl
// template to generate a token, store it in the user's session, and inject it into the page.

pub const actions = .{
    .before = .{jetzig.middleware.AntiCsrfMiddleware},
};

pub fn post(request: *jetzig.Request) !jetzig.View {
    var root = try request.data(.object);

    const Params = struct { spam: []const u8 };
    const params = try request.expectParams(Params) orelse {
        return request.fail(.unprocessable_entity);
    };

    try root.put("spam", params.spam);

    return request.render(.created);
}

pub fn index(request: *jetzig.Request) !jetzig.View {
    return request.render(.ok);
}

test "post with missing token" {
    var app = try jetzig.testing.app(std.testing.allocator, @import("routes"));
    defer app.deinit();

    const response = try app.request(.POST, "/anti_csrf", .{});
    try response.expectStatus(.forbidden);
}

test "post with invalid token" {
    var app = try jetzig.testing.app(std.testing.allocator, @import("routes"));
    defer app.deinit();

    const response = try app.request(.POST, "/anti_csrf", .{});
    try response.expectStatus(.forbidden);
}

test "post with valid token but missing expected params" {
    var app = try jetzig.testing.app(std.testing.allocator, @import("routes"));
    defer app.deinit();

    _ = try app.request(.GET, "/anti_csrf", .{});
    const token = app.session.getT(.string, jetzig.authenticity_token_name).?;
    const response = try app.request(
        .POST,
        "/anti_csrf",
        .{ .params = .{ ._jetzig_authenticity_token = token } },
    );
    try response.expectStatus(.unprocessable_entity);
}

test "post with valid token and expected params" {
    var app = try jetzig.testing.app(std.testing.allocator, @import("routes"));
    defer app.deinit();

    _ = try app.request(.GET, "/anti_csrf", .{});
    const token = app.session.getT(.string, jetzig.authenticity_token_name).?;
    const response = try app.request(
        .POST,
        "/anti_csrf",
        .{ .params = .{ ._jetzig_authenticity_token = token, .spam = "Spam" } },
    );
    try response.expectStatus(.created);
}

test "index" {
    var app = try jetzig.testing.app(std.testing.allocator, @import("routes"));
    defer app.deinit();

    const response = try app.request(.GET, "/anti_csrf", .{});
    try response.expectStatus(.ok);
}
