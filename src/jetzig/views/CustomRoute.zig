const jetzig = @import("../../jetzig.zig");

method: jetzig.http.Request.Method,
path: []const u8,
view: union(enum) {
    with_id: *const fn (id: []const u8, *jetzig.http.Request, *jetzig.data.Data) anyerror!jetzig.views.View,
    without_id: *const fn (*jetzig.http.Request, *jetzig.data.Data) anyerror!jetzig.views.View,
},
