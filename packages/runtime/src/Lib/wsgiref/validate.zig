//! wsgiref.validate - WSGI application validator
//! Reference: cpython/Lib/wsgiref/validate.py
//!
//! CPython __all__: validator, InputWrapper, ErrorWrapper, WriteWrapper,
//!                  PartialIteratorWrapper, IteratorWrapper, check_status,
//!                  check_headers, check_content_type, check_exc_info,
//!                  check_environ, check_input, check_errors
//!
//! Middleware for validating WSGI application compliance.

const std = @import("std");
const wsgiref = @import("../wsgiref.zig");

pub const WsgiError = wsgiref.WsgiError;
pub const Environ = wsgiref.Environ;
pub const ResponseHeaders = wsgiref.ResponseHeaders;

// ============================================================================
// Validation Errors
// ============================================================================

pub const ValidationError = error{
    AssertionError,
    InvalidEnviron,
    InvalidInput,
    InvalidErrors,
    InvalidStatus,
    InvalidHeaders,
    InvalidContentType,
    InvalidExcInfo,
};

// ============================================================================
// Validation Functions
// ============================================================================

/// Validate HTTP status string
pub fn check_status(status: []const u8) !void {
    if (status.len < 4) {
        return ValidationError.InvalidStatus;
    }

    // First 3 chars must be digits
    for (status[0..3]) |c| {
        if (!std.ascii.isDigit(c)) {
            return ValidationError.InvalidStatus;
        }
    }

    // Must have space after status code
    if (status[3] != ' ') {
        return ValidationError.InvalidStatus;
    }
}

/// Validate response headers
pub fn check_headers(headers: []const struct { []const u8, []const u8 }) !void {
    for (headers) |header| {
        if (!wsgiref.isValidHeaderName(header[0])) {
            return ValidationError.InvalidHeaders;
        }
        if (!wsgiref.isValidHeaderValue(header[1])) {
            return ValidationError.InvalidHeaders;
        }

        // Check for hop-by-hop headers that shouldn't be set
        const name = header[0];
        if (std.ascii.eqlIgnoreCase(name, "connection") or
            std.ascii.eqlIgnoreCase(name, "keep-alive") or
            std.ascii.eqlIgnoreCase(name, "proxy-authenticate") or
            std.ascii.eqlIgnoreCase(name, "proxy-authorization") or
            std.ascii.eqlIgnoreCase(name, "te") or
            std.ascii.eqlIgnoreCase(name, "trailers") or
            std.ascii.eqlIgnoreCase(name, "transfer-encoding") or
            std.ascii.eqlIgnoreCase(name, "upgrade"))
        {
            return ValidationError.InvalidHeaders;
        }
    }
}

/// Validate Content-Type header
pub fn check_content_type(status: []const u8, headers: []const struct { []const u8, []const u8 }) !void {
    // Check if Content-Type is required
    const code = std.fmt.parseInt(u32, status[0..3], 10) catch return ValidationError.InvalidStatus;

    // 1xx, 204, and 304 responses must not have Content-Type
    if (code < 200 or code == 204 or code == 304) {
        for (headers) |header| {
            if (std.ascii.eqlIgnoreCase(header[0], "content-type")) {
                return ValidationError.InvalidContentType;
            }
        }
    }
}

/// Validate WSGI environ dictionary
pub fn check_environ(environ: *const Environ) !void {
    // Required CGI variables
    const required = [_][]const u8{
        "REQUEST_METHOD",
        "SCRIPT_NAME",
        "PATH_INFO",
        "QUERY_STRING",
        "SERVER_NAME",
        "SERVER_PORT",
        "SERVER_PROTOCOL",
    };

    for (required) |key| {
        if (environ.get(key) == null) {
            return ValidationError.InvalidEnviron;
        }
    }
}

// ============================================================================
// Tests
// ============================================================================

test "check_status valid" {
    try check_status("200 OK");
    try check_status("404 Not Found");
    try check_status("500 Internal Server Error");
}

test "check_status invalid" {
    try std.testing.expectError(ValidationError.InvalidStatus, check_status(""));
    try std.testing.expectError(ValidationError.InvalidStatus, check_status("OK"));
    try std.testing.expectError(ValidationError.InvalidStatus, check_status("200"));
}
