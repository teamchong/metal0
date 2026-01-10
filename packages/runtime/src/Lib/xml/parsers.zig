//! xml.parsers - XML parsers package
//! Reference: cpython/Lib/xml/parsers/__init__.py
//!
//! This package provides XML parser implementations.

const std = @import("std");

// Re-export expat module
pub const expat = @import("parsers/expat.zig");

// ============================================================================
// Tests
// ============================================================================

test "import expat" {
    _ = expat;
}
