const std = @import("std");
const jetzig = @import("../../jetzig.zig");

const Query = @This();

allocator: std.mem.Allocator,
query_string: []const u8,
query_items: std.ArrayList(QueryItem),
data: *jetzig.data.Data,

pub const QueryItem = struct {
    key: []const u8,
    value: ?[]const u8,
};

pub fn init(allocator: std.mem.Allocator, query_string: []const u8, data: *jetzig.data.Data) Query {
    return .{
        .allocator = allocator,
        .query_string = query_string,
        .query_items = std.ArrayList(QueryItem).init(allocator),
        .data = data,
    };
}

pub fn deinit(self: *Query) void {
    self.query_items.deinit();
    self.data.deinit();
}

pub fn parse(self: *Query) !void {
    var pairs_it = std.mem.splitScalar(u8, self.query_string, '&');

    while (pairs_it.next()) |pair| {
        var key_value_it = std.mem.splitScalar(u8, pair, '=');
        var count: u2 = 0;
        var maybe_key: ?[]const u8 = null;
        var value: ?[]const u8 = null;

        while (key_value_it.next()) |key_or_value| {
            switch (count) {
                0 => maybe_key = key_or_value,
                1 => value = key_or_value,
                else => return error.JetzigQueryParseError,
            }
            count += 1;
        }
        if (maybe_key) |key| {
            if (key.len > 0) {
                try self.query_items.append(.{ .key = key, .value = value });
            }
        }
    }

    var params = try self.data.object();
    for (self.query_items.items) |item| {
        // TODO: Allow nested array/mapping params (`foo[bar][baz]=abc`)
        if (arrayParam(item.key)) |key| {
            if (params.get(key)) |value| {
                switch (value.*) {
                    .array => try value.array.append(self.dataValue(item.value)),
                    else => return error.JetzigQueryParseError,
                }
            } else {
                var array = try jetzig.zmpl.Data.createArray(self.data.allocator);
                try array.append(self.dataValue(item.value));
                try params.put(key, array);
            }
        } else if (mappingParam(item.key)) |mapping| {
            if (params.get(mapping.key)) |value| {
                switch (value.*) {
                    .object => try value.object.put(mapping.field, self.dataValue(item.value)),
                    else => return error.JetzigQueryParseError,
                }
            } else {
                var object = try jetzig.zmpl.Data.createObject(self.data.allocator);
                try object.put(mapping.field, self.dataValue(item.value));
                try params.put(mapping.key, object);
            }
        } else {
            try params.put(item.key, self.dataValue(item.value));
        }
    }
}

fn arrayParam(key: []const u8) ?[]const u8 {
    if (key.len >= 3 and std.mem.eql(u8, key[key.len - 2 ..], "[]")) {
        return key[0 .. key.len - 2];
    } else {
        return null;
    }
}

fn mappingParam(input: []const u8) ?struct { key: []const u8, field: []const u8 } {
    if (input.len < 4) return null; // Must be at least `a[b]`

    const open = std.mem.indexOfScalar(u8, input, '[');
    const close = std.mem.lastIndexOfScalar(u8, input, ']');
    if (open == null or close == null) return null;

    const open_index = open.?;
    const close_index = close.?;
    if (close_index < open_index) return null;

    return .{
        .key = input[0..open_index],
        .field = input[open_index + 1 .. close_index],
    };
}

fn dataValue(self: Query, value: ?[]const u8) *jetzig.data.Data.Value {
    if (value) |item_value| {
        const duped = self.data.allocator.dupe(u8, item_value) catch @panic("OOM");
        return self.data.string(uriDecode(duped));
    } else {
        return jetzig.zmpl.Data._null(self.data.allocator);
    }
}

fn uriDecode(input: []u8) []const u8 {
    std.mem.replaceScalar(u8, input, '+', ' ');
    return std.Uri.percentDecodeInPlace(input);
}

test "simple query string" {
    const allocator = std.testing.allocator;
    const query_string = "foo=bar&baz=qux";
    var data = jetzig.data.Data.init(allocator);

    var query = init(allocator, query_string, &data);
    defer query.deinit();

    try query.parse();
    try std.testing.expectEqualStrings((data.get("foo")).?.string.value, "bar");
    try std.testing.expectEqualStrings((data.get("baz")).?.string.value, "qux");
}

test "query string with array values" {
    const allocator = std.testing.allocator;
    const query_string = "foo[]=bar&foo[]=baz";
    var data = jetzig.data.Data.init(allocator);

    var query = init(allocator, query_string, &data);
    defer query.deinit();

    try query.parse();

    const value = data.get("foo").?;
    switch (value.*) {
        .array => |array| {
            try std.testing.expectEqualStrings(array.get(0).?.string.value, "bar");
            try std.testing.expectEqualStrings(array.get(1).?.string.value, "baz");
        },
        else => unreachable,
    }
}

test "query string with mapping values" {
    const allocator = std.testing.allocator;
    const query_string = "foo[bar]=baz&foo[qux]=quux";
    var data = jetzig.data.Data.init(allocator);

    var query = init(allocator, query_string, &data);
    defer query.deinit();

    try query.parse();

    const value = data.get("foo").?;
    switch (value.*) {
        .object => |object| {
            try std.testing.expectEqualStrings(object.get("bar").?.string.value, "baz");
            try std.testing.expectEqualStrings(object.get("qux").?.string.value, "quux");
        },
        else => unreachable,
    }
}

test "query string with param without value" {
    const allocator = std.testing.allocator;
    const query_string = "foo&bar";
    var data = jetzig.data.Data.init(allocator);

    var query = init(allocator, query_string, &data);
    defer query.deinit();

    try query.parse();

    const foo = data.get("foo").?;
    try switch (foo.*) {
        .null => {},
        else => std.testing.expect(false),
    };

    const bar = data.get("bar").?;
    try switch (bar.*) {
        .null => {},
        else => std.testing.expect(false),
    };
}

test "query string with encoded characters" {
    const allocator = std.testing.allocator;
    const query_string = "foo=bar+baz+qux&bar=hello%20%21%20how%20are%20you%20doing%20%3F%3F%3F";
    var data = jetzig.data.Data.init(allocator);

    var query = init(allocator, query_string, &data);
    defer query.deinit();

    try query.parse();
    try std.testing.expectEqualStrings(
        "bar baz qux",
        (data.getT(.string, "foo")).?,
    );
    try std.testing.expectEqualStrings(
        "hello ! how are you doing ???",
        (data.getT(.string, "bar")).?,
    );
}
