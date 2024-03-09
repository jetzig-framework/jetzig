const jetzig = @import("jetzig");

pub fn index(request: *jetzig.Request, data: *jetzig.Data) !jetzig.View {
    var root = try data.object();
    try root.put("message", data.string("Welcome to Jetzig!"));
    try root.put("number", data.integer(customFunction(100, 200, 300)));

    try request.response.headers.append("x-example-header", "example header value");

    return request.render(.ok);
}

fn customFunction(a: i32, b: i32, c: i32) i32 {
    return a + b + c;
}
