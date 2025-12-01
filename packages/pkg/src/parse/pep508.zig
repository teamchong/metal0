//! PEP 508 Dependency Specifiers
//!
//! Parses dependency strings like:
//! - `numpy`
//! - `numpy>=1.0`
//! - `numpy[dev,test]>=1.0`
//! - `numpy>=1.0; python_version >= "3.8"`
//! - `package @ https://example.com/package.whl`
//!
//! ## Format
//! ```
//! name [extras] [version] [; markers] [@ url]
//! ```
//!
//! Reference: https://peps.python.org/pep-0508/

const std = @import("std");
const pep440 = @import("pep440.zig");

/// A parsed dependency specifier
pub const Dependency = struct {
    name: []const u8,
    extras: []const []const u8 = &[_][]const u8{},
    version_spec: ?pep440.VersionSpec = null,
    markers: ?[]const u8 = null, // Raw marker string (parsed separately if needed)
    url: ?[]const u8 = null, // Direct URL reference

    /// Check if this dependency has any extras
    pub fn hasExtra(self: Dependency, extra: []const u8) bool {
        for (self.extras) |e| {
            if (std.mem.eql(u8, e, extra)) return true;
        }
        return false;
    }

    /// Format as string
    pub fn format(self: Dependency, writer: anytype) !void {
        try writer.writeAll(self.name);

        if (self.extras.len > 0) {
            try writer.writeByte('[');
            for (self.extras, 0..) |extra, i| {
                if (i > 0) try writer.writeByte(',');
                try writer.writeAll(extra);
            }
            try writer.writeByte(']');
        }

        if (self.version_spec) |spec| {
            for (spec.constraints) |c| {
                const op_str: []const u8 = switch (c.op) {
                    .eq => "==",
                    .ne => "!=",
                    .lt => "<",
                    .le => "<=",
                    .gt => ">",
                    .ge => ">=",
                    .compatible => "~=",
                    .arbitrary => "===",
                };
                try writer.writeAll(op_str);
                try c.version.format(writer);
                if (c.wildcard) try writer.writeAll(".*");
            }
        }

        if (self.url) |url| {
            try writer.writeAll(" @ ");
            try writer.writeAll(url);
        }

        if (self.markers) |markers| {
            try writer.writeAll("; ");
            try writer.writeAll(markers);
        }
    }
};

/// Environment markers for conditional dependencies
pub const Marker = struct {
    variable: Variable,
    op: Op,
    value: []const u8,

    pub const Variable = enum {
        os_name,
        sys_platform,
        platform_machine,
        platform_python_implementation,
        platform_release,
        platform_system,
        platform_version,
        python_version,
        python_full_version,
        implementation_name,
        implementation_version,
        extra,
    };

    pub const Op = enum {
        eq, // ==
        ne, // !=
        lt, // <
        le, // <=
        gt, // >
        ge, // >=
        in_, // in
        not_in, // not in
    };

    pub fn variableFromStr(s: []const u8) ?Variable {
        const map = std.StaticStringMap(Variable).initComptime(.{
            .{ "os_name", .os_name },
            .{ "sys_platform", .sys_platform },
            .{ "platform_machine", .platform_machine },
            .{ "platform_python_implementation", .platform_python_implementation },
            .{ "platform_release", .platform_release },
            .{ "platform_system", .platform_system },
            .{ "platform_version", .platform_version },
            .{ "python_version", .python_version },
            .{ "python_full_version", .python_full_version },
            .{ "implementation_name", .implementation_name },
            .{ "implementation_version", .implementation_version },
            .{ "extra", .extra },
        });
        return map.get(s);
    }
};

pub const ParseError = error{
    InvalidDependency,
    InvalidName,
    InvalidExtras,
    InvalidMarkers,
    OutOfMemory,
} || pep440.ParseError;

