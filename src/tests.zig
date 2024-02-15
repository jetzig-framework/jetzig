test {
    _ = @import("jetzig.zig");
    @import("std").testing.refAllDeclsRecursive(@This());
}
