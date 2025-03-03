const std = @import("std");
const jetzig = @import("../../jetzig.zig");

fn isCompressable(content_type: []const u8) bool {
    const type_list = .{
        "text/html",
        "application/xhtml+xml",
        "application/xml",
        "text/css",
        "text/javascript",
        "application/json",
        "application/pdf",
        "image/svg+xml",
    };

    inline for (type_list) |content| {
        if (std.mem.eql(u8, content_type, content)) return true;
    }
    return false;
}

const Encoding = enum { gzip, deflate };
/// Parse accepted encoding, encode responses if possible, set appropriate headers, and
/// modify the response accordingly to decrease response size
pub fn beforeResponse(request: *jetzig.http.Request, response: *jetzig.http.Response) !void {
    if (!isCompressable(response.content_type)) return;
    const encoding = detectEncoding(request) orelse return;

    const compressed = switch (encoding) {
        .gzip => jetzig.util.gzip(request.allocator, response.content, .{}) catch |err|
            return request.server.logger.logError(@errorReturnTrace(), err),
        .deflate => jetzig.util.deflate(request.allocator, response.content, .{}) catch |err|
            return request.server.logger.logError(@errorReturnTrace(), err),
    };

    response.headers.append("Content-Encoding", @tagName(encoding)) catch |err|
        return request.server.logger.logError(@errorReturnTrace(), err);

    // Make caching work
    response.headers.append("Vary", "Accept-Encoding") catch |err|
        return request.server.logger.logError(@errorReturnTrace(), err);

    response.content = compressed;
}

fn detectEncoding(request: *const jetzig.http.Request) ?Encoding {
    var headers_it = request.headers.getAllIterator("Accept-Encoding");
    while (headers_it.next()) |header| {
        var it = std.mem.tokenizeScalar(u8, header.value, ',');
        while (it.next()) |param| {
            inline for (@typeInfo(Encoding).@"enum".fields) |field| {
                if (std.mem.eql(u8, field.name, jetzig.util.strip(param))) {
                    return std.enums.nameCast(Encoding, field.name);
                }
            }
        }
    }

    return null;
}
