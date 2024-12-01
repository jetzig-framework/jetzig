const std = @import("std");

const config = @import("config.zig");

pub const Store = struct {
    /// Configuration for JetKV. Encompasses all backends:
    /// * valkey
    /// * memory
    /// * file
    ///
    /// The Valkey backend is recommended for production deployment. `memory` and `file` can be
    /// used in local development for convenience. All backends have a unified interface, i.e.
    /// they can be swapped out without any code changes.
    pub const Options = @import("kv/Store.zig").KVOptions;

    // For backward compatibility - `jetzig.kv.Options` is preferred.
    pub const KVOptions = Options;

    /// General-purpose store. Use for storing data with no expiry.
    pub const GeneralStore = @import("kv/Store.zig").Store(config.get(Store.Options, "store"));

    /// Store ephemeral data.
    pub const CacheStore = @import("kv/Store.zig").Store(config.get(Store.Options, "cache"));

    /// Background job storage.
    pub const JobQueueStore = @import("kv/Store.zig").Store(config.get(Store.Options, "job_queue"));

    /// Generic store type. Create a custom store by passing `Options`, e.g.:
    /// ```zig
    /// var store = Generic(.{ .backend = .memory }).init(allocator, logger, .custom);
    /// ```
    pub const Generic = @import("kv/Store.zig").Store;

    /// Role a given store fills. Used in log outputs.
    pub const Role = @import("kv/Store.zig").Role;
};
