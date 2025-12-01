//! PEP 508 Conformance Tests
//!
//! Test cases extracted from Python packaging library:
//! https://github.com/pypa/packaging/blob/main/tests/test_requirements.py
//!
//! These tests ensure our parser matches the reference implementation.

const std = @import("std");
const pep508 = @import("pep508.zig");

// ============================================================================
// Valid dependency specifiers - MUST parse successfully
// ============================================================================

const VALID_DEPENDENCIES = [_][]const u8{
    // Basic names
    "package",
    "pAcKaGe",
    "Package",
    "foo-bar.quux_bAz",
    "installer",
    "android12",

    // With extras
    "name[a]",
    "name[a,b]",
    "name[a, b]",
    "name[a,B,CDEF123]",
    "name[]", // Empty extras

    // With version specifiers
    "name==1.0",
    "name>=1.0",
    "name<=1.0",
    "name>1.0",
    "name<1.0",
    "name!=1.0",
    "name~=1.0",
    "name===arbitrarystring",
    "name==1.0-alpha",
    "name<=1!3.0.0.rc2",
    "name>2.2,<3",
    "name (==1.0)",
    "name(>2.2,<3)",
    "name()", // Empty specifier in parens
    "name ==2.8.*",

    // With URL
    "name @ https://example.com/packagename.zip",
    "name @ ssh://user:pass%20word@example.com/packagename.zip",
    "name @ https://example.com/name;v=1.1/?query=foo&bar=baz#blah",
    "name @ git+ssh://git.example.com/MyProject",
    "name @ git+ssh://git@github.com:pypa/packaging.git",
    "name @ git+https://git.example.com/MyProject.git@master",
    "name @ git+https://git.example.com/MyProject.git@v1.0",
    "name @ git+https://git.example.com/MyProject.git@refs/pull/123/head",
    "name @ gopher:/foo/com",
    "name @ file:///absolute/path",
    "name @ file://.",
    "name @ file:.",
    "name @ file:/.",

    // With markers
    "name; python_version>='3.3'",
    "name; python_version >= '3.3'",
    "name; (python_version>=\"3.4\") and extra==\"oursql\"",
    "name; sys_platform!='linux' and(os_name=='linux' or python_version>='3.3')",
    "name; python_implementation == ''",
    "name; platform_python_implementation == ''",
    "name; os.name == 'linux'",
    "name; os_name == 'linux'",
    "name; '8' in platform.version",
    "name; '8' not in platform.version",

    // Complex combinations
    "packaging>20.1",
    "requests[security, tests]>=2.8.1,==2.8.*;python_version<\"2.7\"",
    "requests [security,tests] >= 2.8.1, == 2.8.* ; python_version < \"2.7\"",
    "importlib-metadata; python_version<\"3.8\"",
    "importlib-metadata; python_version<'3.8'",
    "appdirs>=1.4.4,<2; os_name==\"posix\" and extra==\"testing\"",
    "appdirs>=1.4.4,<2; os_name == 'posix' and extra == 'testing'",
    "foobar[quux]<2,>=3; os_name=='a'",
};

// ============================================================================
// Invalid dependency specifiers - MUST fail to parse
// ============================================================================

const INVALID_DEPENDENCIES = [_][]const u8{
    // Empty string
    "",

    // No name
    "==0.0",

    // Missing comma in extras
    "name[bar baz]",

    // Trailing comma in extras
    "name[bar, baz,]",

    // Unclosed bracket
    "name[bar, baz >= 1.0",
    "name[bar, baz",

    // Unclosed paren
    "name (>= 1.0",

    // Invalid prefix match usage
    "black (>=20.*) ; extra == 'format'",

    // Invalid local version with wrong operator
    "name >= 1.0+local.version.label",
    "name <= 1.0+local.version.label",
    "name > 1.0+local.version.label",
    "name < 1.0+local.version.label",
    "name ~= 1.0+local.version.label",

    // No space after URL before marker
    "name @ https://example.com/; extra == 'example'",

    // Unclosed marker paren
    "name; (extra == 'example'",

    // No URL after @
    "name @ ",

    // TODO: These require full marker parsing which we haven't implemented yet
    // Invalid marker variable
    // "name; invalid_name",
    // "name; '3.7' <= invalid_name",

    // Invalid marker operators
    // "name; '3.7' notin python_version",
    // "name; '3.6'inpython_version",
    // "name; '3.7' not python_version",
    // "name; '3.7' ~ python_version",

    // Legacy version outside ===
    "name==1.0.org1",

    // Missing version after operator
    "name==",

    // Missing operator
    "name 1.0",

    // Random char after specifier
    "name >= 1.0 #",

    // Missing comma in specifier
    "name >= 1.0 <= 2.0",
};

