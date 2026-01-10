//! test.test_future_stmt.test_registry - Future statement registry and metadata
//!
//! The __future__ module maintains a registry of all future statements,
//! their status, and when they were introduced or became mandatory.
//!
//! This module tests the future statement registry, feature flags, and
//! version compatibility checking.
//!
//! CPython Reference: https://docs.python.org/3/library/__future__.html

const std = @import("std");
const testing = std.testing;

// ============================================================================
// Future Feature Metadata
// ============================================================================

/// Represents a future feature
pub const FutureFeature = struct {
    /// The feature name (e.g., "annotations", "division")
    name: []const u8,
    /// Python version where this was introduced as optional
    optional_release: Version,
    /// Python version where this became mandatory (or null if still optional)
    mandatory_release: ?Version,
    /// Compiler flag value
    compiler_flag: u32,
    /// Brief description
    description: []const u8,

    const Self = @This();

    /// Check if this feature is optional in a given Python version
    pub fn isOptionalIn(self: Self, version: Version) bool {
        if (version.compare(self.optional_release) < 0) {
            return false; // Not yet introduced
        }
        if (self.mandatory_release) |mandatory| {
            if (version.compare(mandatory) >= 0) {
                return false; // Already mandatory
            }
        }
        return true;
    }

    /// Check if this feature is mandatory in a given Python version
    pub fn isMandatoryIn(self: Self, version: Version) bool {
        if (self.mandatory_release) |mandatory| {
            return version.compare(mandatory) >= 0;
        }
        return false;
    }

    /// Check if this feature is available in a given Python version
    pub fn isAvailableIn(self: Self, version: Version) bool {
        return version.compare(self.optional_release) >= 0;
    }
};

/// Python version representation
pub const Version = struct {
    major: u8,
    minor: u8,
    micro: u8 = 0,

    const Self = @This();

    pub fn init(major: u8, minor: u8) Self {
        return .{ .major = major, .minor = minor };
    }

    pub fn initWithMicro(major: u8, minor: u8, micro: u8) Self {
        return .{ .major = major, .minor = minor, .micro = micro };
    }

    /// Compare two versions
    /// Returns: -1 if self < other, 0 if equal, 1 if self > other
    pub fn compare(self: Self, other: Self) i8 {
        if (self.major != other.major) {
            return if (self.major < other.major) -1 else 1;
        }
        if (self.minor != other.minor) {
            return if (self.minor < other.minor) -1 else 1;
        }
        if (self.micro != other.micro) {
            return if (self.micro < other.micro) -1 else 1;
        }
        return 0;
    }

    /// Format as string
    pub fn toString(self: Self, buffer: []u8) ![]u8 {
        return try std.fmt.bufPrint(buffer, "{d}.{d}.{d}", .{ self.major, self.minor, self.micro });
    }

    /// Check if version is Python 3
    pub fn isPython3(self: Self) bool {
        return self.major >= 3;
    }

    /// Check if version is Python 2
    pub fn isPython2(self: Self) bool {
        return self.major == 2;
    }
};

// ============================================================================
// Feature Registry
// ============================================================================

