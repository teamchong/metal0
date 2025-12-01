//! PEP 440 Conformance Tests
//!
//! Test cases extracted from Python packaging library:
//! https://github.com/pypa/packaging/blob/main/tests/test_version.py
//!
//! These tests ensure our parser matches the reference implementation.

const std = @import("std");
const pep440 = @import("pep440.zig");

// ============================================================================
// VERSIONS list from packaging library - MUST be in sorted order
// These represent valid PEP 440 versions from lowest to highest
// ============================================================================

const VERSIONS = [_][]const u8{
    // Implicit epoch of 0
    "1.0.dev456",
    "1.0a1",
    "1.0a2.dev456",
    "1.0a12.dev456",
    "1.0a12",
    "1.0b1.dev456",
    "1.0b2",
    "1.0b2.post345.dev456",
    "1.0b2.post345",
    // "1.0b2-346", // Normalized form - skip for now (needs normalization)
    "1.0c1.dev456",
    "1.0c1",
    "1.0rc2",
    "1.0c3",
    "1.0",
    "1.0.post456.dev34",
    "1.0.post456",
    "1.1.dev1",
    "1.2+123abc",
    "1.2+123abc456",
    "1.2+abc",
    "1.2+abc123",
    "1.2+abc123def",
    "1.2+1234.abc",
    "1.2+123456",
    // "1.2.r32+123456", // post release alias - needs normalization
    // "1.2.rev33+123456", // post release alias - needs normalization
    // Explicit epoch of 1
    "1!1.0.dev456",
    "1!1.0a1",
    "1!1.0a2.dev456",
    "1!1.0a12.dev456",
    "1!1.0a12",
    "1!1.0b1.dev456",
    "1!1.0b2",
    "1!1.0b2.post345.dev456",
    "1!1.0b2.post345",
    // "1!1.0b2-346", // Normalized form
    "1!1.0c1.dev456",
    "1!1.0c1",
    "1!1.0rc2",
    "1!1.0c3",
    "1!1.0",
    "1!1.0.post456.dev34",
    "1!1.0.post456",
    "1!1.1.dev1",
    "1!1.2+123abc",
    "1!1.2+123abc456",
    "1!1.2+abc",
    "1!1.2+abc123",
    "1!1.2+abc123def",
    "1!1.2+1234.abc",
    "1!1.2+123456",
};

// ============================================================================
// Invalid versions - MUST fail to parse
// ============================================================================

const INVALID_VERSIONS = [_][]const u8{
    // Non sensical versions
    "french toast",
    // Empty
    "",
    // Just text
    "abc",
    "hello.world",
    // Invalid local versions
    "1.0+a+",
    "1.0++",
    "1.0+_foobar",
    "1.0+foo&asd",
    "1.0+1+1",
};

// ============================================================================
// Tests
// ============================================================================

test "all VERSIONS are valid and parseable" {
    const allocator = std.testing.allocator;

    for (VERSIONS) |version_str| {
        var v = pep440.parseVersion(allocator, version_str) catch |err| {
            std.debug.print("Failed to parse valid version: '{s}' with error: {}\n", .{ version_str, err });
            return err;
        };
        defer pep440.freeVersion(allocator, &v);
    }
}

test "VERSIONS are in sorted order" {
    const allocator = std.testing.allocator;

    var prev: ?pep440.Version = null;
    var prev_str: []const u8 = "";

    for (VERSIONS) |version_str| {
        var v = try pep440.parseVersion(allocator, version_str);
        defer pep440.freeVersion(allocator, &v);

        if (prev) |p| {
            const order = p.compare(v);
            if (order != .lt) {
                std.debug.print("Version order violation: '{s}' should be < '{s}'\n", .{ prev_str, version_str });
                // Don't free prev here since we're in an error path
                return error.VersionOrderViolation;
            }
            pep440.freeVersion(allocator, @constCast(&p));
        }

        // Store current as prev for next iteration
        prev = try pep440.parseVersion(allocator, version_str);
        prev_str = version_str;
    }

    // Free the last prev
    if (prev) |*p| {
        pep440.freeVersion(allocator, @constCast(p));
    }
}

test "invalid versions fail to parse" {
    const allocator = std.testing.allocator;

    for (INVALID_VERSIONS) |version_str| {
        const result = pep440.parseVersion(allocator, version_str);
        if (result) |*v| {
            pep440.freeVersion(allocator, @constCast(v));
            std.debug.print("Should have failed to parse: '{s}'\n", .{version_str});
            return error.ShouldHaveFailed;
        } else |_| {
            // Expected - invalid version should fail
        }
    }
}

