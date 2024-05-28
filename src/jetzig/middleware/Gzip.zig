const std = @import("std");
const jetzig = @import("jetzig");

const err_msg = "Response was not compressed due to error: {s}";
pub fn beforeResponse(request: *jetzig.http.Request, response: *jetzig.http.Response) !void {
    var compressed = std.ArrayList(u8).init(request.allocator);
    var reader = std.io.fixedBufferStream(response.content);
    std.compress.gzip.compress(reader.reader(), compressed.writer(), .{ .level = .fast }) catch |err|
        return request.server.logger.ERROR(err_msg, .{@errorName(err)});
    response.headers.append("Content-Encoding", "gzip") catch |err|
        return request.server.logger.ERROR(err_msg, .{@errorName(err)});
    response.content = compressed.items;
}
