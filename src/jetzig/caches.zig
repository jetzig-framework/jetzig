const std = @import("std");

const http = @import("http.zig");

pub const Result = @import("caches/Result.zig");
pub const MemoryCache = @import("caches/MemoryCache.zig");
pub const NullCache = @import("caches/NullCache.zig");

pub const Cache = union(enum) {
    memory_cache: MemoryCache,
    null_cache: NullCache,

    pub fn deinit(self: *Cache) void {
        switch (self.*) {
            inline else => |*case| case.deinit(),
        }
    }

    pub fn get(self: *Cache, key: []const u8) ?Result {
        return switch (self.*) {
            inline else => |*case| case.get(key),
        };
    }

    pub fn put(self: *Cache, key: []const u8, value: http.Response) !Result {
        return switch (self.*) {
            inline else => |*case| case.put(key, value),
        };
    }
};
