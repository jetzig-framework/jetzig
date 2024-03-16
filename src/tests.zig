test {
    _ = @import("jetzig/http/Query.zig");
    _ = @import("jetzig/http/Headers.zig");
    _ = @import("jetzig/http/Cookies.zig");
    _ = @import("jetzig/http/Path.zig");
    @import("std").testing.refAllDeclsRecursive(@This());
}
