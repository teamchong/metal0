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
// PEP 508 Marker Evaluation
// ============================================================================

/// Environment for marker evaluation
pub const Environment = struct {
    os_name: []const u8 = "posix", // "posix", "nt", "java"
    sys_platform: []const u8 = "darwin", // "darwin", "linux", "win32"
    platform_machine: []const u8 = "arm64", // "x86_64", "arm64", "aarch64"
    platform_python_implementation: []const u8 = "CPython",
    platform_release: []const u8 = "",
    platform_system: []const u8 = "Darwin", // "Darwin", "Linux", "Windows"
    platform_version: []const u8 = "",
    python_version: []const u8 = "3.11", // Major.minor only
    python_full_version: []const u8 = "3.11.0",
    implementation_name: []const u8 = "cpython",
    implementation_version: []const u8 = "3.11.0",
    extra: ?[]const u8 = null, // Currently active extra

    /// Default environment for Python 3.11 on macOS ARM64
    pub const default = Environment{};

    /// Get value for a marker variable
    pub fn getValue(self: Environment, variable: Marker.Variable) []const u8 {
        return switch (variable) {
            .os_name => self.os_name,
            .sys_platform => self.sys_platform,
            .platform_machine => self.platform_machine,
            .platform_python_implementation => self.platform_python_implementation,
            .platform_release => self.platform_release,
            .platform_system => self.platform_system,
            .platform_version => self.platform_version,
            .python_version => self.python_version,
            .python_full_version => self.python_full_version,
            .implementation_name => self.implementation_name,
            .implementation_version => self.implementation_version,
            .extra => self.extra orelse "",
        };
    }
};

/// Evaluate a marker expression against an environment
/// Returns true if the marker matches, false otherwise
/// On parse error, returns true (conservative: include the dependency)
pub fn evaluateMarker(marker: []const u8, env: Environment) bool {
    return evaluateMarkerExpr(marker, env) catch true;
}

/// Evaluate marker expression (can return error on parse failure)
fn evaluateMarkerExpr(marker: []const u8, env: Environment) ParseError!bool {
    const s = std.mem.trim(u8, marker, " \t");
    if (s.len == 0) return true;

    // Parse OR expressions (lowest precedence)
    return parseOrExpr(s, env);
}

/// Parse OR expression: expr ("or" expr)*
fn parseOrExpr(input: []const u8, env: Environment) ParseError!bool {
    var s = input;
    var result = try parseAndExpr(s, env, &s);

    while (s.len > 0) {
        const trimmed = std.mem.trim(u8, s, " \t");
        if (std.mem.startsWith(u8, trimmed, "or ") or std.mem.startsWith(u8, trimmed, "or\t")) {
            s = trimmed[3..];
            const right = try parseAndExpr(s, env, &s);
            result = result or right;
        } else {
            break;
        }
    }
    return result;
}

/// Parse AND expression: term ("and" term)*
fn parseAndExpr(input: []const u8, env: Environment, rest: *[]const u8) ParseError!bool {
    var s = std.mem.trim(u8, input, " \t");
    var result = try parseTerm(s, env, &s);

    while (s.len > 0) {
        const trimmed = std.mem.trim(u8, s, " \t");
        if (std.mem.startsWith(u8, trimmed, "and ") or std.mem.startsWith(u8, trimmed, "and\t")) {
            s = trimmed[4..];
            const right = try parseTerm(s, env, &s);
            result = result and right;
        } else {
            break;
        }
    }
    rest.* = s;
    return result;
}

/// Parse term: "(" expr ")" | comparison
fn parseTerm(input: []const u8, env: Environment, rest: *[]const u8) ParseError!bool {
    var s = std.mem.trim(u8, input, " \t");

    // Handle parentheses
    if (s.len > 0 and s[0] == '(') {
        // Find matching close paren
        var depth: i32 = 1;
        var i: usize = 1;
        while (i < s.len and depth > 0) : (i += 1) {
            if (s[i] == '(') depth += 1;
            if (s[i] == ')') depth -= 1;
        }
        if (depth != 0) return ParseError.InvalidMarkers;

        const inner = s[1 .. i - 1];
        const result = try evaluateMarkerExpr(inner, env);
        rest.* = s[i..];
        return result;
    }

    // Parse comparison
    return parseComparison(s, env, rest);
}

