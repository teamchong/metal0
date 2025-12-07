/// future - Future Statement Processing
/// Mirrors cpython/Python/future.c
///
/// This module handles __future__ imports and feature flags:
/// - Parses from __future__ import statements
/// - Sets compiler flags for enabled features
/// - Validates future feature names

const std = @import("std");

// ============================================================================
// Future Feature Names
// ============================================================================

/// Well-known future features (from __future__.py)
pub const FUTURE_NESTED_SCOPES = "nested_scopes";
pub const FUTURE_GENERATORS = "generators";
pub const FUTURE_DIVISION = "division";
pub const FUTURE_ABSOLUTE_IMPORT = "absolute_import";
pub const FUTURE_WITH_STATEMENT = "with_statement";
pub const FUTURE_PRINT_FUNCTION = "print_function";
pub const FUTURE_UNICODE_LITERALS = "unicode_literals";
pub const FUTURE_BARRY_AS_BDFL = "barry_as_FLUFL";
pub const FUTURE_GENERATOR_STOP = "generator_stop";
pub const FUTURE_ANNOTATIONS = "annotations";

/// All known future features
pub const ALL_FEATURES = [_][]const u8{
    FUTURE_NESTED_SCOPES,
    FUTURE_GENERATORS,
    FUTURE_DIVISION,
    FUTURE_ABSOLUTE_IMPORT,
    FUTURE_WITH_STATEMENT,
    FUTURE_PRINT_FUNCTION,
    FUTURE_UNICODE_LITERALS,
    FUTURE_BARRY_AS_BDFL,
    FUTURE_GENERATOR_STOP,
    FUTURE_ANNOTATIONS,
};

// ============================================================================
// Code Object Flags
// ============================================================================

/// Compiler flags that can be set by future statements
pub const CodeFlags = packed struct(u32) {
    optimized: bool = false,
    newlocals: bool = false,
    varargs: bool = false,
    varkeywords: bool = false,
    nested: bool = false,
    generator: bool = false,
    nofree: bool = false,
    coroutine: bool = false,
    iterable_coroutine: bool = false,
    async_generator: bool = false,
    // Future flags start at bit 16
    _reserved: u6 = 0,
    future_division: bool = false, // bit 16
    future_absolute_import: bool = false,
    future_with_statement: bool = false,
    future_print_function: bool = false,
    future_unicode_literals: bool = false,
    future_barry_as_bdfl: bool = false,
    future_generator_stop: bool = false,
    future_annotations: bool = false,
    _reserved2: u2 = 0,
};

/// Individual flag values
pub const CO_FUTURE_DIVISION: u32 = 1 << 16;
pub const CO_FUTURE_ABSOLUTE_IMPORT: u32 = 1 << 17;
pub const CO_FUTURE_WITH_STATEMENT: u32 = 1 << 18;
pub const CO_FUTURE_PRINT_FUNCTION: u32 = 1 << 19;
pub const CO_FUTURE_UNICODE_LITERALS: u32 = 1 << 20;
pub const CO_FUTURE_BARRY_AS_BDFL: u32 = 1 << 21;
pub const CO_FUTURE_GENERATOR_STOP: u32 = 1 << 22;
pub const CO_FUTURE_ANNOTATIONS: u32 = 1 << 23;

// ============================================================================
// Source Location
// ============================================================================

pub const SourceLocation = struct {
    lineno: i32 = -1,
    col_offset: i32 = -1,
    end_lineno: i32 = -1,
    end_col_offset: i32 = -1,

    pub fn isValid(self: SourceLocation) bool {
        return self.lineno >= 0;
    }
};

// ============================================================================
// Future Features
// ============================================================================

