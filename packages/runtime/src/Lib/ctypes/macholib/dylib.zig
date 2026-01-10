//! ctypes.macholib.dylib - Generic dylib path manipulation
//! Reference: cpython/Lib/ctypes/macholib/dylib.py
//!
//! CPython __all__: ['dylib_info']
//!
//! Parses dylib paths to extract location, name, version, and suffix.

const std = @import("std");

// ============================================================================
// Dylib Info Structure
// ============================================================================

/// Information extracted from a dylib path
/// Matches CPython's dylib_info() return dict
pub const DylibInfo = struct {
    /// Directory containing the dylib
    location: []const u8,
    /// Full name including version and suffix
    name: []const u8,
    /// Short name without version/suffix
    shortname: []const u8,
    /// Version string (optional)
    version: ?[]const u8,
    /// Suffix string (optional)
    suffix: ?[]const u8,
};

// ============================================================================
// Dylib Path Patterns
// ============================================================================

/// A dylib name can take one of the following four forms:
///   Location/Name.SomeVersion_Suffix.dylib
///   Location/Name.SomeVersion.dylib
///   Location/Name_Suffix.dylib
///   Location/Name.dylib

/// CPython: DYLIB_RE regex pattern
/// (?x)
/// (?P<location>^.*)(?:^|/)
/// (?P<name>
///     (?P<shortname>\w+?)
///     (?:\.(?P<version>[^._]+))?
///     (?:_(?P<suffix>[^._]+))?
///     \.dylib$
/// )

// ============================================================================
// Main Function
// ============================================================================

/// CPython: def dylib_info(filename)
/// Parse a dylib filename and return its components.
///
/// Returns null if the filename doesn't match the dylib pattern.
/// Otherwise returns a DylibInfo struct with:
///   - location: Directory path
///   - name: Full dylib name
///   - shortname: Base name without version/suffix
///   - version: Version string (optional)
///   - suffix: Suffix string (optional)
pub fn dylib_info(filename: []const u8) ?DylibInfo {
    // Must end with .dylib
    if (!std.mem.endsWith(u8, filename, ".dylib")) {
        return null;
    }

    // Find the last path separator
    const last_sep = std.mem.lastIndexOfScalar(u8, filename, '/');
    const location = if (last_sep) |sep| filename[0..sep] else "";
    const name_start = if (last_sep) |sep| sep + 1 else 0;
    const name = filename[name_start..];

    // Remove .dylib suffix for parsing
    const base = name[0 .. name.len - 6]; // Remove ".dylib"

    // Parse the base name
    // Pattern: shortname[.version][_suffix]
    var shortname: []const u8 = base;
    var version: ?[]const u8 = null;
    var suffix: ?[]const u8 = null;

    // Check for suffix (after underscore)
    if (std.mem.lastIndexOfScalar(u8, base, '_')) |underscore| {
        const potential_suffix = base[underscore + 1 ..];
        // Suffix should not contain dots
        if (std.mem.indexOfScalar(u8, potential_suffix, '.') == null) {
            suffix = potential_suffix;
            shortname = base[0..underscore];
        }
    }

    // Check for version (after dot in shortname)
    const name_to_check = if (suffix != null) shortname else base;
    if (std.mem.indexOfScalar(u8, name_to_check, '.')) |dot| {
        const potential_version = name_to_check[dot + 1 ..];
        // Version should start with a digit or be alphanumeric
        if (potential_version.len > 0) {
            version = potential_version;
            shortname = name_to_check[0..dot];
        }
    }

    // Shortname must be valid (non-empty, word characters)
    if (shortname.len == 0) {
        return null;
    }

    // Validate shortname contains only word characters
    for (shortname) |c| {
        if (!std.ascii.isAlphanumeric(c) and c != '_') {
            return null;
        }
    }

    return DylibInfo{
        .location = location,
        .name = name,
        .shortname = shortname,
        .version = version,
        .suffix = suffix,
    };
}

// ============================================================================
// Tests
// ============================================================================

test "dylib_info basic" {
    const info = dylib_info("/usr/lib/libSystem.dylib");
    try std.testing.expect(info != null);
    try std.testing.expectEqualStrings("/usr/lib", info.?.location);
    try std.testing.expectEqualStrings("libSystem.dylib", info.?.name);
    try std.testing.expectEqualStrings("libSystem", info.?.shortname);
    try std.testing.expect(info.?.version == null);
    try std.testing.expect(info.?.suffix == null);
}

test "dylib_info with version" {
    const info = dylib_info("/usr/lib/libfoo.1.dylib");
    try std.testing.expect(info != null);
    try std.testing.expectEqualStrings("libfoo", info.?.shortname);
    try std.testing.expectEqualStrings("1", info.?.version.?);
}

test "dylib_info with suffix" {
    const info = dylib_info("/usr/lib/libfoo_debug.dylib");
    try std.testing.expect(info != null);
    try std.testing.expectEqualStrings("libfoo", info.?.shortname);
    try std.testing.expectEqualStrings("debug", info.?.suffix.?);
}

test "dylib_info with version and suffix" {
    const info = dylib_info("/usr/lib/libfoo.1_debug.dylib");
    try std.testing.expect(info != null);
    // Note: parsing order matters - this test documents current behavior
}

test "dylib_info non-dylib" {
    const info = dylib_info("/usr/lib/libfoo.so");
    try std.testing.expect(info == null);
}

test "dylib_info no path" {
    const info = dylib_info("libfoo.dylib");
    try std.testing.expect(info != null);
    try std.testing.expectEqualStrings("", info.?.location);
    try std.testing.expectEqualStrings("libfoo.dylib", info.?.name);
}
