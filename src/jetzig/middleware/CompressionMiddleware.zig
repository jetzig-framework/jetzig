const std = @import("std");
const jetzig = @import("jetzig");

fn checkType(content_type: []const u8) bool {
    const type_list = .{ "text/html", "application/xhtml+xml", "application/xml", "text/css", "text/javascript", "application/json", "application/pdf", "image/svg+xml" };
    inline for (type_list) |content| {
        if (std.mem.eql(u8, content_type, content)) return true;
    }
    return false;
}

const Encoding = enum {
    None,
    Gzip,
    Deflate,
};
const err_msg = "Response was not compressed due to error: {s}";
/// Parse accepted encoding, encode responses if possible, set appropriate headers, and
/// modify the response accordingly to decrease response size
pub fn beforeResponse(request: *jetzig.http.Request, response: *jetzig.http.Response) !void {
    // Only some file types need compressions, skip the others
    if (!checkType(response.content_type)) return;

    // Find matching encoding
    var encoding = Encoding.None;
    for (request.headers.getAll("Accept-Encoding")) |encodings| find_encoding: {
        var buffer: [64]u8 = undefined;
        var encodings_stream = std.io.fixedBufferStream(encodings);
        var encodings_reader = encodings_stream.reader();
        while (try encodings_reader.readUntilDelimiterOrEof(&buffer, ',')) |encoding_str| {
            const encoding_trimmed = encoding_str[if (encoding_str[0] == ' ') 1 else 0..];
            const encoding_list = .{ "gzip", "deflate" };
            inline for (encoding_list, 0..) |encoding_compare, i| {
                if (std.mem.eql(u8, encoding_compare, encoding_trimmed)) {
                    encoding = @enumFromInt(i + 1);
                    break :find_encoding;
                }
            }
            std.debug.print("Encoding: {s}\n", .{encoding_str});
        }
    }
    if (encoding == .None) return;

    // Compress data
    var compressed = std.ArrayList(u8).init(request.allocator);
    var content_reader = std.io.fixedBufferStream(response.content);
    switch (encoding) {
        .Gzip => {
            std.compress.gzip.compress(content_reader.reader(), compressed.writer(), .{ .level = .fast }) catch |err|
                return request.server.logger.ERROR(err_msg, .{@errorName(err)});
            response.headers.append("Content-Encoding", "gzip") catch |err|
                return request.server.logger.ERROR(err_msg, .{@errorName(err)});
        },
        .Deflate => {
            std.compress.flate.compress(content_reader.reader(), compressed.writer(), .{ .level = .fast }) catch |err|
                return request.server.logger.ERROR(err_msg, .{@errorName(err)});
            response.headers.append("Content-Encoding", "deflate") catch |err|
                return request.server.logger.ERROR(err_msg, .{@errorName(err)});
        },
        else => {
            // The compression is not supported
            // TODO: Can add zstd and br in the future, but gzip / deflate
            // support through the std is good enough
            return;
        },
    }
    // Make caching work
    response.headers.append("Vary", "Accept-Encoding") catch |err|
        return request.server.logger.ERROR(err_msg, .{@errorName(err)});

    response.content = compressed.items;
}