/// Parse a PEP 508 dependency string
pub fn parseDependency(allocator: std.mem.Allocator, input: []const u8) ParseError!Dependency {
    var s = std.mem.trim(u8, input, " \t\n\r");
    if (s.len == 0) return ParseError.InvalidDependency;

    var dep = Dependency{ .name = "" };

    // Check for URL reference first (name @ url)
    if (std.mem.indexOf(u8, s, " @ ")) |at_pos| {
        const before_at = std.mem.trim(u8, s[0..at_pos], " \t");
        var url_and_rest = s[at_pos + 3 ..];

        // Check for markers after URL (must have space before semicolon)
        // Per PEP 508: "URL references ... ; markers" requires space before ;
        // We look for " ;" pattern - URL can contain ";" internally (e.g., URL params)
        if (std.mem.indexOf(u8, url_and_rest, " ;")) |space_semi| {
            dep.url = std.mem.trim(u8, url_and_rest[0..space_semi], " \t");
            dep.markers = std.mem.trim(u8, url_and_rest[space_semi + 2 ..], " \t");
        } else {
            // No marker - entire remainder is URL
            // Check if URL ends without space before potential marker (invalid)
            // e.g., "url; marker" is invalid, but "url;param=value" is valid URL with semicolon
            const trimmed = std.mem.trimRight(u8, url_and_rest, " \t");
            // Find last semicolon - if it's followed by marker-like content without space, it's invalid
            if (std.mem.lastIndexOf(u8, trimmed, ";")) |last_semi| {
                const after_semi = std.mem.trim(u8, trimmed[last_semi + 1 ..], " \t");
                // Check if what follows looks like a marker (contains == or other marker operators)
                if (std.mem.indexOf(u8, after_semi, "==") != null or
                    std.mem.indexOf(u8, after_semi, "!=") != null or
                    std.mem.indexOf(u8, after_semi, "<=") != null or
                    std.mem.indexOf(u8, after_semi, ">=") != null or
                    std.mem.indexOf(u8, after_semi, " in ") != null or
                    std.mem.indexOf(u8, after_semi, " not ") != null)
                {
                    // This looks like a marker without proper space separator
                    return ParseError.InvalidDependency;
                }
            }
            dep.url = std.mem.trim(u8, url_and_rest, " \t");
        }

        // Parse name and extras from before @
        const name_result = try parseNameAndExtras(allocator, before_at);
        dep.name = name_result.name;
        dep.extras = name_result.extras;
        return dep;
    }

    // Check for markers (;)
    if (std.mem.indexOf(u8, s, ";")) |marker_pos| {
        const marker_str = std.mem.trim(u8, s[marker_pos + 1 ..], " \t");
        // Basic validation: check paren balancing in markers
        var paren_depth: i32 = 0;
        for (marker_str) |c| {
            if (c == '(') paren_depth += 1;
            if (c == ')') paren_depth -= 1;
            if (paren_depth < 0) return ParseError.InvalidMarkers; // Too many closing parens
        }
        if (paren_depth != 0) return ParseError.InvalidMarkers; // Unclosed parens

        // Basic validation: ensure marker contains at least one operator
        if (!containsMarkerOperator(marker_str)) {
            return ParseError.InvalidMarkers;
        }

        dep.markers = marker_str;
        s = s[0..marker_pos];
    }

    // Parse name, extras, and version spec
    const name_result = try parseNameAndExtras(allocator, s);
    dep.name = name_result.name;
    dep.extras = name_result.extras;

    // Parse version spec from remaining string
    if (name_result.remaining.len > 0) {
        dep.version_spec = try pep440.parseSpec(allocator, name_result.remaining);
    }

    return dep;
}

const NameExtrasResult = struct {
    name: []const u8,
    extras: []const []const u8,
    remaining: []const u8,
};

fn parseNameAndExtras(allocator: std.mem.Allocator, input: []const u8) ParseError!NameExtrasResult {
    var s = std.mem.trim(u8, input, " \t");
    var result = NameExtrasResult{
        .name = "",
        .extras = &[_][]const u8{},
        .remaining = "",
    };

    // Find end of name (first non-name character)
    var name_end: usize = 0;
    for (s, 0..) |c, i| {
        if (isNameChar(c)) {
            name_end = i + 1;
        } else {
            break;
        }
    }

    if (name_end == 0) return ParseError.InvalidName;
    result.name = normalizePackageName(s[0..name_end]);
    s = s[name_end..];

    // Parse extras [extra1,extra2]
    s = std.mem.trim(u8, s, " \t");
    if (s.len > 0 and s[0] == '[') {
        const close = std.mem.indexOf(u8, s, "]") orelse return ParseError.InvalidExtras;
        const extras_str = s[1..close];

        var extras = std.ArrayList([]const u8){};
        defer extras.deinit(allocator);

        // Handle empty extras []
        const trimmed_extras = std.mem.trim(u8, extras_str, " \t");
        if (trimmed_extras.len > 0) {
            // Check for trailing comma
            if (std.mem.endsWith(u8, trimmed_extras, ",")) {
                return ParseError.InvalidExtras; // Trailing comma
            }

            var iter = std.mem.splitScalar(u8, extras_str, ',');
            while (iter.next()) |extra| {
                const trimmed = std.mem.trim(u8, extra, " \t");
                if (trimmed.len == 0) {
                    return ParseError.InvalidExtras; // Empty segment between commas
                }
                // Validate extra name: alphanumeric, hyphens, underscores, dots only
                for (trimmed) |c| {
                    if (!std.ascii.isAlphanumeric(c) and c != '-' and c != '_' and c != '.') {
                        return ParseError.InvalidExtras; // Invalid character (e.g., space)
                    }
                }
                try extras.append(allocator, trimmed);
            }
        }

        result.extras = try extras.toOwnedSlice(allocator);
        s = s[close + 1 ..];
    }

    s = std.mem.trim(u8, s, " \t");

    // Handle parenthesized version specifier: name (>=1.0)
    if (s.len > 0 and s[0] == '(') {
        const close = std.mem.lastIndexOf(u8, s, ")") orelse return ParseError.InvalidDependency;
        s = std.mem.trim(u8, s[1..close], " \t");
    }

    // Validate version spec starts with operator, not bare number
    // "name 1.0" is invalid, "name ==1.0" or "name>=1.0" is valid
    if (s.len > 0) {
        const first = s[0];
        if (first != '=' and first != '!' and first != '<' and first != '>' and first != '~') {
            return ParseError.InvalidDependency; // No operator before version
        }
    }

    result.remaining = s;
    return result;
}

