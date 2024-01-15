const std = @import("std");

const root = @import("root");
const Request = root.jetzig.http.Request;
const Data = root.jetzig.data.Data;
const View = root.jetzig.views.View;

pub fn index(request: *Request, data: *Data) anyerror!View {
    var object = try data.object();

    try request.session.put("foo", data.string("bar"));
    try object.put("message", data.string("hello there"));
    try object.put("foo", data.string("foo lookup"));
    try object.put("bar", data.string("bar lookup"));
    try object.put("session_value", (try request.session.get("foo")).?);

    return request.render(.ok);
}

pub fn get(id: []const u8, request: *Request, data: *Data) anyerror!View {
    var object = try data.object();

    try request.session.put("foo", data.string("bar"));
    try object.put("session_value", (try request.session.get("foo")).?);

    try object.put("message", data.string("hello there"));
    try object.put("other_message", data.string("hello again"));
    try object.put("an_integer", data.integer(10));
    try object.put("a_float", data.float(1.345));
    try object.put("a_boolean", data.boolean(true));
    try object.put("Null", data.Null);
    try object.put("a_random_integer", data.integer(std.crypto.random.int(u8)));
    try object.put("resource_id", data.string(id));

    var nested_object = try data.object();
    try nested_object.put("nested key", data.string("nested value"));
    try object.put("other_message", nested_object.*);

    return request.render(.ok);
}

pub fn patch(id: []const u8, request: *Request, data: *Data) anyerror!View {
    var object = try data.object();

    const integer = std.crypto.random.int(u8);

    try object.put("message", data.string("hello there"));
    try object.put("other_message", data.string("hello again"));
    try object.put("other_message", data.integer(integer));
    try object.put("id", data.string(id));

    return request.render(.ok);
}