/// Parse comparison: variable op value | value op variable
fn parseComparison(input: []const u8, env: Environment, rest: *[]const u8) ParseError!bool {
    var s = std.mem.trim(u8, input, " \t");

    // Extract left operand (variable or quoted string)
    const left_result = try parseOperand(s);
    s = std.mem.trim(u8, s[left_result.consumed..], " \t");

    // Extract operator
    const op_result = parseOperator(s) orelse return ParseError.InvalidMarkers;
    s = std.mem.trim(u8, s[op_result.consumed..], " \t");

    // Extract right operand
    const right_result = try parseOperand(s);
    rest.* = s[right_result.consumed..];

    // Get actual values
    const left_val = if (left_result.variable) |v| env.getValue(v) else left_result.literal;
    const right_val = if (right_result.variable) |v| env.getValue(v) else right_result.literal;

    // Evaluate comparison
    return evaluateComparison(left_val, op_result.op, right_val);
}

const OperandResult = struct {
    variable: ?Marker.Variable,
    literal: []const u8,
    consumed: usize,
};

fn parseOperand(input: []const u8) ParseError!OperandResult {
    const s = std.mem.trim(u8, input, " \t");
    const skip = input.len - s.len;

    // Quoted string
    if (s.len > 0 and (s[0] == '"' or s[0] == '\'')) {
        const quote = s[0];
        var i: usize = 1;
        while (i < s.len and s[i] != quote) : (i += 1) {}
        if (i >= s.len) return ParseError.InvalidMarkers;
        return .{
            .variable = null,
            .literal = s[1..i],
            .consumed = skip + i + 1,
        };
    }

    // Variable name
    var i: usize = 0;
    while (i < s.len and (std.ascii.isAlphanumeric(s[i]) or s[i] == '_')) : (i += 1) {}
    if (i == 0) return ParseError.InvalidMarkers;

    const name = s[0..i];
    if (Marker.variableFromStr(name)) |v| {
        return .{
            .variable = v,
            .literal = "",
            .consumed = skip + i,
        };
    }

    return ParseError.InvalidMarkers;
}

const OperatorResult = struct {
    op: Marker.Op,
    consumed: usize,
};

fn parseOperator(input: []const u8) ?OperatorResult {
    const s = std.mem.trim(u8, input, " \t");
    const skip = input.len - s.len;

    // Multi-char operators first
    if (s.len >= 6 and std.mem.startsWith(u8, s, "not in")) {
        return .{ .op = .not_in, .consumed = skip + 6 };
    }
    if (s.len >= 2) {
        if (std.mem.startsWith(u8, s, "==")) return .{ .op = .eq, .consumed = skip + 2 };
        if (std.mem.startsWith(u8, s, "!=")) return .{ .op = .ne, .consumed = skip + 2 };
        if (std.mem.startsWith(u8, s, "<=")) return .{ .op = .le, .consumed = skip + 2 };
        if (std.mem.startsWith(u8, s, ">=")) return .{ .op = .ge, .consumed = skip + 2 };
        if (std.mem.startsWith(u8, s, "in")) return .{ .op = .in_, .consumed = skip + 2 };
    }
    if (s.len >= 1) {
        if (s[0] == '<') return .{ .op = .lt, .consumed = skip + 1 };
        if (s[0] == '>') return .{ .op = .gt, .consumed = skip + 1 };
    }
    return null;
}

/// Evaluate a comparison between two string values
fn evaluateComparison(left: []const u8, op: Marker.Op, right: []const u8) bool {
    return switch (op) {
        .eq => std.mem.eql(u8, left, right),
        .ne => !std.mem.eql(u8, left, right),
        .lt => compareVersionStrings(left, right) == .lt,
        .le => compareVersionStrings(left, right) != .gt,
        .gt => compareVersionStrings(left, right) == .gt,
        .ge => compareVersionStrings(left, right) != .lt,
        .in_ => std.mem.indexOf(u8, right, left) != null,
        .not_in => std.mem.indexOf(u8, right, left) == null,
    };
}

