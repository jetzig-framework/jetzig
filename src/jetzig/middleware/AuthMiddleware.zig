const std = @import("std");
const jetzig = @import("jetzig");

pub const middleware_name = "auth";

// Default model is `.User`.
const user_model = jetzig.config.get(jetzig.auth.AuthOptions, "auth").user_model;

/// Define any custom data fields you want to store here. Assigning to these fields in the `init`
/// function allows you to access them in the `beforeRequest` and `afterRequest` functions, where
/// they can also be modified.
user: ?@TypeOf(jetzig.database.Query(user_model).find(0)).ResultType(),

const Self = @This();

/// Initialize middleware.
pub fn init(request: *jetzig.http.Request) !*Self {
    const middleware = try request.allocator.create(Self);
    middleware.* = .{ .user = null };
    return middleware;
}

const map = std.StaticStringMap(void).initComptime(.{
    .{ ".html", void },
    .{ ".json", void },
});

/// For HTML/JSON requests, fetch a user ID from the encrypted session cookie and execute a
/// database query to match the user ID to a database record. Expects a `User` model defined in
/// the schema, configurable with `auth.user_model`.
///
/// User ID is accessible from a request:
/// ```zig
///
pub fn afterRequest(self: *Self, request: *jetzig.http.Request) !void {
    if (request.path.extension) |extension| {
        if (map.get(extension) == null) return;
    }
    const user_id = try jetzig.auth.getUserId(.integer, request) orelse return;

    const query = jetzig.database.Query(user_model).find(user_id);
    if (try request.repo.execute(query)) |user| {
        self.user = user;
    }
}

/// Invoked after `afterRequest` is called, use this function to do any clean-up.
/// Note that `request.allocator` is an arena allocator, so any allocations are automatically
/// done before the next request starts processing.
pub fn deinit(self: *Self, request: *jetzig.http.Request) void {
    request.allocator.destroy(self);
}
