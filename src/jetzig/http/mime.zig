// Mime types borrowed from here:
// https://mimetype.io/all-types
// https://github.com/patrickmccallum/mimetype-io/blob/master/src/mimeData.json

const std = @import("std");

const mime_types = @import("mime_types").mime_types; // Generated at build time.

/// Provides information about a given MIME Type.
pub const MimeType = struct {
    name: []const u8,
};

/// Attempts to map a given extension to a mime type.
pub fn fromExtension(extension: []const u8) ?MimeType {
    for (mime_types) |mime_type| {
        if (std.mem.eql(u8, extension, mime_type.file_type)) return .{ .name = mime_type.name };
    }
    return null;
}

pub const MimeMap = struct {
    allocator: std.mem.Allocator,
    map: std.StringHashMap([]const u8),

    pub fn init(allocator: std.mem.Allocator) MimeMap {
        return .{
            .allocator = allocator,
            .map = std.StringHashMap([]const u8).init(allocator),
        };
    }

    pub fn deinit(self: *MimeMap) void {
        self.map.deinit();
    }

    pub fn build(self: *MimeMap) !void {
        for (mime_types) |mime_type| {
            try self.map.put(
                mime_type.file_type,
                mime_type.name,
            );
        }
    }

    pub fn get(self: *MimeMap, file_type: []const u8) ?[]const u8 {
        return self.map.get(file_type);
    }
};
