const std = @import("std");
const jetzig = @import("jetzig.zig");

test {
    std.debug.assert(jetzig.jetquery.jetcommon == jetzig.zmpl.jetcommon);
    std.debug.assert(jetzig.zmpl.jetcommon == jetzig.jetcommon);
    _ = @import("jetzig/http/Query.zig");
    _ = @import("jetzig/http/Headers.zig");
    _ = @import("jetzig/http/Cookies.zig");
    _ = @import("jetzig/http/Session.zig");
    _ = @import("jetzig/http/Path.zig");
    _ = @import("jetzig/jobs/Job.zig");
    _ = @import("jetzig/mail/Mail.zig");
    _ = @import("jetzig/loggers/LogQueue.zig");
}
