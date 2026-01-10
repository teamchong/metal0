//! importlib.resources._adapters - Adapter utilities for resources
//! Reference: cpython/Lib/importlib/resources/_adapters.py

const std = @import("std");
const resources = @import("../resources.zig");

// Re-export types from parent module (DRY)
pub const Traversable = resources.Traversable;
pub const Package = resources.Package;

/// Wrap a package to provide Traversable interface
pub fn wrap(package: Package) Traversable {
    return Traversable.init(package.getName());
}

test "wrap" {
    const pkg = Package{ .name = "mypackage" };
    const t = wrap(pkg);
    try std.testing.expectEqualStrings("mypackage", t.path);
}