/// Registry of all __future__ features
pub const FutureRegistry = struct {
    features: []const FutureFeature,

    const Self = @This();

    /// Default registry with all known features
    pub const default = Self{
        .features = &known_features,
    };

    /// Known future features
    const known_features = [_]FutureFeature{
        // Features that became mandatory in Python 3.0
        .{
            .name = "nested_scopes",
            .optional_release = Version.init(2, 1),
            .mandatory_release = Version.init(2, 2),
            .compiler_flag = 0x0010,
            .description = "Statically nested scopes (closures)",
        },
        .{
            .name = "generators",
            .optional_release = Version.init(2, 2),
            .mandatory_release = Version.init(2, 3),
            .compiler_flag = 0x0008,
            .description = "Generator functions using yield",
        },
        .{
            .name = "division",
            .optional_release = Version.init(2, 2),
            .mandatory_release = Version.init(3, 0),
            .compiler_flag = 0x2000,
            .description = "True division (/ always returns float)",
        },
        .{
            .name = "absolute_import",
            .optional_release = Version.init(2, 5),
            .mandatory_release = Version.init(3, 0),
            .compiler_flag = 0x4000,
            .description = "Absolute imports are default",
        },
        .{
            .name = "with_statement",
            .optional_release = Version.init(2, 5),
            .mandatory_release = Version.init(2, 6),
            .compiler_flag = 0x8000,
            .description = "The with statement",
        },
        .{
            .name = "print_function",
            .optional_release = Version.init(2, 6),
            .mandatory_release = Version.init(3, 0),
            .compiler_flag = 0x10000,
            .description = "print as a function",
        },
        .{
            .name = "unicode_literals",
            .optional_release = Version.init(2, 6),
            .mandatory_release = Version.init(3, 0),
            .compiler_flag = 0x20000,
            .description = "String literals are Unicode by default",
        },
        .{
            .name = "generator_stop",
            .optional_release = Version.init(3, 5),
            .mandatory_release = Version.init(3, 7),
            .compiler_flag = 0x80000,
            .description = "StopIteration in generators becomes RuntimeError",
        },
        // Features that are still optional
        .{
            .name = "annotations",
            .optional_release = Version.init(3, 7),
            .mandatory_release = null, // Was planned for 3.10, then postponed indefinitely
            .compiler_flag = 0x100000,
            .description = "Postponed evaluation of annotations (PEP 563)",
        },
        // Easter eggs / jokes
        .{
            .name = "barry_as_FLUFL",
            .optional_release = Version.init(3, 1),
            .mandatory_release = null, // It's a joke
            .compiler_flag = 0x40000,
            .description = "Use <> instead of != (April Fools)",
        },
    };

    /// Find a feature by name
    pub fn findFeature(self: Self, name: []const u8) ?FutureFeature {
        for (self.features) |feature| {
            if (std.mem.eql(u8, feature.name, name)) {
                return feature;
            }
        }
        return null;
    }

    /// Get all features optional in a version
    pub fn optionalFeaturesIn(self: Self, version: Version, buffer: []FutureFeature) []FutureFeature {
        var idx: usize = 0;
        for (self.features) |feature| {
            if (feature.isOptionalIn(version) and idx < buffer.len) {
                buffer[idx] = feature;
                idx += 1;
            }
        }
        return buffer[0..idx];
    }

    /// Get all mandatory features in a version
    pub fn mandatoryFeaturesIn(self: Self, version: Version, buffer: []FutureFeature) []FutureFeature {
        var idx: usize = 0;
        for (self.features) |feature| {
            if (feature.isMandatoryIn(version) and idx < buffer.len) {
                buffer[idx] = feature;
                idx += 1;
            }
        }
        return buffer[0..idx];
    }

    /// Count total features
    pub fn count(self: Self) usize {
        return self.features.len;
    }
};

// ============================================================================
// Compiler Flags
// ============================================================================

/// Compiler flag constants for future features
pub const CompilerFlags = struct {
    pub const CO_NESTED: u32 = 0x0010;
    pub const CO_GENERATOR_ALLOWED: u32 = 0x0008;
    pub const CO_FUTURE_DIVISION: u32 = 0x2000;
    pub const CO_FUTURE_ABSOLUTE_IMPORT: u32 = 0x4000;
    pub const CO_FUTURE_WITH_STATEMENT: u32 = 0x8000;
    pub const CO_FUTURE_PRINT_FUNCTION: u32 = 0x10000;
    pub const CO_FUTURE_UNICODE_LITERALS: u32 = 0x20000;
    pub const CO_FUTURE_BARRY_AS_BDFL: u32 = 0x40000;
    pub const CO_FUTURE_GENERATOR_STOP: u32 = 0x80000;
    pub const CO_FUTURE_ANNOTATIONS: u32 = 0x100000;

    /// Combine multiple flags
    pub fn combine(flags: []const u32) u32 {
        var result: u32 = 0;
        for (flags) |flag| {
            result |= flag;
        }
        return result;
    }

    /// Check if a flag is set
    pub fn isSet(combined: u32, flag: u32) bool {
        return (combined & flag) != 0;
    }

    /// Get flag name
    pub fn getFlagName(flag: u32) ?[]const u8 {
        return switch (flag) {
            CO_NESTED => "CO_NESTED",
            CO_GENERATOR_ALLOWED => "CO_GENERATOR_ALLOWED",
            CO_FUTURE_DIVISION => "CO_FUTURE_DIVISION",
            CO_FUTURE_ABSOLUTE_IMPORT => "CO_FUTURE_ABSOLUTE_IMPORT",
            CO_FUTURE_WITH_STATEMENT => "CO_FUTURE_WITH_STATEMENT",
            CO_FUTURE_PRINT_FUNCTION => "CO_FUTURE_PRINT_FUNCTION",
            CO_FUTURE_UNICODE_LITERALS => "CO_FUTURE_UNICODE_LITERALS",
            CO_FUTURE_BARRY_AS_BDFL => "CO_FUTURE_BARRY_AS_BDFL",
            CO_FUTURE_GENERATOR_STOP => "CO_FUTURE_GENERATOR_STOP",
            CO_FUTURE_ANNOTATIONS => "CO_FUTURE_ANNOTATIONS",
            else => null,
        };
    }
};

