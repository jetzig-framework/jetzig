/// Abstraction of the path component of a URI.
/// Provides access to:
/// * Unaltered original path
/// * Base path (without extension and query string)
/// * Directory (parent path from base path)
/// * Resource ID (final component of base path)
/// * Extension (".json", ".html", etc.)
/// * Query (everything after first "?" character)
const std = @import("std");

path: []const u8,
base_path: []const u8,
directory: []const u8,
file_path: []const u8,
resource_id: []const u8,
extension: ?[]const u8,
query: ?[]const u8,

const Self = @This();

/// Initialize a new HTTP Path.
pub fn init(path: []const u8) Self {
    const base_path = getBasePath(path);

    return .{
        .path = path,
        .base_path = base_path,
        .directory = getDirectory(base_path),
        .file_path = getFilePath(path),
        .resource_id = getResourceId(base_path),
        .extension = getExtension(path),
        .query = getQuery(path),
    };
}

/// No-op - no allocations currently performed.
pub fn deinit(self: *Self) void {
    _ = self;
}

// Extract `"/foo/bar/baz"` from:
// * `"/foo/bar/baz"`
// * `"/foo/bar/baz.html"`
// * `"/foo/bar/baz.html?qux=quux&corge=grault"`
fn getBasePath(path: []const u8) []const u8 {
    if (std.mem.indexOfScalar(u8, path, '?')) |query_index| {
        if (std.mem.lastIndexOfScalar(u8, path[0..query_index], '.')) |extension_index| {
            return path[0..extension_index];
        } else {
            return path[0..query_index];
        }
    } else if (std.mem.lastIndexOfScalar(u8, path, '.')) |extension_index| {
        return path[0..extension_index];
    } else {
        return path;
    }
}

// Extract `"/foo/bar"` from:
// * `"/foo/bar/baz"`
// Special case:
// * `"/"` returns `"/"`
pub fn getDirectory(base_path: []const u8) []const u8 {
    if (std.mem.eql(u8, base_path, "/")) return "/";

    if (std.mem.lastIndexOfScalar(u8, base_path, '/')) |index| {
        return base_path[0..index];
    } else {
        return "/";
    }
}

// Extract `"/foo/bar/baz.html"` from:
// * `"/foo/bar/baz.html"`
// * `"/foo/bar/baz.html?qux=quux&corge=grault"`
// Special case:
// * `"/foo/bar/baz"` returns `"/foo/bar/baz"`
fn getFilePath(path: []const u8) []const u8 {
    if (std.mem.indexOfScalar(u8, path, '?')) |query_index| {
        return path[0..query_index];
    } else {
        return path;
    }
}

// Extract `"baz"` from:
// * `"/foo/bar/baz"`
// * `"/baz"`
fn getResourceId(base_path: []const u8) []const u8 {
    var it = std.mem.splitBackwardsScalar(u8, base_path, '/');
    while (it.next()) |segment| return segment;
    return base_path;
}

// Extract `".html"` from:
// * `"/foo/bar/baz.html"`
// * `"/foo/bar/baz.html?qux=quux&corge=grault"`
fn getExtension(path: []const u8) ?[]const u8 {
    if (std.mem.indexOfScalar(u8, path, '?')) |query_index| {
        if (std.mem.lastIndexOfScalar(u8, path[0..query_index], '.')) |extension_index| {
            return path[extension_index..query_index];
        } else {
            return null;
        }
    } else if (std.mem.lastIndexOfScalar(u8, path, '.')) |extension_index| {
        return path[extension_index..];
    } else {
        return null;
    }
}

// Extract `"qux=quux&corge=grault"` from:
// * `"/foo/bar/baz.html?qux=quux&corge=grault"`
// * `"/foo/bar/baz?qux=quux&corge=grault"`
fn getQuery(path: []const u8) ?[]const u8 {
    if (std.mem.indexOfScalar(u8, path, '?')) |query_index| {
        if (path.len - 1 <= query_index) return null;
        return path[query_index + 1 ..];
    } else {
        return null;
    }
}

