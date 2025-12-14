//! hypothesis.strategies - Strategy functions for property-based testing
//! Stub implementation - hypothesis decorators are skipped at compile time
const std = @import("std");

/// Stub strategy object
pub const StrategyStub = struct {
    pub fn call() void {}
};

/// Float strategy - returns stub strategy
/// In real hypothesis, this generates random floats. In metal0, it's a stub
/// since @hypothesis.given decorators are skipped.
pub fn floats() StrategyStub {
    return .{};
}

/// Integer strategy - returns stub strategy
pub fn integers(args: anytype) StrategyStub {
    _ = args;
    return .{};
}
