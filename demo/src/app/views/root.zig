const jetzig = @import("jetzig");

pub fn index(request: *jetzig.Request, data: *jetzig.Data) !jetzig.View {
    var root = try data.object();
    try root.put("message", data.string("Welcome to Jetzig!"));

    try request.response.headers.append("x-example-header", "example header value");

    return request.render(.ok);
}
