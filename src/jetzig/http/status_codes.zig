const std = @import("std");

const jetzig = @import("../../jetzig.zig");

pub const StatusCode = enum {
    @"continue",
    switching_protocols,
    processing,
    early_hints,
    ok,
    created,
    accepted,
    non_authoritative_info,
    no_content,
    reset_content,
    partial_content,
    multi_status,
    already_reported,
    im_used,
    multiple_choice,
    moved_permanently,
    found,
    see_other,
    not_modified,
    use_proxy,
    temporary_redirect,
    permanent_redirect,
    bad_request,
    unauthorized,
    payment_required,
    forbidden,
    not_found,
    method_not_allowed,
    not_acceptable,
    proxy_auth_required,
    request_timeout,
    conflict,
    gone,
    length_required,
    precondition_failed,
    payload_too_large,
    uri_too_long,
    unsupported_media_type,
    range_not_satisfiable,
    expectation_failed,
    misdirected_request,
    unprocessable_entity,
    locked,
    failed_dependency,
    too_early,
    upgrade_required,
    precondition_required,
    too_many_requests,
    request_header_fields_too_large,
    unavailable_for_legal_reasons,
    internal_server_error,
    not_implemented,
    bad_gateway,
    service_unavailable,
    gateway_timeout,
    http_version_not_supported,
    variant_also_negotiates,
    insufficient_storage,
    loop_detected,
    not_extended,
    network_authentication_required,
};

pub fn StatusCodeType(comptime code: []const u8, comptime message: []const u8) type {
    return struct {
        code: []const u8 = code,
        message: []const u8 = message,

        const Self = @This();

        pub fn format(self: Self, colorized: bool) []const u8 {
            _ = self;
            const full_message = code ++ " " ++ message;

            if (!colorized) return full_message;

            if (std.mem.startsWith(u8, code, "2")) {
                return jetzig.colors.green(full_message);
            } else if (std.mem.startsWith(u8, code, "3")) {
                return jetzig.colors.blue(full_message);
            } else if (std.mem.startsWith(u8, code, "4")) {
                return jetzig.colors.yellow(full_message);
            } else if (std.mem.startsWith(u8, code, "5")) {
                return jetzig.colors.red(full_message);
            } else {
                return full_message;
            }
        }
    };
}

pub const TaggedStatusCode = union(StatusCode) {
    @"continue": StatusCodeType("100", "Continue"),
    switching_protocols: StatusCodeType("101", "Switching Protocols"),
    processing: StatusCodeType("102", "Processing"),
    early_hints: StatusCodeType("103", "Early Hints"),
    ok: StatusCodeType("200", "OK"),
    created: StatusCodeType("201", "Created"),
    accepted: StatusCodeType("202", "Accepted"),
    non_authoritative_info: StatusCodeType("203", "Non Authoritative Information"),
    no_content: StatusCodeType("204", "No Content"),
    reset_content: StatusCodeType("205", "Reset Content"),
    partial_content: StatusCodeType("206", "Partial Content"),
    multi_status: StatusCodeType("207", "Multi Status"),
    already_reported: StatusCodeType("208", "Already Reported"),
    im_used: StatusCodeType("226", "IM Used"),
    multiple_choice: StatusCodeType("300", "Multiple Choices"),
    moved_permanently: StatusCodeType("301", "Moved Permanently"),
    found: StatusCodeType("302", "Found"),
    see_other: StatusCodeType("303", "See Other"),
    not_modified: StatusCodeType("304", "Not Modified"),
    use_proxy: StatusCodeType("305", "Use Proxy"),
    temporary_redirect: StatusCodeType("307", "Temporary Redirect"),
    permanent_redirect: StatusCodeType("308", "Permanent Redirect"),
    bad_request: StatusCodeType("400", "Bad Request"),
    unauthorized: StatusCodeType("401", "Unauthorized"),
    payment_required: StatusCodeType("402", "Payment Required"),
    forbidden: StatusCodeType("403", "Forbidden"),
    not_found: StatusCodeType("404", "Not Found"),
    method_not_allowed: StatusCodeType("405", "Method Not Allowed"),
    not_acceptable: StatusCodeType("406", "Not Acceptable"),
    proxy_auth_required: StatusCodeType("407", "Proxy Authentication Required"),
    request_timeout: StatusCodeType("408", "Request Timeout"),
    conflict: StatusCodeType("409", "Conflict"),
    gone: StatusCodeType("410", "Gone"),
    length_required: StatusCodeType("411", "Length Required"),
    precondition_failed: StatusCodeType("412", "Precondition Failed"),
    payload_too_large: StatusCodeType("413", "Payload Too Large"),
    uri_too_long: StatusCodeType("414", "Request Uri Too Long"),
    unsupported_media_type: StatusCodeType("415", "Unsupported Media Type"),
    range_not_satisfiable: StatusCodeType("416", "Requested Range Not Satisfiable"),
    expectation_failed: StatusCodeType("417", "Expectation Failed"),
    misdirected_request: StatusCodeType("421", "Misdirected Request"),
    unprocessable_entity: StatusCodeType("422", "Unprocessable Entity"),
    locked: StatusCodeType("423", "Locked"),
    failed_dependency: StatusCodeType("424", "Failed Dependency"),
    too_early: StatusCodeType("425", "Too Early"),
    upgrade_required: StatusCodeType("426", "Upgrade Required"),
    precondition_required: StatusCodeType("428", "Precondition Required"),
    too_many_requests: StatusCodeType("429", "Too Many Requests"),
    request_header_fields_too_large: StatusCodeType("431", "Request Header Fields Too Large"),
    unavailable_for_legal_reasons: StatusCodeType("451", "Unavailable for Legal Reasons"),
    internal_server_error: StatusCodeType("500", "Internal Server Error"),
    not_implemented: StatusCodeType("501", "Not Implemented"),
    bad_gateway: StatusCodeType("502", "Bad Gateway"),
    service_unavailable: StatusCodeType("503", "Service Unavailable"),
    gateway_timeout: StatusCodeType("504", "Gateway Timeout"),
    http_version_not_supported: StatusCodeType("505", "Http Version Not Supported"),
    variant_also_negotiates: StatusCodeType("506", "Variant Also Negotiates"),
    insufficient_storage: StatusCodeType("507", "Insufficient Storage"),
    loop_detected: StatusCodeType("508", "Loop Detected"),
    not_extended: StatusCodeType("510", "Not Extended"),
    network_authentication_required: StatusCodeType("511", "Network Authentication Required"),

    const Self = @This();

    pub fn format(self: Self, colorized: bool) []const u8 {
        return switch (self) {
            inline else => |capture| capture.format(colorized),
        };
    }
};
