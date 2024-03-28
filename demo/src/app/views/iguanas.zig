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

    const count = if (params.get("iguanas")) |param|
        try std.fmt.parseInt(usize, param.string.value, 10)
    else
        10;

    const iguanas_slice = try iguanas.iguanas(request.allocator, count);

    for (iguanas_slice) |iguana| {
        try root.append(data.string(iguana));
    }

    return request.render(.ok);
}
