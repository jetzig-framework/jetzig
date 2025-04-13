const std = @import("std");
const builtin = @import("builtin");

pub const build_options = @import("build_options");

pub const Server = @import("http/Server.zig");
pub const Request = @import("http/Request.zig");
pub const StaticRequest = if (build_options.environment == .development)
    Request
else
    @import("http/StaticRequest.zig");
pub const Response = @import("http/Response.zig");
pub const Session = @import("http/Session.zig");
pub const Cookies = @import("http/Cookies.zig");
pub const Headers = @import("http/Headers.zig");
pub const Websocket = @import("http/Websocket.zig");
pub const Query = @import("http/Query.zig");
pub const MultipartQuery = @import("http/MultipartQuery.zig");
pub const File = @import("http/File.zig");
pub const Path = @import("http/Path.zig");
pub const status_codes = @import("http/status_codes.zig");
pub const StatusCode = status_codes.StatusCode;
pub const middleware = @import("http/middleware.zig");
pub const mime = @import("http/mime.zig");
pub const params = @import("http/params.zig");

pub const SimplifiedRequest = struct {
    location: ?[]const u8,
};