/// Holds future feature flags and location
pub const FutureFeatures = struct {
    /// Bitmask of enabled features
    features: u32 = 0,

    /// Location of first future statement
    location: SourceLocation = .{},

    const Self = @This();

    /// Check if a feature is enabled
    pub fn hasFeature(self: Self, flag: u32) bool {
        return self.features & flag != 0;
    }

    /// Enable a feature
    pub fn setFeature(self: *Self, flag: u32) void {
        self.features |= flag;
    }

    /// Check if barry_as_FLUFL is enabled
    pub fn hasBarryAsBdfl(self: Self) bool {
        return self.hasFeature(CO_FUTURE_BARRY_AS_BDFL);
    }

    /// Check if annotations is enabled
    pub fn hasAnnotations(self: Self) bool {
        return self.hasFeature(CO_FUTURE_ANNOTATIONS);
    }

    /// Get all enabled features as CodeFlags
    pub fn asCodeFlags(self: Self) CodeFlags {
        return @bitCast(self.features);
    }
};

// ============================================================================
// Feature Validation
// ============================================================================

pub const FeatureError = error{
    UndefinedFeature,
    NotAChance, // "from __future__ import braces"
};

/// Check if a feature name is valid
pub fn isValidFeature(name: []const u8) bool {
    // Special case: braces is recognized but rejected
    if (std.mem.eql(u8, name, "braces")) {
        return true;
    }

    for (ALL_FEATURES) |feature| {
        if (std.mem.eql(u8, name, feature)) {
            return true;
        }
    }
    return false;
}

/// Check a feature and return its flag (or error)
pub fn checkFeature(name: []const u8) FeatureError!?u32 {
    // Easter egg: "from __future__ import braces"
    if (std.mem.eql(u8, name, "braces")) {
        return FeatureError.NotAChance;
    }

    // Features that are now always enabled (no-op)
    if (std.mem.eql(u8, name, FUTURE_NESTED_SCOPES) or
        std.mem.eql(u8, name, FUTURE_GENERATORS) or
        std.mem.eql(u8, name, FUTURE_DIVISION) or
        std.mem.eql(u8, name, FUTURE_ABSOLUTE_IMPORT) or
        std.mem.eql(u8, name, FUTURE_WITH_STATEMENT) or
        std.mem.eql(u8, name, FUTURE_PRINT_FUNCTION) or
        std.mem.eql(u8, name, FUTURE_UNICODE_LITERALS) or
        std.mem.eql(u8, name, FUTURE_GENERATOR_STOP))
    {
        return null; // No flag needed, always enabled
    }

    // Features that set flags
    if (std.mem.eql(u8, name, FUTURE_BARRY_AS_BDFL)) {
        return CO_FUTURE_BARRY_AS_BDFL;
    }

    if (std.mem.eql(u8, name, FUTURE_ANNOTATIONS)) {
        return CO_FUTURE_ANNOTATIONS;
    }

    return FeatureError.UndefinedFeature;
}

// ============================================================================
// Future Statement Parsing
// ============================================================================

/// Parse future features from a list of import names
pub fn parseFutureFeatures(names: []const []const u8) !FutureFeatures {
    var ff = FutureFeatures{};

    for (names) |name| {
        const flag = try checkFeature(name);
        if (flag) |f| {
            ff.setFeature(f);
        }
    }

    return ff;
}

/// Update features from AST (simplified version)
pub fn fromImportNames(ff: *FutureFeatures, names: []const []const u8, loc: SourceLocation) !void {
    for (names) |name| {
        const flag = try checkFeature(name);
        if (flag) |f| {
            ff.setFeature(f);
            if (!ff.location.isValid()) {
                ff.location = loc;
            }
        }
    }
}

// ============================================================================
// Utility Functions
// ============================================================================

