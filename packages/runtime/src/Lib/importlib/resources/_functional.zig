//! importlib.resources._functional - Functional API for resources
//! Reference: cpython/Lib/importlib/resources/_functional.py
//!
//! CPython exports: contents, is_resource, open_binary, open_text, path, read_binary, read_text

const std = @import("std");
const resources = @import("../resources.zig");

// Re-export from parent module (DRY)
pub const contents = resources.contents;
pub const isResource = resources.isResource;
pub const openBinary = resources.openBinary;
pub const openText = resources.openText;
pub const path = resources.path;
pub const readBinary = resources.readBinary;
pub const readText = resources.readText;

test "isResource re-export" {
    const pkg = resources.Package{ .name = "/nonexistent" };
    try std.testing.expect(!isResource(pkg, "file.txt"));
}
