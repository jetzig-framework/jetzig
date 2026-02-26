const std = @import("std");

const httpz = @import("httpz");

const jetzig = @import("../../jetzig.zig");

allocator: std.mem.Allocator,
key_value: *httpz.key_value.MultiFormKeyValue,

const MultipartQuery = @This();

/// Fetch a file from multipart form data, if present.
pub fn getFile(self: MultipartQuery, key: []const u8) ?jetzig.http.File {
    const keys = self.key_value.keys;
    const values = self.key_value.values;

    for (keys[0..self.key_value.len], values[0..self.key_value.len]) |name, field| {
        const filename = field.filename orelse continue;

        if (std.mem.eql(u8, name, key)) return jetzig.http.File{
            .filename = filename,
            .content = field.value,
        };
    }

    return null;
}

/// Fetch all files matching a key from multipart form data. Useful when a file
/// input has the `multiple` attribute and several files share the same field name.
pub fn getFiles(self: MultipartQuery, key: []const u8) []const jetzig.http.File {
    const keys = self.key_value.keys;
    const values = self.key_value.values;

    var count: usize = 0;
    for (keys[0..self.key_value.len], values[0..self.key_value.len]) |name, field| {
        if (field.filename == null) continue;
        if (std.mem.eql(u8, name, key)) count += 1;
    }

    if (count == 0) return &.{};

    const result = self.allocator.alloc(jetzig.http.File, count) catch return &.{};
    var i: usize = 0;
    for (keys[0..self.key_value.len], values[0..self.key_value.len]) |name, field| {
        const filename = field.filename orelse continue;
        if (std.mem.eql(u8, name, key)) {
            result[i] = .{ .filename = filename, .content = field.value };
            i += 1;
        }
    }

    return result[0..i];
}

/// Return all params in a multipart form submission **excluding** files. Use
/// `jetzig.http.Request.getFile` to read a file object (includes filename and data).
pub fn params(self: MultipartQuery) !*jetzig.data.Data {
    const data = try self.allocator.create(jetzig.data.Data);
    data.* = jetzig.data.Data.init(self.allocator);
    var root = try data.root(.object);

    const keys = self.key_value.keys;
    const values = self.key_value.values;

    for (keys[0..self.key_value.len], values[0..self.key_value.len]) |name, field| {
        if (field.filename != null) continue;

        try root.put(name, field.value);
    }

    return data;
}
