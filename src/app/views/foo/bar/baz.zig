const std = @import("std");

const root = @import("root");

pub fn index(request: *root.jetzig.http.Request) anyerror!root.jetzig.views.View {
    var data = request.data();
    var object = try data.object();

    try object.add("message", data.string("hello there"));
    try object.add("foo", data.string("foo lookup"));
    try object.add("bar", data.string("bar lookup"));

    return request.render(.ok);
}

pub fn get(id: []const u8, request: *root.jetzig.http.Request) anyerror!root.jetzig.views.View {
    var data = request.data();
    var object = try data.object();

    try object.add("message", data.string("hello there"));
    try object.add("other_message", data.string("hello again"));
    try object.add("an_integer", data.integer(10));
    try object.add("a_float", data.float(1.345));
    try object.add("a_boolean", data.boolean(true));
    try object.add("Null", data.Null);
    try object.add("a_random_integer", data.integer(std.crypto.random.int(u8)));
    try object.add("resource_id", data.string(id));

    var nested_object = try data.object();
    try nested_object.add("nested key", data.string("nested value"));
    try object.add("other_message", nested_object.*);

    return request.render(.ok);
}

pub fn patch(id: []const u8, request: *root.jetzig.http.Request) anyerror!root.jetzig.views.View {
    var data = request.data();
    var object = try data.object();

    const integer = std.crypto.random.int(u8);

    try object.add("message", data.string("hello there"));
    try object.add("other_message", data.string("hello again"));
    try object.add("other_message", data.integer(integer));
    try object.add("id", data.string(id));

    return request.render(.ok);
}
