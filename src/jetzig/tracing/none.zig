pub const tracing = @import("../tracing.zig");

pub const NoneBackend = @This();

inline fn init(_ : *NoneBackend) void {}
inline fn initThread(_ : *NoneBackend) void {}
inline fn denitThread(_ : *NoneBackend) void {}
inline fn deinit(_ : *NoneBackend) void {}
inline fn finish(_ : tracing.TracingContext) void {}
inline fn trace(_: NoneBackend, _: tracing.TracingContext, comptime _: []const u8, _: anytype) void {}