/// Compare version-like strings (e.g., "3.11" vs "3.8")
fn compareVersionStrings(a: []const u8, b: []const u8) std.math.Order {
    // Try to parse as versions for proper comparison
    var a_parts = std.mem.splitScalar(u8, a, '.');
    var b_parts = std.mem.splitScalar(u8, b, '.');

    while (true) {
        const a_part = a_parts.next();
        const b_part = b_parts.next();

        if (a_part == null and b_part == null) return .eq;
        if (a_part == null) return .lt; // a is shorter, treat as less
        if (b_part == null) return .gt; // b is shorter, treat as greater

        const a_num = std.fmt.parseInt(i32, a_part.?, 10) catch {
            // Fall back to string comparison
            return std.mem.order(u8, a, b);
        };
        const b_num = std.fmt.parseInt(i32, b_part.?, 10) catch {
            return std.mem.order(u8, a, b);
        };

        if (a_num < b_num) return .lt;
        if (a_num > b_num) return .gt;
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

// ============================================================================
// Marker Evaluation Tests
// ============================================================================

test "marker: python_version comparison" {
    const env = Environment.default; // python_version = "3.11"

    // Should match
    try std.testing.expect(evaluateMarker("python_version >= \"3.8\"", env));
    try std.testing.expect(evaluateMarker("python_version > \"3.0\"", env));
    try std.testing.expect(evaluateMarker("python_version == \"3.11\"", env));
    try std.testing.expect(evaluateMarker("python_version != \"2.7\"", env));
    try std.testing.expect(evaluateMarker("python_version < \"4.0\"", env));
    try std.testing.expect(evaluateMarker("python_version <= \"3.11\"", env));

    // Should not match (Python 2 compatibility)
    try std.testing.expect(!evaluateMarker("python_version < \"3\"", env));
    try std.testing.expect(!evaluateMarker("python_version < \"3.0\"", env));
    try std.testing.expect(!evaluateMarker("python_version == \"2.7\"", env));
}

test "marker: sys_platform comparison" {
    const env = Environment.default; // sys_platform = "darwin"

    try std.testing.expect(evaluateMarker("sys_platform == \"darwin\"", env));
    try std.testing.expect(!evaluateMarker("sys_platform == \"win32\"", env));
    try std.testing.expect(!evaluateMarker("sys_platform == \"linux\"", env));
    try std.testing.expect(evaluateMarker("sys_platform != \"win32\"", env));
}

test "marker: and expression" {
    const env = Environment.default;

    try std.testing.expect(evaluateMarker("python_version >= \"3.8\" and sys_platform == \"darwin\"", env));
    try std.testing.expect(!evaluateMarker("python_version >= \"3.8\" and sys_platform == \"win32\"", env));
    try std.testing.expect(!evaluateMarker("python_version < \"3\" and sys_platform == \"darwin\"", env));
}

test "marker: or expression" {
    const env = Environment.default;

    try std.testing.expect(evaluateMarker("sys_platform == \"win32\" or sys_platform == \"darwin\"", env));
    try std.testing.expect(evaluateMarker("python_version < \"3\" or python_version >= \"3.8\"", env));
    try std.testing.expect(!evaluateMarker("sys_platform == \"win32\" or sys_platform == \"linux\"", env));
}

test "marker: parentheses" {
    const env = Environment.default;

    try std.testing.expect(evaluateMarker("(python_version >= \"3.8\")", env));
    try std.testing.expect(evaluateMarker("(python_version >= \"3.8\" and sys_platform == \"darwin\")", env));
    try std.testing.expect(evaluateMarker("(sys_platform == \"win32\") or (sys_platform == \"darwin\")", env));
}

test "marker: version string comparison" {
    // Test compareVersionStrings directly
    try std.testing.expectEqual(std.math.Order.gt, compareVersionStrings("3.11", "3.8"));
    try std.testing.expectEqual(std.math.Order.lt, compareVersionStrings("3.8", "3.11"));
    try std.testing.expectEqual(std.math.Order.eq, compareVersionStrings("3.11", "3.11"));
    try std.testing.expectEqual(std.math.Order.gt, compareVersionStrings("3.11", "3"));
    try std.testing.expectEqual(std.math.Order.lt, compareVersionStrings("2.7", "3.0"));
}
