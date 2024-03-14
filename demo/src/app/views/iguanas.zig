const std = @import("std");
const jetzig = @import("jetzig");

/// This example uses a layout. A layout is a template that exists in `src/app/views/layouts` and
/// references `{zmpl.content}`.
///
/// The content is the rendered template for the current view which is then injected into the
/// layout in place of `{zmpl.content}`.
///
/// See `demo/src/app/views/layouts/application.zmpl`
/// and `demo/src/app/views/iguanas/index.zmpl`
pub const layout = "application";

pub fn index(request: *jetzig.StaticRequest, data: *jetzig.Data) !jetzig.View {
    _ = data;
    return request.render(.ok);
}
