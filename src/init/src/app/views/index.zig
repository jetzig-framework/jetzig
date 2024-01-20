const std = @import("std");
const jetzig = @import("jetzig");
const Request = jetzig.http.Request;
const Data = jetzig.data.Data;
const View = jetzig.views.View;

pub fn index(request: *jetzig.http.Request, data: *jetzig.data.Data) anyerror!jetzig.views.View {
    var object = try data.object();
    try object.put("message", data.string("Welcome to Jetzig!"));
    return request.render(.ok);
}
