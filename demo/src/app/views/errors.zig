const std = @import("std");
const jetzig = @import("jetzig");

// Generic handler for all errors.
// Use `jetzig.http.status_codes.get(request.status_code)` to get a value that provides string
// versions of the error code and message for use in templates.
pub fn index(request: *jetzig.Request, data: *jetzig.Data) !jetzig.View {
    var root = try data.object();
    var error_info = try data.object();

    const status = jetzig.http.status_codes.get(request.status_code);

    try error_info.put("code", data.string(status.getCode()));
    try error_info.put("message", data.string(status.getMessage()));

    try root.put("error", error_info);

    // Render with the original error status code, or override if preferred.
    return request.render(request.status_code);
}
