//! pytest stub for metal0 AOT compilation
//!
//! Provides minimal pytest compatibility for running tests without the real pytest.
//! Decorators are no-ops, assertions use metal0's runtime assertions.

const std = @import("std");

// ============================================================================
// pytest.mark decorators
// ============================================================================

/// pytest.mark namespace for test decorators
pub const mark = struct {
    /// @pytest.mark.parametrize - no-op decorator (tests are unrolled at codegen)
    pub fn parametrize(comptime _: []const u8, comptime _: anytype) type {
        return struct {
            pub fn decorator(comptime func: anytype) @TypeOf(func) {
                return func;
            }
        };
    }

    /// @pytest.mark.skipif - conditionally skip test
    pub fn skipif(comptime condition: bool, comptime _: struct { reason: []const u8 = "" }) type {
        return struct {
            pub fn decorator(comptime func: anytype) @TypeOf(func) {
                if (condition) {
                    // Return a no-op function that does nothing
                    return struct {
                        pub fn call(_: anytype) void {}
                    }.call;
                }
                return func;
            }
        };
    }

    /// @pytest.mark.skip - always skip test
    pub fn skip(comptime _: struct { reason: []const u8 = "" }) type {
        return struct {
            pub fn decorator(comptime _: anytype) fn () void {
                return struct {
                    pub fn call() void {}
                }.call;
            }
        };
    }

    /// @pytest.mark.filterwarnings - no-op, warnings not filtered in AOT
    pub fn filterwarnings(comptime _: []const u8) type {
        return struct {
            pub fn decorator(comptime func: anytype) @TypeOf(func) {
                return func;
            }
        };
    }

    /// @pytest.mark.xfail - expected failure marker
    pub fn xfail(comptime _: struct { reason: []const u8 = "", strict: bool = false }) type {
        return struct {
            pub fn decorator(comptime func: anytype) @TypeOf(func) {
                return func;
            }
        };
    }

    /// @pytest.mark.slow - slow test marker (no-op)
    pub const slow = struct {
        pub fn decorator(comptime func: anytype) @TypeOf(func) {
            return func;
        }
    };

    /// @pytest.mark.thread_unsafe - thread safety marker (no-op)
    pub fn thread_unsafe(comptime _: struct { reason: []const u8 = "" }) type {
        return struct {
            pub fn decorator(comptime func: anytype) @TypeOf(func) {
                return func;
            }
        };
    }
};

// ============================================================================
// pytest.raises context manager
// ============================================================================

/// Context manager for testing exceptions
pub fn raises(comptime ExceptionType: type, comptime opts: anytype) type {
    _ = opts;
    return struct {
        caught: bool = false,
        exception: ?ExceptionType = null,

        const Self = @This();

        pub fn __enter__(self: *Self) *Self {
            return self;
        }

        pub fn __exit__(self: *Self, exc_type: ?type, exc_val: anytype, _: anytype) bool {
            _ = exc_val;
            if (exc_type) |et| {
                if (et == ExceptionType) {
                    self.caught = true;
                    return true; // Suppress the exception
                }
            }
            return false;
        }

        /// Check if exception was raised (for use in assertions)
        pub fn match(self: *Self, pattern: []const u8) bool {
            _ = pattern;
            return self.caught;
        }
    };
}

// ============================================================================
// pytest.warns context manager
// ============================================================================

/// Context manager for testing warnings
pub fn warns(comptime WarningType: type, comptime opts: anytype) type {
    _ = opts;
    _ = WarningType;
    return struct {
        const Self = @This();

        pub fn __enter__(self: *Self) *Self {
            return self;
        }

        pub fn __exit__(_: *Self, _: ?type, _: anytype, _: anytype) bool {
            return false;
        }
    };
}

// ============================================================================
// pytest.fixture decorator
// ============================================================================

/// @pytest.fixture - marks a function as a fixture
pub fn fixture(comptime opts: anytype) type {
    _ = opts;
    return struct {
        pub fn decorator(comptime func: anytype) @TypeOf(func) {
            return func;
        }
    };
}

// ============================================================================
// pytest.param for parametrize
// ============================================================================

/// pytest.param - wraps parameter values with optional marks
pub fn param(comptime values: anytype, comptime opts: anytype) @TypeOf(values) {
    _ = opts;
    return values;
}

// ============================================================================
// pytest.approx for floating point comparisons
// ============================================================================

/// pytest.approx - approximate floating point comparison
pub fn approx(expected: anytype, opts: struct { rel: f64 = 1e-6, abs: f64 = 1e-12 }) @TypeOf(expected) {
    _ = opts;
    return expected;
}

// ============================================================================
// pytest module-level markers (pytestmark)
// ============================================================================

/// Module-level marker (assigned to pytestmark)
pub const pytestmark = struct {
    marks: []const type = &[_]type{},
};

// ============================================================================
// pytest.fail - explicit test failure
// ============================================================================

pub fn fail(msg: []const u8) noreturn {
    std.debug.print("pytest.fail: {s}\n", .{msg});
    @panic("pytest.fail");
}

// ============================================================================
// pytest.skip - skip current test
// ============================================================================

pub fn @"skip"(msg: []const u8) void {
    std.debug.print("pytest.skip: {s}\n", .{msg});
}

// ============================================================================
// pytest.importorskip - import or skip test
// ============================================================================

pub fn importorskip(comptime module_name: []const u8) type {
    _ = module_name;
    // In AOT mode, imports are resolved at compile time
    // Return a placeholder type
    return struct {};
}
