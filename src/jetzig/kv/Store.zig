const std = @import("std");
const jetzig = @import("../../jetzig.zig");

const Store = @This();

store: jetzig.jetkv.JetKV,
options: KVOptions,

pub const KVOptions = struct {
    backend: enum { memory, file } = .memory,
    file_options: struct {
        path: ?[]const u8 = null,
        address_space_size: u32 = jetzig.jetkv.JetKV.FileBackend.addressSpace(4096),
        truncate: bool = false,
    } = .{},
};

const ValueType = enum { string, array };

/// Initialize a new memory or file store.
pub fn init(allocator: std.mem.Allocator, options: KVOptions) !Store {
    const store = try jetzig.jetkv.JetKV.init(
        allocator,
        switch (options.backend) {
            .file => .{
                .backend = .file,
                .file_backend_options = .{
                    .path = options.file_options.path,
                    .address_space_size = options.file_options.address_space_size,
                    .truncate = options.file_options.truncate,
                },
            },
            .memory => .{
                .backend = .memory,
            },
        },
    );

    return .{ .store = store, .options = options };
}

/// Free allocated resources/close database file.
pub fn deinit(self: *Store) void {
    self.store.deinit();
}

/// Put a Value or into the key-value store.
pub fn put(self: *Store, key: []const u8, value: *jetzig.data.Value) !void {
    try self.store.put(key, try value.toJson());
}

/// Get a Value from the store.
pub fn get(self: *Store, data: *jetzig.data.Data, key: []const u8) !?*jetzig.data.Value {
    return try parseValue(data, try self.store.get(data.allocator(), key));
}

/// Remove a Value to from the key-value store and return it if found.
pub fn fetchRemove(self: *Store, data: *jetzig.data.Data, key: []const u8) !?*jetzig.data.Value {
    return try parseValue(data, try self.store.fetchRemove(data.allocator(), key));
}

/// Remove a Value to from the key-value store.
pub fn remove(self: *Store, key: []const u8) !void {
    try self.store.remove(key);
}

/// Append a Value to the end of an Array in the key-value store.
pub fn append(self: *Store, key: []const u8, value: *const jetzig.data.Value) !void {
    try self.store.append(key, try value.toJson());
}

/// Prepend a Value to the start of an Array in the key-value store.
pub fn prepend(self: *Store, key: []const u8, value: *const jetzig.data.Value) !void {
    try self.store.prepend(key, try value.toJson());
}

/// Pop a Value from an Array in the key-value store.
pub fn pop(self: *Store, data: *jetzig.data.Data, key: []const u8) !?*jetzig.data.Value {
    return try parseValue(data, try self.store.pop(data.allocator(), key));
}

/// Left-pop a Value from an Array in the key-value store.
pub fn popFirst(self: *Store, data: *jetzig.data.Data, key: []const u8) !?*jetzig.data.Value {
    return try parseValue(data, try self.store.popFirst(data.allocator(), key));
}

fn parseValue(data: *jetzig.data.Data, maybe_json: ?[]const u8) !?*jetzig.data.Value {
    if (maybe_json) |json| {
        try data.fromJson(json);
        return data.value.?;
    } else {
        return null;
    }
}
