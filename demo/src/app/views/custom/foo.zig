const jetzig = @import("jetzig");

pub fn bar(id: []const u8, request: *jetzig.Request, data: *jetzig.Data) !jetzig.View {
    var root = try data.object();
    try root.put("id", data.string(id));
    return request.render(.ok);
}
