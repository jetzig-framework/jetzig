const std = @import("std");

const Self = @This();

timestamp: i64,

const constants = struct {
    pub const seconds_in_day: i64 = 60 * 60 * 24;
    pub const seconds_in_year: i64 = 60 * 60 * 24 * 365.25;
    pub const months: [12]i64 = .{ 31, 28, 31, 30, 31, 30, 31, 31, 30, 31, 30, 31 };
    pub const epoch_year: i64 = 1970;
};

pub fn init(timestamp: i64) Self {
    return .{ .timestamp = timestamp };
}

pub fn iso8601(self: *const Self, buf: *[256]u8) ![]const u8 {
    const u32_year: u32 = @intCast(self.year());
    const u32_month: u32 = @intCast(self.month());
    const u32_day_of_month: u32 = @intCast(self.dayOfMonth());
    const u32_hour: u32 = @intCast(self.hour());
    const u32_minute: u32 = @intCast(self.minute());
    const u32_second: u32 = @intCast(self.second());
    return try std.fmt.bufPrint(buf, "{d:0>4}-{d:0>2}-{d:0>2}T{d:0>2}:{d:0>2}:{d:0>2}", .{
        u32_year,
        u32_month,
        u32_day_of_month,
        u32_hour,
        u32_minute,
        u32_second,
    });
}

pub fn year(self: *const Self) i64 {
    return constants.epoch_year + @divTrunc(self.timestamp, constants.seconds_in_year);
}

pub fn month(self: *const Self) usize {
    const day_of_year = self.dayOfYear();
    var total_days: i64 = 0;
    for (constants.months, 1..) |days, index| {
        total_days += days;
        if (day_of_year <= total_days) return index;
    }
    unreachable;
}

pub fn dayOfYear(self: *const Self) i64 {
    return @divTrunc(self.daysSinceEpoch(), constants.seconds_in_day);
}

pub fn dayOfMonth(self: *const Self) i64 {
    const day_of_year = self.dayOfYear();
    var total_days: i64 = 0;
    for (constants.months) |days| {
        total_days += days;
        if (day_of_year <= total_days) return days + (day_of_year - total_days) + 1;
    }
    unreachable;
}

pub fn daysSinceEpoch(self: *const Self) i64 {
    return self.timestamp - ((self.year() - constants.epoch_year) * constants.seconds_in_year);
}

pub fn dayOfWeek(self: *const Self) i64 {
    const currentDay = std.math.mod(i64, self.daysSinceEpoch(), 7) catch unreachable;
    return std.math.mod(i64, currentDay + 4, 7) catch unreachable;
}

pub fn hour(self: *const Self) i64 {
    const seconds = std.math.mod(i64, self.timestamp, constants.seconds_in_day) catch unreachable;
    return @divTrunc(seconds, @as(i64, 60 * 60));
}

pub fn minute(self: *const Self) i64 {
    const seconds = std.math.mod(i64, self.timestamp, @as(i64, 60 * 60)) catch unreachable;
    return @divTrunc(seconds, @as(i64, 60));
}

pub fn second(self: *const Self) i64 {
    return std.math.mod(i64, self.timestamp, @as(i64, 60)) catch unreachable;
}
