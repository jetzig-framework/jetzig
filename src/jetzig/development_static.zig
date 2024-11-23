pub const compiled = [_]Compiled{};

const StaticOutput = struct {
    json: ?[]const u8 = null,
    html: ?[]const u8 = null,
    params: ?[]const u8,
};

const Compiled = struct {
    route_id: []const u8,
    output: StaticOutput,
};
