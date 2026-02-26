const std = @import("std");

const Allocator = std.mem.Allocator;

/// An individual RSS feed item.
pub const Item = struct {
    title: []const u8,
    link: []const u8,
    description: []const u8,
    pub_date: ?[]const u8 = null,
    guid: ?[]const u8 = null,
    author: ?[]const u8 = null,
};

/// RSS 2.0 channel/feed definition.
pub const Channel = struct {
    title: []const u8,
    link: []const u8,
    description: []const u8,
    language: ?[]const u8 = null,
    pub_date: ?[]const u8 = null,
    last_build_date: ?[]const u8 = null,
    items: []const Item = &.{},
};

/// Generate a valid RSS 2.0 XML document from a channel definition.
pub fn generate(allocator: Allocator, channel: Channel) ![]const u8 {
    var buf = std.array_list.Managed(u8).init(allocator);
    errdefer buf.deinit();
    const writer = buf.writer();

    try writer.writeAll(
        \\<?xml version="1.0" encoding="UTF-8"?>
        \\<rss version="2.0">
        \\  <channel>
        \\
    );

    try writeTag(writer, "    ", "title", channel.title);
    try writeTag(writer, "    ", "link", channel.link);
    try writeTag(writer, "    ", "description", channel.description);
    if (channel.language) |v| try writeTag(writer, "    ", "language", v);
    if (channel.pub_date) |v| try writeTag(writer, "    ", "pubDate", v);
    if (channel.last_build_date) |v| try writeTag(writer, "    ", "lastBuildDate", v);

    for (channel.items) |item| {
        try writer.writeAll("    <item>\n");
        try writeTag(writer, "      ", "title", item.title);
        try writeTag(writer, "      ", "link", item.link);
        try writeTag(writer, "      ", "description", item.description);
        if (item.pub_date) |v| try writeTag(writer, "      ", "pubDate", v);
        if (item.guid) |v| try writeTag(writer, "      ", "guid", v);
        if (item.author) |v| try writeTag(writer, "      ", "author", v);
        try writer.writeAll("    </item>\n");
    }

    try writer.writeAll(
        \\  </channel>
        \\</rss>
        \\
    );

    return buf.toOwnedSlice();
}

fn writeTag(writer: anytype, indent: []const u8, tag: []const u8, value: []const u8) !void {
    try writer.writeAll(indent);
    try writer.writeByte('<');
    try writer.writeAll(tag);
    try writer.writeByte('>');
    try writeEscaped(writer, value);
    try writer.writeAll("</");
    try writer.writeAll(tag);
    try writer.writeAll(">\n");
}

fn writeEscaped(writer: anytype, input: []const u8) !void {
    for (input) |c| {
        switch (c) {
            '&' => try writer.writeAll("&amp;"),
            '<' => try writer.writeAll("&lt;"),
            '>' => try writer.writeAll("&gt;"),
            '"' => try writer.writeAll("&quot;"),
            '\'' => try writer.writeAll("&apos;"),
            else => try writer.writeByte(c),
        }
    }
}

test "generate minimal feed" {
    const channel = Channel{
        .title = "Test Blog",
        .link = "https://example.com",
        .description = "A test blog",
    };

    const xml = try generate(std.testing.allocator, channel);
    defer std.testing.allocator.free(xml);

    try std.testing.expect(std.mem.startsWith(u8, xml, "<?xml version=\"1.0\""));
    try std.testing.expect(std.mem.indexOf(u8, xml, "<title>Test Blog</title>") != null);
    try std.testing.expect(std.mem.indexOf(u8, xml, "<link>https://example.com</link>") != null);
    try std.testing.expect(std.mem.indexOf(u8, xml, "<description>A test blog</description>") != null);
    try std.testing.expect(std.mem.indexOf(u8, xml, "</rss>") != null);
}

test "generate feed with items" {
    const channel = Channel{
        .title = "My Blog",
        .link = "https://example.com",
        .description = "Latest posts",
        .language = "en-us",
        .items = &.{
            .{
                .title = "First Post",
                .link = "https://example.com/first",
                .description = "Hello world",
                .pub_date = "Mon, 01 Jan 2024 00:00:00 GMT",
                .guid = "https://example.com/first",
            },
            .{
                .title = "Second Post",
                .link = "https://example.com/second",
                .description = "Another post",
                .author = "author@example.com",
            },
        },
    };

    const xml = try generate(std.testing.allocator, channel);
    defer std.testing.allocator.free(xml);

    try std.testing.expect(std.mem.indexOf(u8, xml, "<language>en-us</language>") != null);
    try std.testing.expect(std.mem.indexOf(u8, xml, "<title>First Post</title>") != null);
    try std.testing.expect(std.mem.indexOf(u8, xml, "<guid>https://example.com/first</guid>") != null);
    try std.testing.expect(std.mem.indexOf(u8, xml, "<author>author@example.com</author>") != null);
    try std.testing.expect(std.mem.indexOf(u8, xml, "<title>Second Post</title>") != null);
}

test "XML escaping" {
    const channel = Channel{
        .title = "Blog & News <Daily>",
        .link = "https://example.com",
        .description = "Tom's \"great\" blog",
    };

    const xml = try generate(std.testing.allocator, channel);
    defer std.testing.allocator.free(xml);

    try std.testing.expect(std.mem.indexOf(u8, xml, "<title>Blog &amp; News &lt;Daily&gt;</title>") != null);
    try std.testing.expect(std.mem.indexOf(u8, xml, "Tom&apos;s &quot;great&quot; blog") != null);
}
