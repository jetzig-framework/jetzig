const std = @import("std");

const jetzig = @import("../../jetzig.zig");

data: *jetzig.data.Data,
status_code: jetzig.http.status_codes.StatusCode,
