const jetzig = @import("jetzig");

const Request = jetzig.http.Request;
const Data = jetzig.data.Data;
const View = jetzig.views.View;

pub fn get(id: []const u8, request: *Request, data: *Data) anyerror!View {
    var user = try data.object();

    try user.put("email", data.string("user@example.com"));
    try user.put("name", data.string("Ziggy Ziguana"));
    try user.put("id", data.string(id));

    return request.render(.ok);
}
