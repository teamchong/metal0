//! Core types for plist values

const std = @import("std");
const hashmap_helper = @import("utils.hashmap_helper");

// ============================================================================
// PlistFormat - Format types
// ============================================================================

pub const PlistFormat = enum {
    FMT_XML,
    FMT_BINARY,
};

// ============================================================================
// UID - Unique ID type for binary plists
// ============================================================================

pub const UID = struct {
    data: u64,

    pub fn init(data: u64) UID {
        return .{ .data = data };
    }
};

// ============================================================================
// PlistValue - Union type for plist values
// ============================================================================

pub const PlistValue = union(enum) {
    string: []const u8,
    integer: i64,
    real: f64,
    boolean: bool,
    data: []const u8,
    date: i64, // Unix timestamp
    array: []PlistValue,
    dict: hashmap_helper.StringHashMap(PlistValue),
    uid: UID,
};