// ============================================================================
// Future Statement Parser
// ============================================================================

/// Parses future import statements
pub const FutureParser = struct {
    const Self = @This();

    /// Check if a line is a valid future import
    pub fn isFutureImport(line: []const u8) bool {
        const trimmed = std.mem.trim(u8, line, " \t");
        return std.mem.startsWith(u8, trimmed, "from __future__ import ");
    }

    /// Result type for extracted features
    pub const FeatureList = struct {
        items: std.ArrayListUnmanaged([]const u8),
        allocator: std.mem.Allocator,

        pub fn deinit(self: *FeatureList) void {
            self.items.deinit(self.allocator);
        }
    };

    /// Extract feature names from a future import line
    pub fn extractFeatures(allocator: std.mem.Allocator, line: []const u8) !FeatureList {
        var features: std.ArrayListUnmanaged([]const u8) = .{};

        const trimmed = std.mem.trim(u8, line, " \t");
        if (!std.mem.startsWith(u8, trimmed, "from __future__ import ")) {
            return .{ .items = features, .allocator = allocator };
        }

        const imports = trimmed[22..]; // After "from __future__ import "
        var it = std.mem.splitAny(u8, imports, ", ");
        while (it.next()) |part| {
            const feature = std.mem.trim(u8, part, " \t");
            if (feature.len > 0 and !std.mem.eql(u8, feature, "(") and !std.mem.eql(u8, feature, ")")) {
                try features.append(allocator, feature);
            }
        }

        return .{ .items = features, .allocator = allocator };
    }

    /// Validate that future imports are at the beginning of the module
    pub fn validatePosition(lines: []const []const u8) !usize {
        var saw_code = false;
        var last_future_line: usize = 0;

        for (lines, 0..) |line, i| {
            const trimmed = std.mem.trim(u8, line, " \t\n");

            // Skip empty lines and comments
            if (trimmed.len == 0 or trimmed[0] == '#') continue;

            // Skip docstrings (simplified)
            if (std.mem.startsWith(u8, trimmed, "\"\"\"") or std.mem.startsWith(u8, trimmed, "'''")) {
                continue;
            }

            if (isFutureImport(line)) {
                if (saw_code) {
                    return error.FutureImportAfterCode;
                }
                last_future_line = i;
            } else {
                saw_code = true;
            }
        }

        return last_future_line;
    }
};

// ============================================================================
// Version Compatibility Checker
// ============================================================================

/// Checks feature compatibility with Python versions
pub const CompatibilityChecker = struct {
    target_version: Version,
    registry: FutureRegistry,

    const Self = @This();

    pub fn init(target: Version) Self {
        return .{
            .target_version = target,
            .registry = FutureRegistry.default,
        };
    }

    /// Check if a feature is needed for compatibility
    pub fn isFeatureNeeded(self: Self, feature_name: []const u8) bool {
        if (self.registry.findFeature(feature_name)) |feature| {
            return feature.isOptionalIn(self.target_version);
        }
        return false;
    }

    /// Get required future imports for Python 2/3 compatibility
    pub fn getRequiredForPython2Compat(self: Self) []const []const u8 {
        _ = self;
        return &[_][]const u8{
            "print_function",
            "unicode_literals",
            "absolute_import",
            "division",
        };
    }

    /// Check if code would work without future imports in target version
    pub fn checkCompatibility(self: Self, features: []const []const u8) bool {
        for (features) |feature_name| {
            if (!self.isFeatureNeeded(feature_name)) {
                // Feature is mandatory or unknown - no import needed
                continue;
            }
            return false; // Feature is still optional, import needed
        }
        return true;
    }
};

// ============================================================================
// Tests
// ============================================================================

test "version_init" {
    const v = Version.init(3, 9);
    try testing.expectEqual(@as(u8, 3), v.major);
    try testing.expectEqual(@as(u8, 9), v.minor);
    try testing.expectEqual(@as(u8, 0), v.micro);
}

test "version_compare" {
    const v1 = Version.init(3, 8);
    const v2 = Version.init(3, 9);
    const v3 = Version.init(3, 9);

    try testing.expect(v1.compare(v2) < 0);
    try testing.expect(v2.compare(v1) > 0);
    try testing.expect(v2.compare(v3) == 0);
}

test "version_python_check" {
    const py2 = Version.init(2, 7);
    const py3 = Version.init(3, 10);

    try testing.expect(py2.isPython2());
    try testing.expect(!py2.isPython3());
    try testing.expect(py3.isPython3());
    try testing.expect(!py3.isPython2());
}

