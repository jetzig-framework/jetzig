const std = @import("std");
const jetzig = @import("jetzig");
const auth = @import("jetzig").auth;

pub fn index(request: *jetzig.Request) !jetzig.View {
    return request.render(.ok);
}

pub fn post(request: *jetzig.Request) !jetzig.View {
    const Login = struct {
        email: []const u8,
        password: []const u8,
    };

    const params = try request.expectParams(Login) orelse {
        return request.fail(.forbidden);
    };

    // Lookup the user by email
    const query = jetzig.database.Query(.User).findBy(
        .{ .email = params.email },
    );

    const user = try request.repo.execute(query) orelse {
        return request.fail(.forbidden);
    };

    // Check that the password matches
    if (try auth.verifyPassword(
        request.allocator,
        user.password_hash,
        params.password,
    )) {
        try auth.signIn(request, user.id);
        return request.redirect("/", .found);
    }
    return request.fail(.forbidden);
}
