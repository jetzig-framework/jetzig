const std = @import("std");
const jetzig = @import("../../jetzig.zig");

pub const KVOptions = struct {
    backend: enum { memory, file, valkey } = .memory,
    file_options: struct {
        path: ?[]const u8 = null,
        address_space_size: u32 = jetzig.jetkv.FileBackend.addressSpace(4096),
        truncate: bool = false,
    } = .{},
    valkey_options: struct {
        host: []const u8 = "localhost",
        port: u16 = 6379,
        connect_timeout: u64 = 1000, // (ms)
        read_timeout: u64 = 1000, // (ms)
        connect: enum { auto, manual, lazy } = .lazy,
        buffer_size: u32 = 8192,
        pool_size: u16 = 8,
    } = .{},
};

const ValueType = enum { string, array };

fn jetKVOptions(options: KVOptions) jetzig.jetkv.Options {
    return switch (options.backend) {
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
        .valkey => .{
            .backend = .valkey,
            .valkey_backend_options = .{
                .host = options.valkey_options.host,
                .port = options.valkey_options.port,
                .connect_timeout = options.valkey_options.connect_timeout * std.time.ms_per_s,
                .read_timeout = options.valkey_options.read_timeout * std.time.ms_per_s,
                .connect = std.enums.nameCast(
                    jetzig.jetkv.ValkeyBackendOptions.ConnectMode,
                    options.valkey_options.connect,
                ),
                .buffer_size = options.valkey_options.buffer_size,
                .pool_size = options.valkey_options.pool_size,
            },
        },
    };
}

/// Role a given store fills. Used in log outputs.
pub const Role = enum { jobs, cache, general, custom };

pub fn Store(comptime options: KVOptions) type {
    return struct {
        const Self = @This();

        store: jetzig.jetkv.JetKV(jetKVOptions(options)),
        logger: jetzig.loggers.Logger,
        options: KVOptions,
        role: Role,

        /// Initialize a new memory or file store.
        pub fn init(allocator: std.mem.Allocator, logger: jetzig.loggers.Logger, role: Role) !Self {
            const store = try jetzig.jetkv.JetKV(jetKVOptions(options)).init(allocator);

            return .{ .store = store, .role = role, .logger = logger, .options = options };
        }

        /// Free allocated resources/close database file.
        pub fn deinit(self: *Self) void {
            self.store.deinit();
        }

        /// Put a or into the key-value store.
        pub fn put(self: *Self, key: []const u8, value: *jetzig.data.Value) !void {
            try self.store.put(key, try value.toJson());
            if (self.role == .cache) {
                try self.logger.DEBUG(
                    "[cache:{s}:store] {s}",
                    .{ @tagName(self.store.backend), key },
                );
            }
        }

        /// Put a or into the key-value store with an expiration in seconds.
        pub fn putExpire(self: *Self, key: []const u8, value: *jetzig.data.Value, expiration: i32) !void {
            try self.store.putExpire(key, try value.toJson(), expiration);
            if (self.role == .cache) {
                try self.logger.DEBUG(
                    "[cache:{s}:store:expire:{d}s] {s}",
                    .{ @tagName(self.store.backend), expiration, key },
                );
            }
        }

        /// Get a Value from the store.
        pub fn get(self: *Self, data: *jetzig.data.Data, key: []const u8) !?*jetzig.data.Value {
            const start = std.time.nanoTimestamp();
            const json = try self.store.get(data.allocator, key);
            const value = try parseValue(data, json);
            const end = std.time.nanoTimestamp();
            if (self.role == .cache) {
                if (value == null) {
                    try self.logger.DEBUG("[cache:miss] {s}", .{key});
                } else {
                    try self.logger.DEBUG(
                        "[cache:{s}:hit:{}] {s}",
                        .{
                            @tagName(self.store.backend),
                            std.fmt.fmtDuration(@intCast(end - start)),
                            key,
                        },
                    );
                }
            }
            return value;
        }

        /// Remove a Value to from the key-value store and return it if found.
        pub fn fetchRemove(self: *Self, data: *jetzig.data.Data, key: []const u8) !?*jetzig.data.Value {
            return try parseValue(data, try self.store.fetchRemove(data.allocator, key));
        }

        /// Remove a Value to from the key-value store.
        pub fn remove(self: *Self, key: []const u8) !void {
            try self.store.remove(key);
        }

        /// Append a Value to the end of an Array in the key-value store.
        pub fn append(self: *Self, key: []const u8, value: *const jetzig.data.Value) !void {
            try self.store.append(key, try value.toJson());
        }

        /// Prepend a Value to the start of an Array in the key-value store.
        pub fn prepend(self: *Self, key: []const u8, value: *const jetzig.data.Value) !void {
            try self.store.prepend(key, try value.toJson());
        }

        /// Pop a Value from an Array in the key-value store.
        pub fn pop(self: *Self, data: *jetzig.data.Data, key: []const u8) !?*jetzig.data.Value {
            return try parseValue(data, try self.store.pop(data.allocator, key));
        }

        /// Left-pop a Value from an Array in the key-value store.
        pub fn popFirst(self: *Self, data: *jetzig.data.Data, key: []const u8) !?*jetzig.data.Value {
            return try parseValue(data, try self.store.popFirst(data.allocator, key));
        }
    };
}

fn parseValue(data: *jetzig.data.Data, maybe_json: ?[]const u8) !?*jetzig.data.Value {
    if (maybe_json) |json| {
        try data.fromJson(json);
        return data.value.?;
    } else {
        return null;
    }
}
