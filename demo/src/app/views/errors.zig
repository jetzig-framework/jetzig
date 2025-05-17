const std = @import("std");
const jetzig = @import("jetzig");

// Generic handler for all errors.
// Use `jetzig.http.status_codes.get(request.status_code)` to get a value that provides string
// versions of the error code and message for use in templates.
pub fn index(request: *jetzig.Request) !jetzig.View {
    var root = try request.data(.object);
    var error_info = try root.put("error", .object);

    const status = jetzig.http.status_codes.get(request.status_code);

    try error_info.put("code", status.getCode());
    try error_info.put("message", status.getMessage());

    // Render with the original error status code, or override if preferred.
    return request.render(request.status_code);
}