test ".base_path (with extension, with query)" {
    const path = Self.init("/foo/bar/baz.html?qux=quux&corge=grault");

    try std.testing.expectEqualStrings("/foo/bar/baz", path.base_path);
}

test ".base_path (with extension, without query)" {
    const path = Self.init("/foo/bar/baz.html");

    try std.testing.expectEqualStrings("/foo/bar/baz", path.base_path);
}

test ".base_path (without extension, without query)" {
    const path = Self.init("/foo/bar/baz");

    try std.testing.expectEqualStrings("/foo/bar/baz", path.base_path);
}

test ".directory (with extension, with query)" {
    const path = Self.init("/foo/bar/baz.html?qux=quux&corge=grault");

    try std.testing.expectEqualStrings("/foo/bar", path.directory);
}

test ".directory (with extension, without query)" {
    const path = Self.init("/foo/bar/baz.html");

    try std.testing.expectEqualStrings("/foo/bar", path.directory);
}

test ".directory (without extension, without query)" {
    const path = Self.init("/foo/bar/baz");

    try std.testing.expectEqualStrings("/foo/bar", path.directory);
}

test ".directory (without extension, without query, root path)" {
    const path = Self.init("/");

    try std.testing.expectEqualStrings("/", path.directory);
}

test ".resource_id (with extension, with query)" {
    const path = Self.init("/foo/bar/baz.html?qux=quux&corge=grault");

    try std.testing.expectEqualStrings("baz", path.resource_id);
}

test ".resource_id (with extension, without query)" {
    const path = Self.init("/foo/bar/baz.html");

    try std.testing.expectEqualStrings("baz", path.resource_id);
}

test ".resource_id (without extension, without query)" {
    const path = Self.init("/foo/bar/baz");

    try std.testing.expectEqualStrings("baz", path.resource_id);
}

test ".resource_id (without extension, without query, without base path)" {
    const path = Self.init("/baz");

    try std.testing.expectEqualStrings("baz", path.resource_id);
}

test ".extension (with query)" {
    const path = Self.init("/foo/bar/baz.html?qux=quux&corge=grault");

    try std.testing.expectEqualStrings(".html", path.extension.?);
}

test ".extension (without query)" {
    const path = Self.init("/foo/bar/baz.html");

    try std.testing.expectEqualStrings(".html", path.extension.?);
}

test ".extension (without extension)" {
    const path = Self.init("/foo/bar/baz");

    try std.testing.expect(path.extension == null);
}

test ".query (with extension, with query)" {
    const path = Self.init("/foo/bar/baz.html?qux=quux&corge=grault");

    try std.testing.expectEqualStrings(path.query.?, "qux=quux&corge=grault");
}

test ".query (without extension, with query)" {
    const path = Self.init("/foo/bar/baz?qux=quux&corge=grault");

    try std.testing.expectEqualStrings(path.query.?, "qux=quux&corge=grault");
}

test ".query (with extension, without query)" {
    const path = Self.init("/foo/bar/baz.json");

    try std.testing.expect(path.query == null);
}

test ".query (without extension, without query)" {
    const path = Self.init("/foo/bar/baz");

    try std.testing.expect(path.query == null);
}

test ".query (with empty query)" {
    const path = Self.init("/foo/bar/baz?");

    try std.testing.expect(path.query == null);
}

test ".file_path (with extension, with query)" {
    const path = Self.init("/foo/bar/baz.json?qux=quux&corge=grault");

    try std.testing.expectEqualStrings("/foo/bar/baz.json", path.file_path);
}

test ".file_path (with extension, without query)" {
    const path = Self.init("/foo/bar/baz.json");

    try std.testing.expectEqualStrings("/foo/bar/baz.json", path.file_path);
}

test ".file_path (without extension, without query)" {
    const path = Self.init("/foo/bar/baz");

    try std.testing.expectEqualStrings("/foo/bar/baz", path.file_path);
}

test ".file_path (without extension, with query)" {
    const path = Self.init("/foo/bar/baz?qux=quux&corge=grault");

    try std.testing.expectEqualStrings("/foo/bar/baz", path.file_path);
}
