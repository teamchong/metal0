//! test.support.hypothesis_helper - Hypothesis property-based testing stubs
//! Provides minimal stubs for hypothesis library used by some CPython tests
//!
//! Real hypothesis is a complex library for property-based testing.
//! Metal0 tests skip hypothesis decorators at compile time.
const std = @import("std");

/// Stub hypothesis module with strategies submodule
pub const hypothesis = struct {
    pub const strategies = @import("_hypothesis_stubs/strategies.zig");

    /// given decorator stub - no-op in AOT
    pub fn given(args: anytype) void {
        _ = args;
    }
};