// ============================================================================
// Tests
// ============================================================================

test "all VALID_DEPENDENCIES parse successfully" {
    const allocator = std.testing.allocator;

    for (VALID_DEPENDENCIES) |dep_str| {
        var dep = pep508.parseDependency(allocator, dep_str) catch |err| {
            std.debug.print("Failed to parse valid dependency: '{s}' with error: {}\n", .{ dep_str, err });
            return err;
        };
        defer pep508.freeDependency(allocator, &dep);
    }
}

test "all INVALID_DEPENDENCIES fail to parse" {
    const allocator = std.testing.allocator;

    for (INVALID_DEPENDENCIES) |dep_str| {
        const result = pep508.parseDependency(allocator, dep_str);
        if (result) |*dep| {
            pep508.freeDependency(allocator, @constCast(dep));
            std.debug.print("Should have failed to parse: '{s}'\n", .{dep_str});
            return error.ShouldHaveFailed;
        } else |_| {
            // Expected - invalid dependency should fail
        }
    }
}

test "name parsing" {
    const allocator = std.testing.allocator;

    const cases = [_]struct { input: []const u8, expected_name: []const u8 }{
        .{ .input = "package", .expected_name = "package" },
        .{ .input = "Package", .expected_name = "Package" },
        .{ .input = "foo-bar.quux_bAz", .expected_name = "foo-bar.quux_bAz" },
        .{ .input = "android12", .expected_name = "android12" },
        .{ .input = "numpy>=1.0", .expected_name = "numpy" },
        .{ .input = "requests[security]", .expected_name = "requests" },
    };

    for (cases) |case| {
        var dep = try pep508.parseDependency(allocator, case.input);
        defer pep508.freeDependency(allocator, &dep);

        if (!std.mem.eql(u8, dep.name, case.expected_name)) {
            std.debug.print("Name mismatch for '{s}': expected '{s}', got '{s}'\n", .{ case.input, case.expected_name, dep.name });
            return error.NameMismatch;
        }
    }
}

test "extras parsing" {
    const allocator = std.testing.allocator;

    const Case = struct {
        input: []const u8,
        expected: []const []const u8,
    };

    const cases = [_]Case{
        .{ .input = "name", .expected = &[_][]const u8{} },
        .{ .input = "name[a]", .expected = &[_][]const u8{"a"} },
        .{ .input = "name[a,b]", .expected = &[_][]const u8{ "a", "b" } },
        .{ .input = "name[a, b]", .expected = &[_][]const u8{ "a", "b" } },
        .{ .input = "name[]", .expected = &[_][]const u8{} },
    };

    for (cases) |case| {
        var dep = try pep508.parseDependency(allocator, case.input);
        defer pep508.freeDependency(allocator, &dep);

        const extras = dep.extras;
        if (extras.len != case.expected.len) {
            std.debug.print("Extras count mismatch for '{s}': expected {}, got {}\n", .{ case.input, case.expected.len, extras.len });
            return error.ExtrasMismatch;
        }

        for (extras, 0..) |extra, i| {
            if (!std.mem.eql(u8, extra, case.expected[i])) {
                std.debug.print("Extra mismatch for '{s}' at index {}: expected '{s}', got '{s}'\n", .{ case.input, i, case.expected[i], extra });
                return error.ExtrasMismatch;
            }
        }
    }
}