test "epoch parsing" {
    const allocator = std.testing.allocator;

    const cases = [_]struct { input: []const u8, expected_epoch: u32 }{
        .{ .input = "1.0", .expected_epoch = 0 },
        .{ .input = "1.0.dev0", .expected_epoch = 0 },
        .{ .input = "1!1.0", .expected_epoch = 1 },
        .{ .input = "1!1.0.dev6", .expected_epoch = 1 },
        .{ .input = "7!1.0", .expected_epoch = 7 },
        .{ .input = "1.0+deadbeef", .expected_epoch = 0 },
        .{ .input = "1!1.0+deadbeef", .expected_epoch = 1 },
    };

    for (cases) |case| {
        var v = try pep440.parseVersion(allocator, case.input);
        defer pep440.freeVersion(allocator, &v);

        if (v.epoch != case.expected_epoch) {
            std.debug.print("Epoch mismatch for '{s}': expected {}, got {}\n", .{ case.input, case.expected_epoch, v.epoch });
            return error.EpochMismatch;
        }
    }
}

test "release parsing" {
    const allocator = std.testing.allocator;

    const cases = [_]struct { input: []const u8, expected: []const u32 }{
        .{ .input = "1.0", .expected = &[_]u32{ 1, 0 } },
        .{ .input = "1.0a1", .expected = &[_]u32{ 1, 0 } },
        .{ .input = "1.0.1", .expected = &[_]u32{ 1, 0, 1 } },
        .{ .input = "2.3.4.5", .expected = &[_]u32{ 2, 3, 4, 5 } },
        .{ .input = "1!1.0", .expected = &[_]u32{ 1, 0 } },
    };

    for (cases) |case| {
        var v = try pep440.parseVersion(allocator, case.input);
        defer pep440.freeVersion(allocator, &v);

        if (v.release.len != case.expected.len) {
            std.debug.print("Release length mismatch for '{s}': expected {}, got {}\n", .{ case.input, case.expected.len, v.release.len });
            return error.ReleaseMismatch;
        }

        for (v.release, 0..) |seg, i| {
            if (seg != case.expected[i]) {
                std.debug.print("Release segment mismatch for '{s}' at index {}: expected {}, got {}\n", .{ case.input, i, case.expected[i], seg });
                return error.ReleaseMismatch;
            }
        }
    }
}

test "pre-release parsing" {
    const allocator = std.testing.allocator;

    const cases = [_]struct {
        input: []const u8,
        kind: ?pep440.Version.PreRelease.PreKind,
        num: ?u32,
    }{
        .{ .input = "1.0", .kind = null, .num = null },
        .{ .input = "1.0a1", .kind = .alpha, .num = 1 },
        .{ .input = "1.0b2", .kind = .beta, .num = 2 },
        .{ .input = "1.0rc3", .kind = .rc, .num = 3 },
        .{ .input = "1.0c4", .kind = .rc, .num = 4 }, // c is alias for rc
        .{ .input = "1.0a12", .kind = .alpha, .num = 12 },
        .{ .input = "1!1.0a1", .kind = .alpha, .num = 1 },
        .{ .input = "1.0.post1", .kind = null, .num = null },
    };

    for (cases) |case| {
        var v = try pep440.parseVersion(allocator, case.input);
        defer pep440.freeVersion(allocator, &v);

        if (case.kind == null) {
            if (v.pre != null) {
                std.debug.print("Expected no pre-release for '{s}', got {?}\n", .{ case.input, v.pre });
                return error.PreReleaseMismatch;
            }
        } else {
            if (v.pre == null) {
                std.debug.print("Expected pre-release for '{s}', got null\n", .{case.input});
                return error.PreReleaseMismatch;
            }
            if (v.pre.?.kind != case.kind.?) {
                std.debug.print("Pre-release kind mismatch for '{s}'\n", .{case.input});
                return error.PreReleaseMismatch;
            }
            if (v.pre.?.num != case.num.?) {
                std.debug.print("Pre-release num mismatch for '{s}': expected {?}, got {}\n", .{ case.input, case.num, v.pre.?.num });
                return error.PreReleaseMismatch;
            }
        }
    }
}

test "post-release parsing" {
    const allocator = std.testing.allocator;

    const cases = [_]struct { input: []const u8, expected: ?u32 }{
        .{ .input = "1.0", .expected = null },
        .{ .input = "1.0.post1", .expected = 1 },
        .{ .input = "1.0.post456", .expected = 456 },
        .{ .input = "1.0a1.post5", .expected = 5 },
        .{ .input = "1!1.0.post5", .expected = 5 },
    };

    for (cases) |case| {
        var v = try pep440.parseVersion(allocator, case.input);
        defer pep440.freeVersion(allocator, &v);

        if (v.post != case.expected) {
            std.debug.print("Post mismatch for '{s}': expected {?}, got {?}\n", .{ case.input, case.expected, v.post });
            return error.PostMismatch;
        }
    }
}

