//! Python '__future__' module - Future statement definitions
//!
//! Provides definitions for __future__ statements.
//!
//! Mirrors: CPython Lib/__future__.py

const std = @import("std");

// ============================================================================
// Feature Flags
// ============================================================================

/// All feature names
pub const all_feature_names = [_][]const u8{
    "nested_scopes",
    "generators",
    "division",
    "absolute_import",
    "with_statement",
    "print_function",
    "unicode_literals",
    "barry_as_FLUFL",
    "generator_stop",
    "annotations",
};

// ============================================================================
// _Feature
// ============================================================================

/// Feature descriptor
pub const _Feature = struct {
    const Self = @This();

    /// Optional release when feature was first available
    optional_release: ?struct { major: u8, minor: u8, micro: u8, level: []const u8, serial: u8 },
    /// Mandatory release when feature became standard
    mandatory_release: ?struct { major: u8, minor: u8, micro: u8, level: []const u8, serial: u8 },
    /// Compiler flag value
    compiler_flag: u32,

    pub fn init(
        optional: ?struct { major: u8, minor: u8, micro: u8, level: []const u8, serial: u8 },
        mandatory: ?struct { major: u8, minor: u8, micro: u8, level: []const u8, serial: u8 },
        compiler_flag: u32,
    ) Self {
        return .{
            .optional_release = optional,
            .mandatory_release = mandatory,
            .compiler_flag = compiler_flag,
        };
    }

    /// Get the optional release info
    pub fn getOptionalRelease(self: Self) ?struct { major: u8, minor: u8, micro: u8, level: []const u8, serial: u8 } {
        return self.optional_release;
    }

    /// Get the mandatory release info
    pub fn getMandatoryRelease(self: Self) ?struct { major: u8, minor: u8, micro: u8, level: []const u8, serial: u8 } {
        return self.mandatory_release;
    }
};

// ============================================================================
// Compiler Flag Constants
// ============================================================================

pub const CO_NESTED = 0x0010;
pub const CO_GENERATOR_ALLOWED = 0x1000;
pub const CO_FUTURE_DIVISION = 0x20000;
pub const CO_FUTURE_ABSOLUTE_IMPORT = 0x40000;
pub const CO_FUTURE_WITH_STATEMENT = 0x80000;
pub const CO_FUTURE_PRINT_FUNCTION = 0x100000;
pub const CO_FUTURE_UNICODE_LITERALS = 0x200000;
pub const CO_FUTURE_BARRY_AS_BDFL = 0x400000;
pub const CO_FUTURE_GENERATOR_STOP = 0x800000;
pub const CO_FUTURE_ANNOTATIONS = 0x1000000;

// ============================================================================
// Feature Definitions
// ============================================================================

/// nested_scopes - Enable nested scopes (PEP 227)
pub const nested_scopes = _Feature.init(
    .{ .major = 2, .minor = 1, .micro = 0, .level = "beta", .serial = 1 },
    .{ .major = 2, .minor = 2, .micro = 0, .level = "alpha", .serial = 0 },
    CO_NESTED,
);

/// generators - Enable generator functions (PEP 255)
pub const generators = _Feature.init(
    .{ .major = 2, .minor = 2, .micro = 0, .level = "alpha", .serial = 1 },
    .{ .major = 2, .minor = 3, .micro = 0, .level = "final", .serial = 0 },
    CO_GENERATOR_ALLOWED,
);

/// division - Enable true division (PEP 238)
pub const division = _Feature.init(
    .{ .major = 2, .minor = 2, .micro = 0, .level = "alpha", .serial = 2 },
    .{ .major = 3, .minor = 0, .micro = 0, .level = "alpha", .serial = 0 },
    CO_FUTURE_DIVISION,
);

/// absolute_import - Enable absolute imports (PEP 328)
pub const absolute_import = _Feature.init(
    .{ .major = 2, .minor = 5, .micro = 0, .level = "alpha", .serial = 1 },
    .{ .major = 3, .minor = 0, .micro = 0, .level = "alpha", .serial = 0 },
    CO_FUTURE_ABSOLUTE_IMPORT,
);

/// with_statement - Enable with statement (PEP 343)
pub const with_statement = _Feature.init(
    .{ .major = 2, .minor = 5, .micro = 0, .level = "alpha", .serial = 1 },
    .{ .major = 2, .minor = 6, .micro = 0, .level = "alpha", .serial = 0 },
    CO_FUTURE_WITH_STATEMENT,
);

/// print_function - Enable print as function (PEP 3105)
pub const print_function = _Feature.init(
    .{ .major = 2, .minor = 6, .micro = 0, .level = "alpha", .serial = 2 },
    .{ .major = 3, .minor = 0, .micro = 0, .level = "alpha", .serial = 0 },
    CO_FUTURE_PRINT_FUNCTION,
);

/// unicode_literals - Enable unicode literals by default (PEP 3112)
pub const unicode_literals = _Feature.init(
    .{ .major = 2, .minor = 6, .micro = 0, .level = "alpha", .serial = 2 },
    .{ .major = 3, .minor = 0, .micro = 0, .level = "alpha", .serial = 0 },
    CO_FUTURE_UNICODE_LITERALS,
);

/// barry_as_FLUFL - April Fools joke (PEP 401)
pub const barry_as_FLUFL = _Feature.init(
    .{ .major = 3, .minor = 1, .micro = 0, .level = "alpha", .serial = 2 },
    null,
    CO_FUTURE_BARRY_AS_BDFL,
);

/// generator_stop - StopIteration in generators becomes RuntimeError (PEP 479)
pub const generator_stop = _Feature.init(
    .{ .major = 3, .minor = 5, .micro = 0, .level = "beta", .serial = 1 },
    .{ .major = 3, .minor = 7, .micro = 0, .level = "alpha", .serial = 0 },
    CO_FUTURE_GENERATOR_STOP,
);

/// annotations - Postponed evaluation of annotations (PEP 563)
pub const annotations = _Feature.init(
    .{ .major = 3, .minor = 7, .micro = 0, .level = "beta", .serial = 1 },
    null, // Not yet mandatory
    CO_FUTURE_ANNOTATIONS,
);

// ============================================================================
// Tests
// ============================================================================

test "feature names" {
    try std.testing.expectEqual(@as(usize, 10), all_feature_names.len);
}

test "nested_scopes feature" {
    try std.testing.expectEqual(CO_NESTED, nested_scopes.compiler_flag);
    try std.testing.expect(nested_scopes.optional_release != null);
    try std.testing.expect(nested_scopes.mandatory_release != null);
}

test "division feature" {
    try std.testing.expectEqual(CO_FUTURE_DIVISION, division.compiler_flag);
}

test "annotations feature" {
    try std.testing.expectEqual(CO_FUTURE_ANNOTATIONS, annotations.compiler_flag);
    try std.testing.expect(annotations.mandatory_release == null);
}

test "compiler flag values" {
    try std.testing.expect(CO_NESTED != 0);
    try std.testing.expect(CO_FUTURE_DIVISION != CO_FUTURE_ABSOLUTE_IMPORT);
    try std.testing.expect(CO_FUTURE_ANNOTATIONS > CO_FUTURE_GENERATOR_STOP);
}
