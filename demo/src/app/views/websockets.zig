const std = @import("std");
const jetzig = @import("jetzig");

pub fn index(request: *jetzig.Request, data: *jetzig.Data) !jetzig.View {
    _ = data;
    return request.render(.ok);
}

pub fn get(id: []const u8, request: *jetzig.Request, data: *jetzig.Data) !jetzig.View {
    _ = data;
    _ = id;
    return request.render(.ok);
}

pub fn post(request: *jetzig.Request, data: *jetzig.Data) !jetzig.View {
    _ = data;
    return request.render(.created);
}

pub fn put(id: []const u8, request: *jetzig.Request, data: *jetzig.Data) !jetzig.View {
    _ = data;
    _ = id;
    return request.render(.ok);
}

pub fn patch(id: []const u8, request: *jetzig.Request, data: *jetzig.Data) !jetzig.View {
    _ = data;
    _ = id;
    return request.render(.ok);
}

pub fn delete(id: []const u8, request: *jetzig.Request, data: *jetzig.Data) !jetzig.View {
    _ = data;
    _ = id;
    return request.render(.ok);
}

pub fn receiveMessage(message: jetzig.channels.Message) !void {
    const data = try message.data();
    if (data.getT(.string, "toggle")) |toggle| {
        if (message.channel.get("cells")) |cells| {
            const is_taken = cells.getT(.boolean, toggle);
            if (is_taken == null or is_taken.? == false) {
                try cells.put(toggle, true);
            }
        } else {
            var cells = try message.channel.put("cells", .object);
            for (1..10) |cell| {
                var buf: [1]u8 = undefined;
                const key = try std.fmt.bufPrint(&buf, "{d}", .{cell});
                try cells.put(key, std.mem.eql(u8, key, toggle));
            }
        }
        try message.channel.sync();
    } else {
        var cells = try message.channel.put("cells", .object);
        for (1..10) |cell| {
            var buf: [1]u8 = undefined;
            const key = try std.fmt.bufPrint(&buf, "{d}", .{cell});
            try cells.put(key, false);
        }
        try message.channel.sync();
    }
    // try message.channel.publish("hello");
}

test "index" {
    var app = try jetzig.testing.app(std.testing.allocator, @import("routes"));
    defer app.deinit();

    const response = try app.request(.GET, "/websockets", .{});
    try response.expectStatus(.ok);
}

test "get" {
    var app = try jetzig.testing.app(std.testing.allocator, @import("routes"));
    defer app.deinit();

    const response = try app.request(.GET, "/websockets/example-id", .{});
    try response.expectStatus(.ok);
}

test "post" {
    var app = try jetzig.testing.app(std.testing.allocator, @import("routes"));
    defer app.deinit();

    const response = try app.request(.POST, "/websockets", .{});
    try response.expectStatus(.created);
}

test "put" {
    var app = try jetzig.testing.app(std.testing.allocator, @import("routes"));
    defer app.deinit();

    const response = try app.request(.PUT, "/websockets/example-id", .{});
    try response.expectStatus(.ok);
}

test "patch" {
    var app = try jetzig.testing.app(std.testing.allocator, @import("routes"));
    defer app.deinit();

    const response = try app.request(.PATCH, "/websockets/example-id", .{});
    try response.expectStatus(.ok);
}

test "delete" {
    var app = try jetzig.testing.app(std.testing.allocator, @import("routes"));
    defer app.deinit();

    const response = try app.request(.DELETE, "/websockets/example-id", .{});
    try response.expectStatus(.ok);
}