fn isNameChar(c: u8) bool {
    return std.ascii.isAlphanumeric(c) or c == '-' or c == '_' or c == '.';
}

/// Check if marker string contains at least one comparison operator
fn containsMarkerOperator(marker: []const u8) bool {
    // Marker operators per PEP 508: ==, !=, <, <=, >, >=, ~=, ===, in, not in
    if (std.mem.indexOf(u8, marker, "==") != null) return true;
    if (std.mem.indexOf(u8, marker, "!=") != null) return true;
    if (std.mem.indexOf(u8, marker, "<=") != null) return true;
    if (std.mem.indexOf(u8, marker, ">=") != null) return true;
    if (std.mem.indexOf(u8, marker, "~=") != null) return true;
    if (std.mem.indexOf(u8, marker, "===") != null) return true;
    // Check for < and > that aren't part of <= or >=
    for (marker, 0..) |c, i| {
        if (c == '<' and (i + 1 >= marker.len or marker[i + 1] != '=')) return true;
        if (c == '>' and (i + 1 >= marker.len or marker[i + 1] != '=')) return true;
    }
    // Check for 'in' and 'not in' as word boundaries
    if (std.mem.indexOf(u8, marker, " in ") != null) return true;
    if (std.mem.indexOf(u8, marker, " not in ") != null) return true;
    return false;
}

/// Normalize package name (PEP 503): lowercase, replace [-_.] with -
fn normalizePackageName(name: []const u8) []const u8 {
    // For now, return as-is. Full normalization would need allocation.
    // Real implementation should: lowercase, replace [-_.] with single -
    return name;
}

/// Free a parsed dependency
pub fn freeDependency(allocator: std.mem.Allocator, dep: *Dependency) void {
    if (dep.extras.len > 0) {
        allocator.free(dep.extras);
    }
    if (dep.version_spec) |*spec| {
        pep440.freeSpec(allocator, spec);
    }
}

// ============================================================================
// Tests
// ============================================================================

test "parse simple dependency" {
    const allocator = std.testing.allocator;

    var dep = try parseDependency(allocator, "numpy");
    defer freeDependency(allocator, &dep);

    try std.testing.expectEqualStrings("numpy", dep.name);
    try std.testing.expectEqual(@as(usize, 0), dep.extras.len);
    try std.testing.expect(dep.version_spec == null);
}

test "parse dependency with version" {
    const allocator = std.testing.allocator;

    var dep = try parseDependency(allocator, "numpy>=1.20");
    defer freeDependency(allocator, &dep);

    try std.testing.expectEqualStrings("numpy", dep.name);
    try std.testing.expect(dep.version_spec != null);
    try std.testing.expectEqual(@as(usize, 1), dep.version_spec.?.constraints.len);
    try std.testing.expectEqual(pep440.Operator.ge, dep.version_spec.?.constraints[0].op);
}

test "parse dependency with extras" {
    const allocator = std.testing.allocator;

    var dep = try parseDependency(allocator, "package[dev,test]>=1.0");
    defer freeDependency(allocator, &dep);

    try std.testing.expectEqualStrings("package", dep.name);
    try std.testing.expectEqual(@as(usize, 2), dep.extras.len);
    try std.testing.expectEqualStrings("dev", dep.extras[0]);
    try std.testing.expectEqualStrings("test", dep.extras[1]);
}

test "parse dependency with markers" {
    const allocator = std.testing.allocator;

    var dep = try parseDependency(allocator, "numpy>=1.0; python_version >= \"3.8\"");
    defer freeDependency(allocator, &dep);

    try std.testing.expectEqualStrings("numpy", dep.name);
    try std.testing.expect(dep.markers != null);
    try std.testing.expectEqualStrings("python_version >= \"3.8\"", dep.markers.?);
}

test "parse dependency with URL" {
    const allocator = std.testing.allocator;

    var dep = try parseDependency(allocator, "package @ https://example.com/package.whl");
    defer freeDependency(allocator, &dep);

    try std.testing.expectEqualStrings("package", dep.name);
    try std.testing.expect(dep.url != null);
    try std.testing.expectEqualStrings("https://example.com/package.whl", dep.url.?);
}

test "parse complex dependency" {
    const allocator = std.testing.allocator;

    var dep = try parseDependency(allocator, "requests[security,socks]>=2.20,<3.0; python_version >= \"3.6\"");
    defer freeDependency(allocator, &dep);

    try std.testing.expectEqualStrings("requests", dep.name);
    try std.testing.expectEqual(@as(usize, 2), dep.extras.len);
    try std.testing.expect(dep.version_spec != null);
    try std.testing.expectEqual(@as(usize, 2), dep.version_spec.?.constraints.len);
    try std.testing.expect(dep.markers != null);
}
