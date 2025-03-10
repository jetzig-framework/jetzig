const jetquery = @import("jetzig").jetquery;

pub const User = jetquery.Model(@This(), "users", struct {
    id: i32,
    email: []const u8,
    password_hash: []const u8,
    created_at: jetquery.DateTime,
    updated_at: jetquery.DateTime,
}, .{});
