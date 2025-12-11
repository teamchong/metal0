//! Helper functions for creating plist values

const types = @import("types.zig");
const PlistValue = types.PlistValue;
const UID = types.UID;

// ============================================================================
// Helper functions
// ============================================================================

/// Create a string value
pub fn string(s: []const u8) PlistValue {
    return .{ .string = s };
}

/// Create an integer value
pub fn integer(i: i64) PlistValue {
    return .{ .integer = i };
}

/// Create a real value
pub fn real(r: f64) PlistValue {
    return .{ .real = r };
}

/// Create a boolean value
pub fn boolean(b: bool) PlistValue {
    return .{ .boolean = b };
}

/// Create a data value
pub fn data(d: []const u8) PlistValue {
    return .{ .data = d };
}

/// Create a date value from unix timestamp
pub fn date(timestamp: i64) PlistValue {
    return .{ .date = timestamp };
}

/// Create a UID value
pub fn uid(u: u64) PlistValue {
    return .{ .uid = UID.init(u) };
}
