test {
    _ = @import("jetzig/http/Query.zig");
    _ = @import("jetzig/http/Headers.zig");
    _ = @import("jetzig/http/Cookies.zig");
    @import("std").testing.refAllDeclsRecursive(@This());
}
