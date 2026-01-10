//! json.__main__ - Command-line interface for json module
//! Reference: cpython/Lib/json/__main__.py
//!
//! CPython __all__: (none - just runs main())
//!
//! Entry point for `python -m json` which delegates to json.tool.

const std = @import("std");
const tool = @import("tool.zig");

/// Entry point for python -m json
pub fn main() !void {
    return tool.main();
}

// ============================================================================
// Tests
// ============================================================================

test "json.__main__ imports" {
    _ = main;
    _ = tool;
}
