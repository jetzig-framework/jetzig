const std = @import("std");
const config = @import("../jetzig.zig").config;
const is_enabled = config.get(bool, "tracing_enabled");
const tracing_backend = config.get(TracingBackend, "tracing_backend");
const tracing_scopes = config.get([]const TracingScopes, "tracing_scopes");
const tracing_path = config.get(TracingLazyPath, "tracing_folder");
pub const TracingBackend = enum {
    none,
    log,
    chrome, 
};

pub const TracingScopes = enum {
    http_server,
    jobs,
    key_value_store,
    loggers,
    mail,
    middleware_internal,
    views,
    startup,
    markdown,
    database,
    user
};


pub const TracingLazyPath = union(enum) {
    path: []const u8,
    cwd: void,
};


threadlocal var started = false;


pub const TracingContext = struct {
    source: std.builtin.SourceLocation,
    ImplInterface: ImplInterface,

    pub inline fn finish(self: TracingContext) void {
        if(started) {
            switch(self.ImplInterface) {
                inline else => |backend| {
                    backend.finish(self);
                }
            }
            started = false;
        }
    }
};

pub const ImplInterface = union(TracingBackend) {
    none: @import("tracing/none.zig"),
    log: @import("tracing/logger.zig"),
    chrome: @import("tracing/chrome.zig"),

    pub fn init(self: TracingBackend) void {
        switch(self) {
            inline else => |backend| {
                backend.init();
            }
        }
    }

    pub fn threadedInit(self: TracingBackend) void {
        switch(self) {
            inline else => |backend| {
                backend.initThread();
            }
        }
        started = true;
    }

    pub fn deinit(self: TracingBackend) void {
        switch(self) {
            inline else => |backend| {
                if(started) {
                    backend.deinitThread();
                } else {
                    backend.deinit();
                }
            }
        }
    }

    pub inline fn trace(self: TracingBackend, comptime formatted_message: []const u8, args: anytype) TracingContext {
        const ctx : TracingContext = .{
            .ImplInterface = self,
            .source_file = @src()
        };
        switch(self) {
            inline else => |backend| {
                backend.trace(ctx, formatted_message, args);
            }
        }
        return ctx;
    }
};