test "version specifier parsing" {
    const allocator = std.testing.allocator;

    const cases = [_]struct { input: []const u8, has_version: bool }{
        .{ .input = "name", .has_version = false },
        .{ .input = "name==1.0", .has_version = true },
        .{ .input = "name>=1.0,<2.0", .has_version = true },
        .{ .input = "name[extra]>=1.0", .has_version = true },
        .{ .input = "name @ https://example.com/", .has_version = false },
    };

    for (cases) |case| {
        var dep = try pep508.parseDependency(allocator, case.input);
        defer pep508.freeDependency(allocator, &dep);

        const has_version = dep.version_spec != null;
        if (has_version != case.has_version) {
            std.debug.print("Version spec mismatch for '{s}': expected {}, got {}\n", .{ case.input, case.has_version, has_version });
            return error.VersionMismatch;
        }
    }
}

test "URL parsing" {
    const allocator = std.testing.allocator;

    const cases = [_]struct { input: []const u8, expected_url: ?[]const u8 }{
        .{ .input = "name", .expected_url = null },
        .{ .input = "name @ https://example.com/pkg.zip", .expected_url = "https://example.com/pkg.zip" },
        .{ .input = "name @ file:///absolute/path", .expected_url = "file:///absolute/path" },
        .{ .input = "name @ git+https://github.com/foo/bar.git", .expected_url = "git+https://github.com/foo/bar.git" },
    };

    for (cases) |case| {
        var dep = try pep508.parseDependency(allocator, case.input);
        defer pep508.freeDependency(allocator, &dep);

        if (case.expected_url == null) {
            if (dep.url != null) {
                std.debug.print("Expected no URL for '{s}', got '{s}'\n", .{ case.input, dep.url.? });
                return error.URLMismatch;
            }
        } else {
            if (dep.url == null) {
                std.debug.print("Expected URL for '{s}', got null\n", .{case.input});
                return error.URLMismatch;
            }
            if (!std.mem.eql(u8, dep.url.?, case.expected_url.?)) {
                std.debug.print("URL mismatch for '{s}': expected '{s}', got '{s}'\n", .{ case.input, case.expected_url.?, dep.url.? });
                return error.URLMismatch;
            }
        }
    }
}

test "marker parsing" {
    const allocator = std.testing.allocator;

    const cases = [_]struct { input: []const u8, has_marker: bool }{
        .{ .input = "name", .has_marker = false },
        .{ .input = "name>=1.0", .has_marker = false },
        .{ .input = "name; python_version>='3.6'", .has_marker = true },
        .{ .input = "name>=1.0; os_name=='linux'", .has_marker = true },
        .{ .input = "name @ https://example.com/ ; extra=='test'", .has_marker = true },
    };

    for (cases) |case| {
        var dep = try pep508.parseDependency(allocator, case.input);
        defer pep508.freeDependency(allocator, &dep);

        const has_marker = dep.markers != null;
        if (has_marker != case.has_marker) {
            std.debug.print("Marker mismatch for '{s}': expected {}, got {}\n", .{ case.input, case.has_marker, has_marker });
            return error.MarkerMismatch;
        }
    }
}

test "equivalent names with underscores and dashes" {
    const allocator = std.testing.allocator;

    // Per PEP 508, these should be equivalent (case-insensitive, -/_ treated same)
    var dep1 = try pep508.parseDependency(allocator, "scikit-learn==1.0.1");
    defer pep508.freeDependency(allocator, &dep1);

    var dep2 = try pep508.parseDependency(allocator, "scikit_learn==1.0.1");
    defer pep508.freeDependency(allocator, &dep2);

    // Names should be stored as-is (not normalized)
    try std.testing.expectEqualStrings("scikit-learn", dep1.name);
    try std.testing.expectEqualStrings("scikit_learn", dep2.name);
}
