/// Abstraction of the path component of a URI.
/// Provides access to:
/// * Unaltered original path
/// * Base path (without extension and query string)
/// * Directory (parent path from base path)
/// * Resource ID (final component of base path)
/// * Extension (".json", ".html", etc.)
/// * Query (everything after first "?" character)
const std = @import("std");
const jetzig = @import("../../jetzig.zig");

path: []const u8,
base_path: []const u8,
directory: []const u8,
file_path: []const u8,
view_name: []const u8,
resource_id: []const u8,
extension: ?[]const u8,
query: ?[]const u8,
method: ?jetzig.Request.Method,

const Path = @This();

/// Initialize a new HTTP Path.
pub fn init(path: []const u8) Path {
    const base_path = getBasePath(path);

    return .{
        .path = path,
        .base_path = base_path,
        .directory = getDirectory(base_path),
        .file_path = getFilePath(path),
        .view_name = std.mem.trimLeft(u8, base_path, "/"),
        .resource_id = getResourceId(base_path),
        .extension = getExtension(path),
        .query = getQuery(path),
        .method = getMethod(path),
    };
}

/// No-op - no allocations currently performed.
pub fn deinit(self: *Path) void {
    _ = self;
}

/// For a given route with a possible `:id` placeholder, return the matching URL segment for that
/// placeholder. e.g. route with path `/foo/:id/bar` and request path `/foo/1234/bar` returns
/// `"1234"`.
pub fn resourceId(self: Path, route: jetzig.views.Route) []const u8 {
    var route_uri_path_it = std.mem.splitScalar(u8, route.uri_path, '/');
    var base_path_it = std.mem.splitScalar(u8, self.base_path, '/');

    while (route_uri_path_it.next()) |route_uri_path_segment| {
        const base_path_segment = base_path_it.next() orelse return self.resource_id;
        if (std.mem.startsWith(u8, route_uri_path_segment, ":")) return base_path_segment;
    }

    return self.resource_id;
}

pub fn resourceArgs(self: Path, route: jetzig.views.Route, allocator: std.mem.Allocator) ![]const []const u8 {
    var args = std.ArrayList([]const u8).init(allocator);
    var route_uri_path_it = std.mem.splitScalar(u8, route.uri_path, '/');
    var path_it = std.mem.splitScalar(u8, self.base_path, '/');

    var matched = false;

    while (path_it.next()) |path_segment| {
        const route_uri_path_segment = route_uri_path_it.next();
        if (!matched and
            route_uri_path_segment != null and
            std.mem.startsWith(u8, route_uri_path_segment.?, ":") and
            std.mem.endsWith(u8, route_uri_path_segment.?, "*"))
        {
            matched = true;
        }
        if (matched) {
            try args.append(path_segment);
        }
    }

    return try args.toOwnedSlice();
}

// Extract `"/foo/bar/baz"` from:
// * `"/foo/bar/baz"`
// * `"/foo/bar/baz.html"`
// * `"/foo/bar/baz.html?qux=quux&corge=grault"`
// * `"/foo/bar/baz/_PATCH"`
fn getBasePath(path: []const u8) []const u8 {
    const base = if (std.mem.indexOfScalar(u8, path, '?')) |query_index| blk: {
        if (std.mem.lastIndexOfScalar(u8, path[0..query_index], '.')) |extension_index| {
            break :blk path[0..extension_index];
        } else {
            break :blk path[0..query_index];
        }
    } else if (std.mem.lastIndexOfScalar(u8, path, '.')) |extension_index| blk: {
        break :blk if (isRootPath(path[0..extension_index]))
            path[0..extension_index]
        else
            std.mem.trimRight(u8, path[0..extension_index], "/");
    } else blk: {
        break :blk if (isRootPath(path)) path else std.mem.trimRight(u8, path, "/");
    };

    if (std.mem.lastIndexOfScalar(u8, base, '/')) |last_index| {
        if (std.mem.startsWith(u8, base[last_index..], "/_")) {
            return base[0..last_index];
        } else {
            return base;
        }
    } else return base;
}

