const std = @import("std");
const jetzig = @import("../../jetzig.zig");
const http = @import("../http.zig");

const Self = @This();

allocator: std.mem.Allocator,
std_response: *std.http.Server.Response,
headers: *jetzig.http.Headers,
content: []const u8,
status_code: http.status_codes.StatusCode,
content_type: []const u8,

pub fn init(
    allocator: std.mem.Allocator,
    std_response: *std.http.Server.Response,
) !Self {
    const headers = try allocator.create(jetzig.http.Headers);
    headers.* = jetzig.http.Headers.init(allocator, std_response.headers);

    return .{
        .allocator = allocator,
        .std_response = std_response,
        .status_code = .no_content,
        .content_type = "application/octet-stream",
        .content = "",
        .headers = headers,
    };
}

pub fn deinit(self: *const Self) void {
    self.headers.deinit();
    self.allocator.destroy(self.headers);
    self.std_response.deinit();
}

const ResetState = enum { reset, closing };

/// Resets the current connection.
pub fn reset(self: *const Self) ResetState {
    return switch (self.std_response.reset()) {
        .reset => .reset,
        .closing => .closing,
    };
}

/// Waits for the current request to finish sending.
pub fn wait(self: *const Self) !void {
    try self.std_response.wait();
}

/// Finalizes a request. Appends any stored headers, sets the response status code, and writes
/// the response body.
pub fn finish(self: *const Self) !void {
    self.std_response.status = switch (self.status_code) {
        inline else => |status_code| @field(std.http.Status, @tagName(status_code)),
    };

    var it = self.headers.iterator();
    while (it.next()) |header| {
        try self.std_response.headers.append(header.name, header.value);
    }

    try self.std_response.send();
    try self.std_response.writeAll(self.content);
    try self.std_response.finish();
}

/// Reads the current request body. Caller owns memory.
pub fn read(self: *const Self) ![]const u8 {
    return try self.std_response.reader().readAllAlloc(self.allocator, jetzig.config.max_bytes_request_body);
}

const TransferEncodingOptions = struct {
    content_length: usize,
};

/// Sets the transfer encoding for the current response (content length/chunked encoding).
/// ```
/// setTransferEncoding(.{ .content_length = 1000 });
/// ```
pub fn setTransferEncoding(self: *const Self, transfer_encoding: TransferEncodingOptions) void {
    // TODO: Chunked encoding
    self.std_response.transfer_encoding = .{ .content_length = transfer_encoding.content_length };
}
