//! hypothesis.strategies - Strategy functions for property-based testing
//! Stub implementation - hypothesis decorators are skipped at compile time
const std = @import("std");

/// Float strategy - returns function that generates float test cases
/// In real hypothesis, this generates random floats. In metal0, it's a stub
/// since @hypothesis.given decorators are skipped.
pub fn floats(args: anytype) fn () void {
    _ = args;
    return struct {
        pub fn call() void {}
    }.call;
}

/// Integer strategy - returns function that generates integer test cases
pub fn integers(args: anytype) fn () void {
    _ = args;
    return struct {
        pub fn call() void {}
    }.call;
}
