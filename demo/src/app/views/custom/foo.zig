const jetzig = @import("jetzig");

pub fn bar(id: []const u8, request: *jetzig.Request) !jetzig.View {
    var root = try request.data(.object);
    try root.put("id", id);
    return request.render(.ok);
}
