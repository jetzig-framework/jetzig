const jetzig = @import("jetzig");

pub fn index(request: *jetzig.http.StaticRequest, data: *jetzig.data.Data) anyerror!jetzig.views.View {
    _ = data;
    return request.render(.ok);
}
