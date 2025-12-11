//! Function signature inspection
//!
//! Provides functions to extract and work with function signatures:
//! - getSignature: Extract signature from a function type
//! - formatargspec: Format a signature as a string

const std = @import("std");
const types = @import("types.zig");

pub const Parameter = types.Parameter;
pub const ParameterKind = types.ParameterKind;
pub const Signature = types.Signature;

// ============================================================================
// Signature inspection
// ============================================================================

/// Get the signature of a function type
pub fn getSignature(comptime T: type) Signature {
    const info = @typeInfo(T);

    if (info != .@"fn") {
        return Signature.init(&[_]Parameter{});
    }

    const fn_info = info.@"fn";
    var params: [fn_info.params.len]Parameter = undefined;

    inline for (fn_info.params, 0..) |param, i| {
        params[i] = .{
            .name = if (param.name) |n| n else "",
            .kind = .POSITIONAL_OR_KEYWORD,
            .annotation = if (param.type) |t| @typeName(t) else "any",
        };
    }

    return Signature.init(&params);
}

// ============================================================================
// Formatting
// ============================================================================

/// Format a signature as a string
pub fn formatargspec(sig: Signature, allocator: std.mem.Allocator) ![]u8 {
    var result = std.ArrayList(u8).init(allocator);
    errdefer result.deinit();

    try result.append('(');

    for (sig.parameters, 0..) |param, i| {
        if (i > 0) {
            try result.appendSlice(", ");
        }
        try result.appendSlice(param.name);

        if (param.annotation) |ann| {
            try result.appendSlice(": ");
            try result.appendSlice(ann);
        }

        if (param.default) |def| {
            try result.appendSlice(" = ");
            try result.appendSlice(def);
        }
    }

    try result.append(')');

    if (sig.return_annotation) |ret| {
        try result.appendSlice(" -> ");
        try result.appendSlice(ret);
    }

    return result.toOwnedSlice();
}
