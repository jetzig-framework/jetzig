const std = @import("std");
const jetzig = @import("../../jetzig.zig");

const InertiaMiddleware = @This();

pub fn afterView(request: *jetzig.http.Request) !void {
    if (request.headers.get("HX-Target")) |target| {
        try request.server.logger.DEBUG(
            "[middleware-htmx] htmx request detected, disabling layout. (#{s})",
            .{target},
        );
        request.setLayout(null);
    } else {
        const template_context = jetzig.TemplateContext{ .request = request };
        const template = jetzig.zmpl.findPrefixed("jetzig", "inertia").?;
        _ = request.renderContent(.ok, try template.render(
            request.response_data,
            jetzig.TemplateContext,
            template_context,
            .{},
        ));
    }
}

pub fn beforeResponse(request: *jetzig.http.Request, response: *jetzig.http.Response) !void {
    switch (response.status_code) {
        .moved_permanently, .found => {},
        else => return,
    }

    if (request.headers.get("HX-Request") == null) return;

    if (response.headers.get("Location")) |location| {
        response.status_code = .ok;
        request.response_data.reset();
        try response.headers.append("HX-Redirect", location);
    }
}
