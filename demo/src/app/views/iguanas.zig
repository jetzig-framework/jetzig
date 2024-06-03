const std = @import("std");
const jetzig = @import("jetzig");
const iguanas = @import("iguanas");

/// This example uses a layout. A layout is a template that exists in `src/app/views/layouts` and
/// references `{zmpl.content}`.
///
/// The content is the rendered template for the current view which is then injected into the
/// layout in place of `{zmpl.content}`.
///
/// See `demo/src/app/views/layouts/application.zmpl`
/// and `demo/src/app/views/iguanas/index.zmpl`
pub const layout = "application";

pub fn index(request: *jetzig.Request, data: *jetzig.Data) !jetzig.View {
    var root = try data.array();

    const params = try request.params();

    const count = params.getT(.integer, "iguanas") orelse 10;

    const iguanas_slice = try iguanas.iguanas(request.allocator, @intCast(count));

    for (iguanas_slice) |iguana| {
        try root.append(data.string(iguana));
    }

    return request.render(.ok);
}

test "index" {
    var app = try jetzig.testing.app(std.testing.allocator, @import("routes"));
    defer app.deinit();

    const response = try app.request(.GET, "/iguanas", .{ .json = .{ .iguanas = 10 } });
    try response.expectJson(".1", "iguana");
    try response.expectJson(".2", "iguana");
    try response.expectJson(".3", "iguana");
    try response.expectJson(".4", "iguana");
    try response.expectJson(".5", "iguana");
    try response.expectJson(".6", "iguana");
    try response.expectJson(".7", "iguana");
    try response.expectJson(".8", "iguana");
    try response.expectJson(".9", "iguana");
}
