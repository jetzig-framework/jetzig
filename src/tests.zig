test {
    _ = @import("jetzig.zig");
    _ = @import("jetzig/http/Query.zig");
    @import("std").testing.refAllDeclsRecursive(@This());
}
