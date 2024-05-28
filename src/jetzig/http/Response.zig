const std = @import("std");

const httpz = @import("httpz");

const jetzig = @import("../../jetzig.zig");
const http = @import("../http.zig");

const Self = @This();

allocator: std.mem.Allocator,
headers: jetzig.http.Headers,
content: []const u8,
status_code: http.status_codes.StatusCode,
content_type: []const u8,
httpz_response: *httpz.Response,

pub fn init(
    allocator: std.mem.Allocator,
    httpz_response: *httpz.Response,
) !Self {
    return .{
        .allocator = allocator,
        .httpz_response = httpz_response,
        .status_code = .no_content,
        .content_type = "application/octet-stream",
        .content = "",
        .headers = jetzig.http.Headers.init(allocator, &httpz_response.headers),
    };
}
