//! Member inspection utilities
//!
//! Provides functions to inspect type members:
//! - getmethods: Get methods of a type
//! - getmro: Get method resolution order
//! - issubclass: Check subclass relationships

const std = @import("std");
const types = @import("types.zig");

pub const MemberInfo = types.MemberInfo;

// ============================================================================
// Member inspection
// ============================================================================

/// Get methods of a type as a slice
pub fn getmethods(comptime T: type) []const []const u8 {
    const type_info = @typeInfo(T);
    if (type_info != .@"struct") return &[_][]const u8{};

    const decls = type_info.@"struct".decls;
    comptime var count: usize = 0;

    // Count methods
    inline for (decls) |decl| {
        const field_type = @TypeOf(@field(T, decl.name));
        if (@typeInfo(field_type) == .@"fn") {
            count += 1;
        }
    }

    comptime var result: [count][]const u8 = undefined;
    comptime var idx: usize = 0;

    inline for (decls) |decl| {
        const field_type = @TypeOf(@field(T, decl.name));
        if (@typeInfo(field_type) == .@"fn") {
            result[idx] = decl.name;
            idx += 1;
        }
    }

    return &result;
}

// ============================================================================
// Class hierarchy
// ============================================================================

/// Get the method resolution order
pub fn getmro(comptime T: type) []const type {
    // Zig doesn't have class inheritance, so MRO is just the type itself
    return &[_]type{T};
}

/// Check if a class is a subclass of another
pub fn issubclass(comptime Sub: type, comptime Super: type) bool {
    // In Zig, we check structural compatibility
    if (Sub == Super) return true;

    // Check if Sub has all fields of Super
    const sub_info = @typeInfo(Sub);
    const super_info = @typeInfo(Super);

    if (sub_info != .@"struct" or super_info != .@"struct") return false;

    for (super_info.@"struct".fields) |super_field| {
        var found = false;
        for (sub_info.@"struct".fields) |sub_field| {
            if (std.mem.eql(u8, super_field.name, sub_field.name)) {
                found = true;
                break;
            }
        }
        if (!found) return false;
    }

    return true;
}