/// Get feature name from flag
pub fn getFeatureName(flag: u32) ?[]const u8 {
    return switch (flag) {
        CO_FUTURE_DIVISION => FUTURE_DIVISION,
        CO_FUTURE_ABSOLUTE_IMPORT => FUTURE_ABSOLUTE_IMPORT,
        CO_FUTURE_WITH_STATEMENT => FUTURE_WITH_STATEMENT,
        CO_FUTURE_PRINT_FUNCTION => FUTURE_PRINT_FUNCTION,
        CO_FUTURE_UNICODE_LITERALS => FUTURE_UNICODE_LITERALS,
        CO_FUTURE_BARRY_AS_BDFL => FUTURE_BARRY_AS_BDFL,
        CO_FUTURE_GENERATOR_STOP => FUTURE_GENERATOR_STOP,
        CO_FUTURE_ANNOTATIONS => FUTURE_ANNOTATIONS,
        else => null,
    };
}

/// Get all enabled feature names
pub fn getEnabledFeatures(allocator: std.mem.Allocator, ff: FutureFeatures) ![][]const u8 {
    var features = std.ArrayList([]const u8).init(allocator);
    errdefer features.deinit();

    const flags = [_]u32{
        CO_FUTURE_DIVISION,
        CO_FUTURE_ABSOLUTE_IMPORT,
        CO_FUTURE_WITH_STATEMENT,
        CO_FUTURE_PRINT_FUNCTION,
        CO_FUTURE_UNICODE_LITERALS,
        CO_FUTURE_BARRY_AS_BDFL,
        CO_FUTURE_GENERATOR_STOP,
        CO_FUTURE_ANNOTATIONS,
    };

    for (flags) |flag| {
        if (ff.hasFeature(flag)) {
            if (getFeatureName(flag)) |name| {
                try features.append(name);
            }
        }
    }

    return features.toOwnedSlice();
}

// ============================================================================
// Initialization
// ============================================================================

pub fn init() void {}

// ============================================================================
// Tests
// ============================================================================

test "valid features" {
    try std.testing.expect(isValidFeature("annotations"));
    try std.testing.expect(isValidFeature("barry_as_FLUFL"));
    try std.testing.expect(isValidFeature("braces")); // Valid but rejected
    try std.testing.expect(!isValidFeature("not_a_feature"));
}

test "check feature" {
    // Always-enabled features return null
    try std.testing.expectEqual(@as(?u32, null), try checkFeature("nested_scopes"));
    try std.testing.expectEqual(@as(?u32, null), try checkFeature("generators"));

    // Features with flags
    try std.testing.expectEqual(@as(?u32, CO_FUTURE_BARRY_AS_BDFL), try checkFeature("barry_as_FLUFL"));
    try std.testing.expectEqual(@as(?u32, CO_FUTURE_ANNOTATIONS), try checkFeature("annotations"));

    // Easter egg
    try std.testing.expectError(FeatureError.NotAChance, checkFeature("braces"));

    // Unknown feature
    try std.testing.expectError(FeatureError.UndefinedFeature, checkFeature("unknown"));
}

test "future features struct" {
    var ff = FutureFeatures{};

    try std.testing.expect(!ff.hasAnnotations());
    try std.testing.expect(!ff.hasBarryAsBdfl());

    ff.setFeature(CO_FUTURE_ANNOTATIONS);
    try std.testing.expect(ff.hasAnnotations());

    ff.setFeature(CO_FUTURE_BARRY_AS_BDFL);
    try std.testing.expect(ff.hasBarryAsBdfl());
}

test "parse future features" {
    const names = &[_][]const u8{ "annotations", "nested_scopes" };
    const ff = try parseFutureFeatures(names);

    try std.testing.expect(ff.hasAnnotations());
    try std.testing.expect(!ff.hasBarryAsBdfl());
}

test "feature names" {
    try std.testing.expectEqualStrings("annotations", getFeatureName(CO_FUTURE_ANNOTATIONS).?);
    try std.testing.expectEqualStrings("barry_as_FLUFL", getFeatureName(CO_FUTURE_BARRY_AS_BDFL).?);
    try std.testing.expect(getFeatureName(0) == null);
}
