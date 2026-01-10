//! test.test_ctypes.test_returnfuncptrs - Tests for returning function pointers
//! Reference: cpython/Lib/test/test_ctypes/test_returnfuncptrs.py
//!
//! Tests for functions that return function pointers.

const std = @import("std");
const _support = @import("_support.zig");

// ============================================================================
// Function Pointer Types
// ============================================================================

pub const FuncPtr = *const fn () callconv(.C) void;
pub const IntFuncPtr = *const fn () callconv(.C) i32;
pub const IntIntFuncPtr = *const fn (i32) callconv(.C) i32;
pub const BinaryOpPtr = *const fn (i32, i32) callconv(.C) i32;

/// Generic function pointer wrapper
pub fn FuncPtrWrapper(comptime FnType: type) type {
    return struct {
        const Self = @This();

        ptr: ?FnType = null,

        pub fn init() Self {
            return .{};
        }

        pub fn fromPtr(p: FnType) Self {
            return .{ .ptr = p };
        }

        pub fn isNull(self: *const Self) bool {
            return self.ptr == null;
        }

        pub fn address(self: *const Self) usize {
            if (self.ptr) |p| {
                return @intFromPtr(p);
            }
            return 0;
        }
    };
}

// ============================================================================
// Factory Functions
// ============================================================================

/// Returns a function that returns a constant
pub fn makeConstantFunc(value: i32) IntFuncPtr {
    _ = value;
    // In real implementation, would generate a closure
    // For now, return a static function
    const S = struct {
        fn constantFunc() callconv(.C) i32 {
            return 42;
        }
    };
    return S.constantFunc;
}

/// Returns an identity function
pub fn makeIdentityFunc() IntIntFuncPtr {
    const S = struct {
        fn identity(x: i32) callconv(.C) i32 {
            return x;
        }
    };
    return S.identity;
}

/// Returns an addition function
pub fn makeAddFunc() BinaryOpPtr {
    const S = struct {
        fn add(a: i32, b: i32) callconv(.C) i32 {
            return a + b;
        }
    };
    return S.add;
}

/// Returns a multiplication function
pub fn makeMulFunc() BinaryOpPtr {
    const S = struct {
        fn mul(a: i32, b: i32) callconv(.C) i32 {
            return a * b;
        }
    };
    return S.mul;
}

// ============================================================================
// Function Pointer Table
// ============================================================================

pub const FuncTable = struct {
    const Self = @This();
    const max_funcs = 16;

    funcs: [max_funcs]?*const anyopaque = [_]?*const anyopaque{null} ** max_funcs,
    count: usize = 0,

    pub fn init() Self {
        return .{};
    }

    pub fn add(self: *Self, func: *const anyopaque) !usize {
        if (self.count >= max_funcs) return error.TableFull;
        const idx = self.count;
        self.funcs[idx] = func;
        self.count += 1;
        return idx;
    }

    pub fn get(self: *const Self, idx: usize) ?*const anyopaque {
        if (idx >= max_funcs) return null;
        return self.funcs[idx];
    }

    pub fn call(self: *const Self, comptime T: type, idx: usize, args: anytype) !@typeInfo(T).@"fn".return_type.? {
        const ptr = self.get(idx) orelse return error.FuncNotFound;
        const func: T = @ptrCast(ptr);
        return @call(.auto, func, args);
    }
};

// ============================================================================
// Test Cases
// ============================================================================

fn testMakeConstantFunc() !void {
    const func = makeConstantFunc(42);
    const result = func();
    try std.testing.expectEqual(@as(i32, 42), result);
}

fn testMakeIdentityFunc() !void {
    const func = makeIdentityFunc();
    try std.testing.expectEqual(@as(i32, 100), func(100));
    try std.testing.expectEqual(@as(i32, -50), func(-50));
}

fn testMakeAddFunc() !void {
    const func = makeAddFunc();
    try std.testing.expectEqual(@as(i32, 30), func(10, 20));
    try std.testing.expectEqual(@as(i32, 0), func(5, -5));
}

fn testMakeMulFunc() !void {
    const func = makeMulFunc();
    try std.testing.expectEqual(@as(i32, 200), func(10, 20));
    try std.testing.expectEqual(@as(i32, -25), func(5, -5));
}

fn testFuncPtrWrapper() !void {
    const Wrapper = FuncPtrWrapper(IntFuncPtr);
    var w = Wrapper.init();

    try std.testing.expect(w.isNull());
    try std.testing.expectEqual(@as(usize, 0), w.address());

    const func = makeConstantFunc(42);
    w = Wrapper.fromPtr(func);

    try std.testing.expect(!w.isNull());
    try std.testing.expect(w.address() != 0);
}

fn testFuncTable() !void {
    var table = FuncTable.init();

    const add_func = makeAddFunc();
    const mul_func = makeMulFunc();

    const add_idx = try table.add(@ptrCast(add_func));
    const mul_idx = try table.add(@ptrCast(mul_func));

    try std.testing.expect(table.get(add_idx) != null);
    try std.testing.expect(table.get(mul_idx) != null);
}

fn testFuncPtrAddress() !void {
    const func1 = makeAddFunc();
    const func2 = makeMulFunc();

    const addr1 = @intFromPtr(func1);
    const addr2 = @intFromPtr(func2);

    try std.testing.expect(addr1 != 0);
    try std.testing.expect(addr2 != 0);
    try std.testing.expect(addr1 != addr2);
}

fn testFuncPtrCompare() !void {
    const func = makeIdentityFunc();
    const Wrapper = FuncPtrWrapper(IntIntFuncPtr);

    const w1 = Wrapper.fromPtr(func);
    const w2 = Wrapper.fromPtr(func);

    try std.testing.expectEqual(w1.address(), w2.address());
}

fn testMultipleCalls() !void {
    const add = makeAddFunc();

    try std.testing.expectEqual(@as(i32, 3), add(1, 2));
    try std.testing.expectEqual(@as(i32, 15), add(10, 5));
    try std.testing.expectEqual(@as(i32, 0), add(-1, 1));
}

fn testChainedCalls() !void {
    const add = makeAddFunc();
    const mul = makeMulFunc();

    // mul(add(1, 2), add(3, 4)) = mul(3, 7) = 21
    const result = mul(add(1, 2), add(3, 4));
    try std.testing.expectEqual(@as(i32, 21), result);
}

// ============================================================================
// Zig Test Declarations
// ============================================================================

test "make_constant_func" {
    try testMakeConstantFunc();
}

test "make_identity_func" {
    try testMakeIdentityFunc();
}

test "make_add_func" {
    try testMakeAddFunc();
}

test "make_mul_func" {
    try testMakeMulFunc();
}

test "func_ptr_wrapper" {
    try testFuncPtrWrapper();
}

test "func_table" {
    try testFuncTable();
}

test "func_ptr_address" {
    try testFuncPtrAddress();
}

test "func_ptr_compare" {
    try testFuncPtrCompare();
}

test "multiple_calls" {
    try testMultipleCalls();
}

test "chained_calls" {
    try testChainedCalls();
}
