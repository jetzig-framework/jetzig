const jetzig = @import("../../jetzig.zig");

pub const ViewWithoutId = *const fn (
    *jetzig.http.Request,
) anyerror!jetzig.views.View;

pub const ViewWithId = *const fn (
    id: []const u8,
    *jetzig.http.Request,
) anyerror!jetzig.views.View;

pub const ViewWithArgs = *const fn (
    []const []const u8,
    *jetzig.http.Request,
) anyerror!jetzig.views.View;

pub const StaticViewWithoutId = *const fn (
    *jetzig.http.StaticRequest,
) anyerror!jetzig.views.View;

pub const StaticViewWithId = *const fn (
    id: []const u8,
    *jetzig.http.StaticRequest,
) anyerror!jetzig.views.View;

pub const StaticViewWithArgs = *const fn (
    []const []const u8,
    *jetzig.http.StaticRequest,
) anyerror!jetzig.views.View;

// Legacy view types receive a `data` argument. This made sense when `data.string(...)` etc. were
// needed to create a string, but now we use type inference/coercion when adding values to
// response data.
// `Array.append(.array)`, `Array.append(.object)`, `Object.put(key, .array)`, and
// `Object.put(key, .object)` also remove the need to use `data.array()` and `data.object()`.
// The only remaining use is `data.root(.object)` and `data.root(.array)` which we can move to
// `request.responseData(.object)` and `request.responseData(.array)`.
pub const LegacyViewWithoutId = *const fn (
    *jetzig.http.Request,
    *jetzig.data.Data,
) anyerror!jetzig.views.View;

pub const LegacyViewWithId = *const fn (
    id: []const u8,
    *jetzig.http.Request,
    *jetzig.data.Data,
) anyerror!jetzig.views.View;

pub const LegacyStaticViewWithoutId = *const fn (
    *jetzig.http.StaticRequest,
    *jetzig.data.Data,
) anyerror!jetzig.views.View;

pub const LegacyViewWithArgs = *const fn (
    []const []const u8,
    *jetzig.http.Request,
    *jetzig.data.Data,
) anyerror!jetzig.views.View;

pub const LegacyStaticViewWithId = *const fn (
    id: []const u8,
    *jetzig.http.StaticRequest,
    *jetzig.data.Data,
) anyerror!jetzig.views.View;

pub const LegacyStaticViewWithArgs = *const fn (
    []const []const u8,
    *jetzig.http.StaticRequest,
) anyerror!jetzig.views.View;
