const std = @import("std");
const jetzig = @import("jetzig");

pub fn index(request: *jetzig.Request, data: *jetzig.Data) !jetzig.View {
    _ = data;
    const params = try request.params();
    if (params.get("redirect")) |location| {
        return request.redirect(try location.toString(), .moved_permanently);
    }

    return request.render(.ok);
}