test "future_feature_availability" {
    const division = FutureFeature{
        .name = "division",
        .optional_release = Version.init(2, 2),
        .mandatory_release = Version.init(3, 0),
        .compiler_flag = 0x2000,
        .description = "True division",
    };

    try testing.expect(division.isAvailableIn(Version.init(2, 5)));
    try testing.expect(division.isOptionalIn(Version.init(2, 6)));
    try testing.expect(!division.isOptionalIn(Version.init(3, 0)));
    try testing.expect(division.isMandatoryIn(Version.init(3, 0)));
}

test "future_registry_find" {
    const registry = FutureRegistry.default;

    const division = registry.findFeature("division");
    try testing.expect(division != null);
    try testing.expectEqualStrings("division", division.?.name);

    const nonexistent = registry.findFeature("nonexistent");
    try testing.expect(nonexistent == null);
}

test "future_registry_count" {
    const registry = FutureRegistry.default;
    try testing.expect(registry.count() >= 8); // At least 8 known features
}

test "compiler_flags_combine" {
    const combined = CompilerFlags.combine(&.{
        CompilerFlags.CO_FUTURE_DIVISION,
        CompilerFlags.CO_FUTURE_PRINT_FUNCTION,
    });

    try testing.expect(CompilerFlags.isSet(combined, CompilerFlags.CO_FUTURE_DIVISION));
    try testing.expect(CompilerFlags.isSet(combined, CompilerFlags.CO_FUTURE_PRINT_FUNCTION));
    try testing.expect(!CompilerFlags.isSet(combined, CompilerFlags.CO_FUTURE_ANNOTATIONS));
}

test "compiler_flags_names" {
    try testing.expectEqualStrings("CO_FUTURE_DIVISION", CompilerFlags.getFlagName(CompilerFlags.CO_FUTURE_DIVISION).?);
    try testing.expect(CompilerFlags.getFlagName(0xFFFFFFFF) == null);
}

test "future_parser_is_future_import" {
    try testing.expect(FutureParser.isFutureImport("from __future__ import division"));
    try testing.expect(FutureParser.isFutureImport("  from __future__ import print_function"));
    try testing.expect(!FutureParser.isFutureImport("from os import path"));
    try testing.expect(!FutureParser.isFutureImport("import __future__"));
}

test "future_parser_extract_features" {
    var features = try FutureParser.extractFeatures(testing.allocator, "from __future__ import division, print_function");
    defer features.deinit();

    try testing.expectEqual(@as(usize, 2), features.items.items.len);
    try testing.expectEqualStrings("division", features.items.items[0]);
    try testing.expectEqualStrings("print_function", features.items.items[1]);
}

test "future_parser_validate_position" {
    const valid_lines = [_][]const u8{
        "#!/usr/bin/env python",
        "# comment",
        "\"\"\"docstring\"\"\"",
        "from __future__ import division",
        "import os",
    };
    const last = try FutureParser.validatePosition(&valid_lines);
    try testing.expectEqual(@as(usize, 3), last);
}

test "compatibility_checker_init" {
    const checker = CompatibilityChecker.init(Version.init(3, 10));
    try testing.expectEqual(@as(u8, 3), checker.target_version.major);
    try testing.expectEqual(@as(u8, 10), checker.target_version.minor);
}

test "compatibility_checker_python2_compat" {
    const checker = CompatibilityChecker.init(Version.init(2, 7));
    const required = checker.getRequiredForPython2Compat();
    try testing.expect(required.len >= 4);
}

test "version_to_string" {
    const v = Version.initWithMicro(3, 10, 4);
    var buffer: [20]u8 = undefined;
    const str = try v.toString(&buffer);
    try testing.expectEqualStrings("3.10.4", str);
}

test "future_feature_description" {
    const registry = FutureRegistry.default;
    const annotations = registry.findFeature("annotations");
    try testing.expect(annotations != null);
    try testing.expect(annotations.?.description.len > 0);
}

test "annotations_no_mandatory_release" {
    const registry = FutureRegistry.default;
    const annotations = registry.findFeature("annotations");
    try testing.expect(annotations != null);
    try testing.expect(annotations.?.mandatory_release == null);
}

test "barry_as_flufl_in_registry" {
    const registry = FutureRegistry.default;
    const barry = registry.findFeature("barry_as_FLUFL");
    try testing.expect(barry != null);
    try testing.expect(std.mem.indexOf(u8, barry.?.description, "April Fools") != null);
}
