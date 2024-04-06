const std = @import("std");
const jetzig = @import("jetzig");

pub fn index(request: *jetzig.Request, data: *jetzig.Data) !jetzig.View {
    _ = data;
    const params = try request.params();
    if (params.get("redirect")) |location| {
        switch (location.*) {
            // Value is `.Null` when param is empty, e.g.:
            // `http://localhost:8080/redirect?redirect`
            .Null => return request.redirect("http://www.example.com/", .moved_permanently),
            // Value is `.string` when param is present, e.g.:
            // `http://localhost:8080/redirect?redirect=https://jetzig.dev/`
            .string => |string| return request.redirect(string.value, .moved_permanently),
            else => unreachable,
        }
    }

    return request.render(.ok);
}
