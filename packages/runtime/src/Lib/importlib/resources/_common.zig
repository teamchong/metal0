//! importlib.resources._common - Common utilities for resources
//! Reference: cpython/Lib/importlib/resources/_common.py
//!
//! CPython exports: files, as_file, Package, Anchor

const std = @import("std");
const resources = @import("../resources.zig");

// Re-export from parent module (DRY)
pub const files = resources.files;
pub const asFile = resources.asFile;
pub const Package = resources.Package;
pub const Anchor = resources.Anchor;
pub const Traversable = resources.Traversable;

/// Get package from anchor
pub fn getPackage(anchor: ?resources.Anchor) ?resources.Package {
    return if (anchor) |a| a else null;
}

test "files re-export" {
    const t = try resources.files(null);
    try std.testing.expectEqualStrings(".", t.path);
}
