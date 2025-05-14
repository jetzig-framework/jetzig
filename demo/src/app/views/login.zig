const std = @import("std");
const jetzig = @import("jetzig");
const auth = @import("jetzig").auth;

pub fn index(request: *jetzig.Request) !jetzig.View {
    var root = try request.data(.object);

    if (request.middleware(.auth).user) |user| {
        try root.put("user", .{ .email = user.email });
    }

    return request.render(.ok);
}

pub fn post(request: *jetzig.Request) !jetzig.View {
    const Logout = struct { logout: []const u8 };
    const Login = struct { email: []const u8, password: []const u8 };

    if (try request.expectParams(Logout)) |_| {
        try auth.signOut(request);
        return request.redirect("/login", .found);
    }

    const params = try request.expectParams(Login) orelse {
        return request.fail(.forbidden);
    };

    // Lookup the user by email
    const user = try jetzig.database.Query(.User).findBy(
        .{ .email = params.email },
    ).execute(request.repo) orelse {
        return request.fail(.forbidden);
    };

    // Check that the password matches
    if (!try auth.verifyPassword(
        request.allocator,
        user.password_hash,
        params.password,
    )) return request.fail(.forbidden);

    try auth.signIn(request, user.id);
    return request.redirect("/login", .found);
}

test "post" {
    var app = try jetzig.testing.app(std.testing.allocator, @import("routes"));
    defer app.deinit();

    const hashed_pass = try auth.hashPassword(std.testing.allocator, "test");
    defer std.testing.allocator.free(hashed_pass);

    try jetzig.database.Query(.User).deleteAll().execute(app.repo);
    try app.repo.insert(.User, .{
        .id = 1,
        .email = "test@test.com",
        .password_hash = hashed_pass,
    });

    const response = try app.request(.POST, "/login", .{
        .json = .{
            .email = "test@test.com",
            .password = "test",
        },
    });
    try response.expectStatus(.found);
}