test "dev-release parsing" {
    const allocator = std.testing.allocator;

    const cases = [_]struct { input: []const u8, expected: ?u32 }{
        .{ .input = "1.0", .expected = null },
        .{ .input = "1.0.dev0", .expected = 0 },
        .{ .input = "1.0.dev6", .expected = 6 },
        .{ .input = "1.0.dev456", .expected = 456 },
        .{ .input = "1.0a1.post5.dev6", .expected = 6 },
        .{ .input = "1!1.0.dev6", .expected = 6 },
    };

    for (cases) |case| {
        var v = try pep440.parseVersion(allocator, case.input);
        defer pep440.freeVersion(allocator, &v);

        if (v.dev != case.expected) {
            std.debug.print("Dev mismatch for '{s}': expected {?}, got {?}\n", .{ case.input, case.expected, v.dev });
            return error.DevMismatch;
        }
    }
}

test "local version parsing" {
    const allocator = std.testing.allocator;

    const cases = [_]struct { input: []const u8, expected: ?[]const u8 }{
        .{ .input = "1.0", .expected = null },
        .{ .input = "1.0+deadbeef", .expected = "deadbeef" },
        .{ .input = "1.0+abc123", .expected = "abc123" },
        .{ .input = "1.0+1234.abc", .expected = "1234.abc" },
        .{ .input = "1!1.0+deadbeef", .expected = "deadbeef" },
    };

    for (cases) |case| {
        var v = try pep440.parseVersion(allocator, case.input);
        defer pep440.freeVersion(allocator, &v);

        if (case.expected == null) {
            if (v.local != null) {
                std.debug.print("Expected no local for '{s}', got '{?s}'\n", .{ case.input, v.local });
                return error.LocalMismatch;
            }
        } else {
            if (v.local == null) {
                std.debug.print("Expected local for '{s}', got null\n", .{case.input});
                return error.LocalMismatch;
            }
            if (!std.mem.eql(u8, v.local.?, case.expected.?)) {
                std.debug.print("Local mismatch for '{s}': expected '{s}', got '{s}'\n", .{ case.input, case.expected.?, v.local.? });
                return error.LocalMismatch;
            }
        }
    }
}

test "version ordering: dev < pre < release < post" {
    const allocator = std.testing.allocator;

    var v_dev = try pep440.parseVersion(allocator, "1.0.dev1");
    defer pep440.freeVersion(allocator, &v_dev);

    var v_alpha = try pep440.parseVersion(allocator, "1.0a1");
    defer pep440.freeVersion(allocator, &v_alpha);

    var v_beta = try pep440.parseVersion(allocator, "1.0b1");
    defer pep440.freeVersion(allocator, &v_beta);

    var v_rc = try pep440.parseVersion(allocator, "1.0rc1");
    defer pep440.freeVersion(allocator, &v_rc);

    var v_release = try pep440.parseVersion(allocator, "1.0");
    defer pep440.freeVersion(allocator, &v_release);

    var v_post = try pep440.parseVersion(allocator, "1.0.post1");
    defer pep440.freeVersion(allocator, &v_post);

    // dev < alpha
    try std.testing.expectEqual(std.math.Order.lt, v_dev.compare(v_alpha));
    // alpha < beta
    try std.testing.expectEqual(std.math.Order.lt, v_alpha.compare(v_beta));
    // beta < rc
    try std.testing.expectEqual(std.math.Order.lt, v_beta.compare(v_rc));
    // rc < release
    try std.testing.expectEqual(std.math.Order.lt, v_rc.compare(v_release));
    // release < post
    try std.testing.expectEqual(std.math.Order.lt, v_release.compare(v_post));
}

test "rc and c are equivalent" {
    const allocator = std.testing.allocator;

    var v_rc = try pep440.parseVersion(allocator, "1.0rc1");
    defer pep440.freeVersion(allocator, &v_rc);

    var v_c = try pep440.parseVersion(allocator, "1.0c1");
    defer pep440.freeVersion(allocator, &v_c);

    try std.testing.expectEqual(std.math.Order.eq, v_rc.compare(v_c));
}

test "epoch comparison takes precedence" {
    const allocator = std.testing.allocator;

    var v_no_epoch = try pep440.parseVersion(allocator, "2.0");
    defer pep440.freeVersion(allocator, &v_no_epoch);

    var v_with_epoch = try pep440.parseVersion(allocator, "1!1.0");
    defer pep440.freeVersion(allocator, &v_with_epoch);

    // 1!1.0 > 2.0 because epoch 1 > epoch 0
    try std.testing.expectEqual(std.math.Order.gt, v_with_epoch.compare(v_no_epoch));
}

test "1.0 equals 1.0.0" {
    const allocator = std.testing.allocator;

    var v1 = try pep440.parseVersion(allocator, "1.0");
    defer pep440.freeVersion(allocator, &v1);

    var v2 = try pep440.parseVersion(allocator, "1.0.0");
    defer pep440.freeVersion(allocator, &v2);

    try std.testing.expectEqual(std.math.Order.eq, v1.compare(v2));
}
