const std = @import("std");
const builtin = @import("builtin");

pub const ErrorInfo = struct {
    stack_trace: ?*std.builtin.StackTrace = null,
    err: ?anyerror = null,
};

pub fn sourceLocations(
    allocator: std.mem.Allocator,
    debug_info: *std.debug.SelfInfo,
    stack_trace: *std.builtin.StackTrace,
) ![]const std.debug.SourceLocation {
    var source_locations = std.ArrayList(std.debug.SourceLocation).init(allocator);

    if (builtin.strip_debug_info) return error.MissingDebugInfo;

    var frame_index: usize = 0;
    var frames_left: usize = @min(stack_trace.index, stack_trace.instruction_addresses.len);

    while (frames_left != 0) : ({
        frames_left -= 1;
        frame_index = (frame_index + 1) % stack_trace.instruction_addresses.len;
    }) {
        const return_address = stack_trace.instruction_addresses[frame_index];
        const address = return_address - 1;
        const module = try debug_info.getModuleForAddress(address);
        const symbol_info = try module.getSymbolAtAddress(debug_info.allocator, address);

        if (symbol_info.source_location) |source_location| {
            try source_locations.append(source_location);
        }
    }

    return try source_locations.toOwnedSlice();
}

pub const HtmlStackTrace = struct {
    allocator: std.mem.Allocator,
    stack_trace: *std.builtin.StackTrace,

    pub fn format(self: HtmlStackTrace, _: anytype, _: anytype, writer: anytype) !void {
        const debug_info = try std.debug.getSelfDebugInfo();
        const source_locations = try sourceLocations(
            self.allocator,
            debug_info,
            self.stack_trace,
        );
        for (source_locations) |source_location| {
            defer debug_info.allocator.free(source_location.file_name);
            try writer.print(
                \\<div class='stack-source-line'>
                \\  <span class='file-name'>{s}:{d}</span>
                \\
            ,
                .{
                    source_location.file_name,
                    source_location.line,
                },
            );
            const surrounding_previous = try surroundingLinesFromFile(
                self.allocator,
                .previous,
                3,
                source_location.file_name,
                source_location.line,
            );
            const surrounding_next = try surroundingLinesFromFile(
                self.allocator,
                .next,
                3,
                source_location.file_name,
                source_location.line,
            );
            const target_source_line = try readLineFromFile(
                self.allocator,
                source_location.file_name,
                source_location.line,
            );

            for (surrounding_previous) |source_line| {
                try writer.print(surrounding_line_template, .{ source_line.line, source_line.content });
            }
            try writer.print(target_line_template, .{ target_source_line.line, target_source_line.content });
            for (surrounding_next) |source_line| {
                try writer.print(surrounding_line_template, .{ source_line.line, source_line.content });
            }

            try writer.print(
                \\</div>
                \\
            , .{});
        }
    }
};

const SourceLine = struct { content: []const u8, line: usize };

pub fn readLineFromFile(allocator: std.mem.Allocator, path: []const u8, line: usize) !SourceLine {
    const file = try std.fs.openFileAbsolute(path, .{});
    var buf: [std.heap.pageSize()]u8 = undefined;

    var count: usize = 1;
    var cursor: usize = 0;

    seek: {
        while (true) {
            const bytes_read = try file.readAll(buf[0..]);
            for (buf[0..bytes_read]) |char| {
                if (char == '\n') count += 1;
                cursor += 1;
                if (count == line) {
                    cursor += 1;
                    break :seek;
                }
            }
            if (bytes_read < buf.len) return error.EndOfFile;
        }
    }

    var size: usize = 0;
    try file.seekTo(cursor);
    read: {
        const bytes_read = try file.readAll(buf[0..]);
        if (std.mem.indexOf(u8, buf[0..bytes_read], "\n")) |index| {
            size += index;
            break :read;
        } else if (bytes_read < buf.len) {
            size += bytes_read;
            break :read;
        } else {
            while (true) {
                const more_bytes_read = try file.readAll(buf[0..]);
                if (std.mem.indexOf(u8, buf[0..more_bytes_read], "\n")) |index| {
                    size += index;
                    break :read;
                } else if (more_bytes_read < buf.len) {
                    size += more_bytes_read;
                    break :read;
                } else {
                    size += more_bytes_read;
                }
            }
        }
    }
    const line_content = try allocator.alloc(u8, size);
    try file.seekTo(cursor);
    const bytes_read = try file.readAll(line_content[0..]);

    std.debug.assert(bytes_read == size);

    return .{ .content = line_content[0..], .line = line };
}

fn surroundingLinesFromFile(
    allocator: std.mem.Allocator,
    context: enum { previous, next },
    desired_count: usize,
    path: []const u8,
    target_line: usize,
) ![]SourceLine {
    // This isn't very efficient but we only use it in debug mode so not a huge deal.
    const start = switch (context) {
        .previous => if (target_line > desired_count)
            target_line - desired_count
        else
            target_line,
        .next => target_line + 2,
    };

    var lines = std.ArrayList(SourceLine).init(allocator);

    switch (context) {
        .previous => {
            for (start..target_line) |line| {
                try lines.append(try readLineFromFile(allocator, path, line));
            }
        },
        .next => {
            for (0..desired_count, start..) |_, line| {
                try lines.append(try readLineFromFile(allocator, path, line));
            }
        },
    }

    return try lines.toOwnedSlice();
}

pub const console_template =
    \\<!DOCTYPE html>
    \\<html>
    \\  <head>
    \\    <style>
    \\{3s}
    \\    </style>
    \\  </head>
    \\  <body>
    \\    <h1>Encountered Error: {0s}</h1>
    \\    <div class="stack-trace">
    \\      {1}
    \\    </div>
    \\    <h2>Response Data</h2>
    \\    <div class="response-data">
    \\      <pre><code class="language-json">{2s}</code></pre>
    \\    </div>
    \\    <script src="/_jetzig_debug.js"></script>
    \\  </body>
    \\</html>
;

const surrounding_line_template =
    \\<div class='line-content surrounding'><pre class="line-number">{d: >4}</pre><pre><code class="language-zig">{s}</code></pre></div>
    \\
;
const target_line_template =
    \\<div class='line-content target'><pre class="line-number">{d: >4}</pre><pre><code class="language-zig">{s}</code></pre></div>
    \\
;
