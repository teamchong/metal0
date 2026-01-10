//! ctypes.macholib.framework - Generic framework path manipulation
//! Reference: cpython/Lib/ctypes/macholib/framework.py
//!
//! CPython __all__: ['framework_info']
//!
//! Parses framework paths to extract location, name, version, and suffix.

const std = @import("std");

// ============================================================================
// Framework Info Structure
// ============================================================================

/// Information extracted from a framework path
/// Matches CPython's framework_info() return dict
pub const FrameworkInfo = struct {
    /// Directory containing the framework
    location: []const u8,
    /// Full framework path including version
    name: []const u8,
    /// Short name (framework name without .framework)
    shortname: []const u8,
    /// Version string (optional)
    version: ?[]const u8,
    /// Suffix string (optional)
    suffix: ?[]const u8,
};

// ============================================================================
// Framework Path Patterns
// ============================================================================

/// A framework name can take one of the following four forms:
///   Location/Name.framework/Versions/SomeVersion/Name_Suffix
///   Location/Name.framework/Versions/SomeVersion/Name
///   Location/Name.framework/Name_Suffix
///   Location/Name.framework/Name

/// CPython: STRICT_FRAMEWORK_RE regex pattern
/// (?x)
/// (?P<location>^.*)(?:^|/)
/// (?P<name>
///     (?P<shortname>\w+).framework/
///     (?:Versions/(?P<version>[^/]+)/)?
///     (?P=shortname)
///     (?:_(?P<suffix>[^_]+))?
/// )$

// ============================================================================
// Main Function
// ============================================================================

/// CPython: def framework_info(filename)
/// Parse a framework path and return its components.
///
/// Returns null if the filename doesn't match the framework pattern.
/// Otherwise returns a FrameworkInfo struct with:
///   - location: Directory path before the framework
///   - name: Full framework path from Name.framework/...
///   - shortname: Framework name (without .framework)
///   - version: Version string (optional)
///   - suffix: Suffix string (optional)
pub fn framework_info(filename: []const u8) ?FrameworkInfo {
    // Find .framework/ in the path
    const fw_marker = ".framework/";
    const fw_pos = std.mem.indexOf(u8, filename, fw_marker) orelse return null;

    // Extract shortname (before .framework)
    const before_fw = filename[0..fw_pos];
    const last_sep = std.mem.lastIndexOfScalar(u8, before_fw, '/');
    const shortname_start = if (last_sep) |sep| sep + 1 else 0;
    const shortname = before_fw[shortname_start..];

    // Validate shortname (must be word characters)
    if (shortname.len == 0) return null;
    for (shortname) |c| {
        if (!std.ascii.isAlphanumeric(c) and c != '_') {
            return null;
        }
    }

    // Get location (before shortname)
    const location = if (last_sep) |sep| filename[0..sep] else "";

    // Parse after .framework/
    const after_fw = filename[fw_pos + fw_marker.len ..];

    var version: ?[]const u8 = null;
    var suffix: ?[]const u8 = null;
    var executable_name: []const u8 = after_fw;

    // Check for Versions/X/ pattern
    if (std.mem.startsWith(u8, after_fw, "Versions/")) {
        const versions_suffix = after_fw["Versions/".len..];
        if (std.mem.indexOfScalar(u8, versions_suffix, '/')) |slash| {
            version = versions_suffix[0..slash];
            executable_name = versions_suffix[slash + 1 ..];
        }
    }

    // Executable name should start with shortname
    if (!std.mem.startsWith(u8, executable_name, shortname)) {
        return null;
    }

    // Check for suffix (after shortname_)
    const after_shortname = executable_name[shortname.len..];
    if (after_shortname.len > 0 and after_shortname[0] == '_') {
        suffix = after_shortname[1..];
        // Suffix should not contain underscore
        if (std.mem.indexOfScalar(u8, suffix.?, '_') != null) {
            suffix = null;
        }
    } else if (after_shortname.len > 0) {
        // Must be exactly shortname or shortname_suffix
        return null;
    }

    // Construct the full name (from shortname.framework onwards)
    const name = filename[shortname_start..];

    return FrameworkInfo{
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

test "framework_info basic" {
    const info = framework_info("/System/Library/Frameworks/Foundation.framework/Foundation");
    try std.testing.expect(info != null);
    try std.testing.expectEqualStrings("/System/Library/Frameworks", info.?.location);
    try std.testing.expectEqualStrings("Foundation", info.?.shortname);
    try std.testing.expect(info.?.version == null);
    try std.testing.expect(info.?.suffix == null);
}

test "framework_info with version" {
    const info = framework_info("/System/Library/Frameworks/Python.framework/Versions/3.9/Python");
    try std.testing.expect(info != null);
    try std.testing.expectEqualStrings("Python", info.?.shortname);
    try std.testing.expectEqualStrings("3.9", info.?.version.?);
}

test "framework_info with suffix" {
    const info = framework_info("/Library/Frameworks/Foo.framework/Foo_debug");
    try std.testing.expect(info != null);
    try std.testing.expectEqualStrings("Foo", info.?.shortname);
    try std.testing.expectEqualStrings("debug", info.?.suffix.?);
}

test "framework_info with version and suffix" {
    const info = framework_info("/Library/Frameworks/Bar.framework/Versions/A/Bar_profile");
    try std.testing.expect(info != null);
    try std.testing.expectEqualStrings("Bar", info.?.shortname);
    try std.testing.expectEqualStrings("A", info.?.version.?);
    try std.testing.expectEqualStrings("profile", info.?.suffix.?);
}

test "framework_info non-framework" {
    const info = framework_info("/usr/lib/libfoo.dylib");
    try std.testing.expect(info == null);
}

test "framework_info mismatched name" {
    // Executable name doesn't match framework name
    const info = framework_info("/Library/Frameworks/Foo.framework/Bar");
    try std.testing.expect(info == null);
}

test "framework_info current version" {
    const info = framework_info("/System/Library/Frameworks/CoreFoundation.framework/Versions/Current/CoreFoundation");
    try std.testing.expect(info != null);
    try std.testing.expectEqualStrings("CoreFoundation", info.?.shortname);
    try std.testing.expectEqualStrings("Current", info.?.version.?);
}
