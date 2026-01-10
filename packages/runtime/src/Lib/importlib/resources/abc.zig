//! importlib.resources.abc - Abstract base classes for resources
//! Reference: cpython/Lib/importlib/resources/abc.py
//!
//! CPython exports: ResourceReader, Traversable, TraversableResources

const std = @import("std");
const resources = @import("../resources.zig");

// Re-export from parent module (DRY)
pub const ResourceReader = resources.ResourceReader;
pub const Traversable = resources.Traversable;

/// TraversableResources protocol
/// CPython: class TraversableResources(abc.ABC)
pub const TraversableResources = struct {
    /// Return Traversable for package files
    pub fn files(self: *const TraversableResources) ?*Traversable {
        _ = self;
        return null;
    }
};

test "ResourceReader re-export" {
    const rr = ResourceReader{};
    try std.testing.expect(!rr.isResource("test"));
}