fn getMethod(path: []const u8) ?jetzig.Request.Method {
    var it = std.mem.splitBackwardsScalar(u8, path, '/');
    const last_segment = it.next() orelse return null;
    inline for (comptime std.enums.values(jetzig.Request.Method)) |method| {
        if (std.mem.startsWith(u8, last_segment, "_" ++ @tagName(method))) {
            return method;
        }
    }
    return null;
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

    if (std.mem.endsWith(u8, base_path, "/edit")) _ = it.next();

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

// Extract `/foo/bar/edit` from `/foo/bar/1/edit`
// Extract `/foo/bar` from `/foo/bar/1`
pub fn actionPath(self: Path, buf: *[2048]u8) []const u8 {
    if (self.path.len > 2048) return self.path; // Should never happen but we don't want to panic or overflow.

    if (std.mem.endsWith(u8, self.path, "/edit")) {
        var it = std.mem.tokenizeScalar(u8, self.path, '/');
        var cursor: usize = 0;
        const count = std.mem.count(u8, self.path, "/");
        var index: usize = 0;

        buf[0] = '/';
        cursor += 1;

        while (it.next()) |segment| : (index += 1) {
            if (index + 2 == count) continue; // Skip ID - we special-case this in `resourceId`
            @memcpy(buf[cursor .. cursor + segment.len], segment);
            cursor += segment.len;
            if (index + 1 < count) {
                @memcpy(buf[cursor .. cursor + 1], "/");
                cursor += 1;
            }
        }

        return buf[0..cursor];
    } else return self.path;
}

inline fn isRootPath(path: []const u8) bool {
    return std.mem.eql(u8, path, "/");
}

test ".base_path (with extension, with query)" {
    const path = Path.init("/foo/bar/baz.html?qux=quux&corge=grault");

    try std.testing.expectEqualStrings("/foo/bar/baz", path.base_path);
}

test ".base_path (with extension, without query)" {
    const path = Path.init("/foo/bar/baz.html");

    try std.testing.expectEqualStrings("/foo/bar/baz", path.base_path);
}

test ".base_path (without extension, without query)" {
    const path = Path.init("/foo/bar/baz");

    try std.testing.expectEqualStrings("/foo/bar/baz", path.base_path);
}

test ".base_path (with trailing slash)" {
    const path = Path.init("/foo/bar/");

    try std.testing.expectEqualStrings("/foo/bar", path.base_path);
}

test ".base_path (root path)" {
    const path = Path.init("/");

    try std.testing.expectEqualStrings("/", path.base_path);
}

test ".base_path (root path with extension)" {
    const path = Path.init("/.json");

    try std.testing.expectEqualStrings("/", path.base_path);
    try std.testing.expectEqualStrings(".json", path.extension.?);
}

test ".directory (with extension, with query)" {
    const path = Path.init("/foo/bar/baz.html?qux=quux&corge=grault");

    try std.testing.expectEqualStrings("/foo/bar", path.directory);
}

test ".directory (with extension, without query)" {
    const path = Path.init("/foo/bar/baz.html");

    try std.testing.expectEqualStrings("/foo/bar", path.directory);
}

test ".directory (without extension, without query)" {
    const path = Path.init("/foo/bar/baz");

    try std.testing.expectEqualStrings("/foo/bar", path.directory);
}

test ".directory (without extension, without query, root path)" {
    const path = Path.init("/");

    try std.testing.expectEqualStrings("/", path.directory);
}

test ".resource_id (with extension, with query)" {
    const path = Path.init("/foo/bar/baz.html?qux=quux&corge=grault");

    try std.testing.expectEqualStrings("baz", path.resource_id);
}

test ".resource_id (with extension, without query)" {
    const path = Path.init("/foo/bar/baz.html");

    try std.testing.expectEqualStrings("baz", path.resource_id);
}

test ".resource_id (without extension, without query)" {
    const path = Path.init("/foo/bar/baz");

    try std.testing.expectEqualStrings("baz", path.resource_id);
}

test ".resource_id (without extension, without query, without base path)" {
    const path = Path.init("/baz");

    try std.testing.expectEqualStrings("baz", path.resource_id);
}

test ".resource_id (with trailing slash)" {
    const path = Path.init("/foo/bar/");

    try std.testing.expectEqualStrings("bar", path.resource_id);
}

test ".extension (with query)" {
    const path = Path.init("/foo/bar/baz.html?qux=quux&corge=grault");

    try std.testing.expectEqualStrings(".html", path.extension.?);
}

test ".extension (without query)" {
    const path = Path.init("/foo/bar/baz.html");

    try std.testing.expectEqualStrings(".html", path.extension.?);
}

test ".extension (without extension)" {
    const path = Path.init("/foo/bar/baz");

    try std.testing.expect(path.extension == null);
}

test ".query (with extension, with query)" {
    const path = Path.init("/foo/bar/baz.html?qux=quux&corge=grault");

    try std.testing.expectEqualStrings(path.query.?, "qux=quux&corge=grault");
}

test ".query (without extension, with query)" {
    const path = Path.init("/foo/bar/baz?qux=quux&corge=grault");

    try std.testing.expectEqualStrings(path.query.?, "qux=quux&corge=grault");
}

test ".query (with extension, without query)" {
    const path = Path.init("/foo/bar/baz.json");

    try std.testing.expect(path.query == null);
}

test ".query (without extension, without query)" {
    const path = Path.init("/foo/bar/baz");

    try std.testing.expect(path.query == null);
}

test ".query (with empty query)" {
    const path = Path.init("/foo/bar/baz?");

    try std.testing.expect(path.query == null);
}

test ".file_path (with extension, with query)" {
    const path = Path.init("/foo/bar/baz.json?qux=quux&corge=grault");

    try std.testing.expectEqualStrings("/foo/bar/baz.json", path.file_path);
}

test ".file_path (with extension, without query)" {
    const path = Path.init("/foo/bar/baz.json");

    try std.testing.expectEqualStrings("/foo/bar/baz.json", path.file_path);
}

test ".file_path (without extension, without query)" {
    const path = Path.init("/foo/bar/baz");

    try std.testing.expectEqualStrings("/foo/bar/baz", path.file_path);
}

test ".file_path (without extension, with query)" {
    const path = Path.init("/foo/bar/baz?qux=quux&corge=grault");

    try std.testing.expectEqualStrings("/foo/bar/baz", path.file_path);
}

test ".resource_id (/foo/bar/123/edit)" {
    const path = Path.init("/foo/bar/123/edit");

    try std.testing.expectEqualStrings("123", path.resource_id);
}

test ".actionPath (/foo/bar/123/edit)" {
    var buf: [2048]u8 = undefined;
    const path = Path.init("/foo/bar/123/edit").actionPath(&buf);

    try std.testing.expectEqualStrings("/foo/bar/edit", path);
}

test ".actionPath (/foo/bar)" {
    var buf: [2048]u8 = undefined;
    const path = Path.init("/foo/bar").actionPath(&buf);

    try std.testing.expectEqualStrings("/foo/bar", path);
}

test ".base_path (/foo/bar/1/_PATCH" {
    const path = Path.init("/foo/bar/1/_PATCH");
    try std.testing.expectEqualStrings("/foo/bar/1", path.base_path);
    try std.testing.expectEqualStrings("1", path.resource_id);
}

test ".method (/foo/bar/1/_PATCH" {
    const path = Path.init("/foo/bar/1/_PATCH");
    try std.testing.expect(path.method.? == .PATCH);
}

test ".view_name" {
    const path = Path.init("/foo/bar");
    try std.testing.expectEqualStrings("foo/bar", path.view_name);
}
