const std = @import("std");
const jetzig = @import("jetzig");

pub fn index(request: *jetzig.Request) !jetzig.View {
    const channel = jetzig.Rss.Channel{
        .title = "Jetzig Demo Blog",
        .link = "https://demo.jetzig.dev",
        .description = "Example RSS feed powered by Jetzig",
        .language = "en-us",
        .items = &.{
            .{
                .title = "Getting Started with Jetzig",
                .link = "https://demo.jetzig.dev/blog/getting-started",
                .description = "Learn how to build web applications with Jetzig.",
                .pub_date = "Mon, 01 Jan 2024 00:00:00 GMT",
                .guid = "https://demo.jetzig.dev/blog/getting-started",
            },
            .{
                .title = "Using RSS Feeds",
                .link = "https://demo.jetzig.dev/blog/rss-feeds",
                .description = "How to add RSS feed support to your Jetzig app.",
                .pub_date = "Tue, 02 Jan 2024 00:00:00 GMT",
                .guid = "https://demo.jetzig.dev/blog/rss-feeds",
            },
        },
    };

    const xml = try jetzig.Rss.generate(request.allocator, channel);
    request.response.content_type = "application/rss+xml";
    return request.renderText(xml, .ok);
}

test "index returns RSS feed" {
    var app = try jetzig.testing.app(std.testing.allocator, @import("routes"));
    defer app.deinit();

    const response = try app.request(.GET, "/feed", .{});
    try response.expectStatus(.ok);
    try response.expectBodyContains("<?xml version=\"1.0\"");
    try response.expectBodyContains("<rss version=\"2.0\">");
    try response.expectBodyContains("<title>Jetzig Demo Blog</title>");
    try response.expectBodyContains("<title>Getting Started with Jetzig</title>");
    try response.expectHeader("content-type", "application/rss+xml");
}
