//! importlib.metadata._text - Text utilities
//! Reference: cpython/Lib/importlib/metadata/_text.py

const std = @import("std");

/// Normalize package name according to PEP 503
/// CPython: def normalize(name)
pub fn normalize(allocator: std.mem.Allocator, name: []const u8) ![]u8 {
    var result = try allocator.alloc(u8, name.len);
    var write_idx: usize = 0;
    var prev_was_sep = false;

    for (name) |c| {
        const is_sep = c == '-' or c == '_' or c == '.';
        if (is_sep) {
            if (!prev_was_sep) {
                result[write_idx] = '_';
                write_idx += 1;
            }
            prev_was_sep = true;
        } else {
            result[write_idx] = std.ascii.toLower(c);
            write_idx += 1;
            prev_was_sep = false;
        }
    }

    return result[0..write_idx];
}

/// Legacy normalization (just lowercase and replace hyphens)
/// CPython: def legacy_normalize(name)
pub fn legacyNormalize(allocator: std.mem.Allocator, name: []const u8) ![]u8 {
    var result = try allocator.alloc(u8, name.len);
    for (name, 0..) |c, i| {
        result[i] = if (c == '-') '_' else std.ascii.toLower(c);
    }
    return result;
}

test "normalize" {
    const allocator = std.testing.allocator;

    const r1 = try normalize(allocator, "Sample-Pkg");
    defer allocator.free(r1);
    try std.testing.expectEqualStrings("sample_pkg", r1);

    const r2 = try normalize(allocator, "Sample__Pkg-name.foo");
    defer allocator.free(r2);
    try std.testing.expectEqualStrings("sample_pkg_name_foo", r2);
}

test "legacyNormalize" {
    const allocator = std.testing.allocator;

    const r1 = try legacyNormalize(allocator, "Sample-Pkg");
    defer allocator.free(r1);
    try std.testing.expectEqualStrings("sample_pkg", r1);
}
