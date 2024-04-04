const std = @import("std");
const jetzig = @import("jetzig");

/// `src/app/views/root.zig` represents the root URL `/`
/// The `index` view function is invoked when when the HTTP verb is `GET`.
/// Other view types are invoked either by passing a resource ID value (e.g. `/1234`) or by using
/// a different HTTP verb:
///
/// GET / => index(request, data)
/// GET /1234 => get(id, request, data)
/// POST / => post(request, data)
/// PUT /1234 => put(id, request, data)
/// PATCH /1234 => patch(id, request, data)
/// DELETE /1234 => delete(id, request, data)
pub fn index(request: *jetzig.Request, data: *jetzig.Data) !jetzig.View {
    // The first call to `data.object()` or `data.array()` sets the root response data value.
    // JSON requests return a JSON string representation of the root data value.
    // Zmpl templates can access all values in the root data value.
    var root = try data.object();

    // Add a string to the root object.
    try root.put("welcome_message", data.string("Welcome to Jetzig!"));

    // Request params have the same type as a `data.object()` so they can be inserted them
    // directly into the response data. Fetch `http://localhost:8080/?message=hello` to set the
    // param. JSON data is also accepted when the `content-type: application/json` header is
    // present.
    const params = try request.params();

    try root.put("message_param", params.get("message"));

    // Set arbitrary response headers as required. `content-type` is automatically assigned for
    // HTML, JSON responses.
    //
    // Static files located in `public/` in the root of your project directory are accessible
    // from the root path (e.g. `public/jetzig.png`) is available at `/jetzig.png` and the
    // content type is inferred from the extension using MIME types.
    try request.response.headers.append("x-example-header", "example header value");

    // Render the response and set the response code.
    return request.render(.ok);
}
