//! test.test_ctypes.test_funcptr - Tests for function pointers
//! Reference: cpython/Lib/test/test_ctypes/test_funcptr.py
//!
//! Tests for function pointer types in ctypes including CFUNCTYPE,
//! callbacks, and function pointer manipulation.

const std = @import("std");
const _support = @import("_support.zig");

// ============================================================================
// Function Pointer Types
// ============================================================================

/// Create a C function pointer type
pub fn CFUNCTYPE(comptime RetType: type, comptime Args: anytype) type {
    const ArgsInfo = @typeInfo(@TypeOf(Args));

    return struct {
        const Self = @This();
        pub const ReturnType = RetType;
        pub const arg_count = if (ArgsInfo == .@"struct") ArgsInfo.@"struct".fields.len else 0;

        ptr: ?*const anyopaque = null,

        pub fn init() Self {
            return .{};
        }

        pub fn fromAddress(addr: usize) Self {
            return .{ .ptr = @ptrFromInt(addr) };
        }

        pub fn address(self: Self) usize {
            if (self.ptr) |p| {
                return @intFromPtr(p);
            }
            return 0;
        }

        pub fn isNull(self: Self) bool {
            return self.ptr == null;
        }

        /// Check if function pointer is valid (non-null)
        pub fn isValid(self: Self) bool {
            return self.ptr != null;
        }

        /// Compare two function pointers
        pub fn eql(self: Self, other: Self) bool {
            return self.ptr == other.ptr;
        }
    };
}

/// Windows calling convention (stdcall)
pub fn WINFUNCTYPE(comptime RetType: type, comptime Args: anytype) type {
    return CFUNCTYPE(RetType, Args);
}

// ============================================================================
// Function Pointer Wrapper
// ============================================================================

/// Wrapper that holds function pointer with metadata
pub fn FuncPtrWrapper(comptime signature: FuncSignature) type {
    return struct {
        const Self = @This();
        pub const Signature = signature;

        ptr: ?*const anyopaque = null,
        restype: TypeInfo = signature.return_type,
        argtypes: [signature.arg_count]TypeInfo = signature.arg_types,
        errcheck: ?*const fn (i64) bool = null,

        pub fn init() Self {
            return .{};
        }

        pub fn setPtr(self: *Self, addr: usize) void {
            self.ptr = @ptrFromInt(addr);
        }

        pub fn setErrcheck(self: *Self, func: *const fn (i64) bool) void {
            self.errcheck = func;
        }

        pub fn getArgtypes(self: *const Self) []const TypeInfo {
            return &self.argtypes;
        }
    };
}

pub const FuncSignature = struct {
    return_type: TypeInfo,
    arg_types: [8]TypeInfo = [_]TypeInfo{.{ .name = "", .size = 0 }} ** 8,
    arg_count: usize = 0,
};

pub const TypeInfo = struct {
    name: []const u8,
    size: usize,
};

// ============================================================================
// Common Function Types
// ============================================================================

// int (*)(void)
pub const IntFunc = CFUNCTYPE(c_int, .{});

// int (*)(int)
pub const IntIntFunc = CFUNCTYPE(c_int, .{c_int});

// int (*)(int, int)
pub const IntIntIntFunc = CFUNCTYPE(c_int, .{ c_int, c_int });

// void* (*)(size_t)
pub const MallocFunc = CFUNCTYPE(?*anyopaque, .{usize});

// void (*)(void*)
pub const FreeFunc = CFUNCTYPE(void, .{?*anyopaque});

// double (*)(double)
pub const DoubleFunc = CFUNCTYPE(f64, .{f64});

// Type aliases
const c_int = i32;

// ============================================================================
// Callback Support
// ============================================================================

/// Convert a Zig function to a callback
pub fn makeCallback(comptime func: anytype) *const anyopaque {
    return @ptrCast(&func);
}

/// Callback holder with error handling
pub const CallbackHolder = struct {
    const Self = @This();

    ptr: *const anyopaque,
    user_data: ?*anyopaque = null,

    pub fn init(ptr: *const anyopaque) Self {
        return .{ .ptr = ptr };
    }

    pub fn withUserData(ptr: *const anyopaque, data: *anyopaque) Self {
        return .{ .ptr = ptr, .user_data = data };
    }

    pub fn address(self: Self) usize {
        return @intFromPtr(self.ptr);
    }
};

// ============================================================================
// Test Functions
// ============================================================================

fn testAdd(a: i32, b: i32) i32 {
    return a + b;
}

fn testSquare(x: i32) i32 {
    return x * x;
}

fn testNegate(x: i32) i32 {
    return -x;
}

fn testDouble(x: f64) f64 {
    return x * 2.0;
}

// ============================================================================
// Test Cases
// ============================================================================

fn testCFUNCTYPEBasic() !void {
    const FuncType = CFUNCTYPE(i32, .{ i32, i32 });
    const fp = FuncType.init();

    try std.testing.expect(fp.isNull());
    try std.testing.expectEqual(@as(usize, 0), fp.address());
    try std.testing.expectEqual(@as(usize, 2), FuncType.arg_count);
}

fn testCFUNCTYPEFromAddress() !void {
    const FuncType = CFUNCTYPE(i32, .{i32});
    const fp = FuncType.fromAddress(0x12345678);

    try std.testing.expect(!fp.isNull());
    try std.testing.expectEqual(@as(usize, 0x12345678), fp.address());
}

fn testCFUNCTYPECompare() !void {
    const FuncType = CFUNCTYPE(i32, .{});
    const fp1 = FuncType.fromAddress(0x1000);
    const fp2 = FuncType.fromAddress(0x1000);
    const fp3 = FuncType.fromAddress(0x2000);

    try std.testing.expect(fp1.eql(fp2));
    try std.testing.expect(!fp1.eql(fp3));
}

fn testIntFunc() !void {
    const fp = IntFunc.init();
    try std.testing.expect(fp.isNull());
    try std.testing.expectEqual(i32, IntFunc.ReturnType);
}

fn testDoubleFunc() !void {
    const fp = DoubleFunc.init();
    try std.testing.expectEqual(f64, DoubleFunc.ReturnType);
    try std.testing.expectEqual(@as(usize, 1), DoubleFunc.arg_count);
}

fn testMakeCallback() !void {
    const cb = makeCallback(testAdd);
    try std.testing.expect(@intFromPtr(cb) != 0);
}

fn testCallbackHolder() !void {
    const cb = makeCallback(testSquare);
    const holder = CallbackHolder.init(cb);

    try std.testing.expect(holder.address() != 0);
    try std.testing.expect(holder.user_data == null);
}

fn testCallbackHolderWithData() !void {
    const cb = makeCallback(testNegate);
    var data: i32 = 42;
    const holder = CallbackHolder.withUserData(cb, @ptrCast(&data));

    try std.testing.expect(holder.user_data != null);
}

fn testFuncPtrWrapper() !void {
    const sig = FuncSignature{
        .return_type = .{ .name = "int", .size = 4 },
        .arg_types = .{
            .{ .name = "int", .size = 4 },
            .{ .name = "int", .size = 4 },
            .{ .name = "", .size = 0 },
            .{ .name = "", .size = 0 },
            .{ .name = "", .size = 0 },
            .{ .name = "", .size = 0 },
            .{ .name = "", .size = 0 },
            .{ .name = "", .size = 0 },
        },
        .arg_count = 2,
    };

    const WrapperType = FuncPtrWrapper(sig);
    var wrapper = WrapperType.init();

    wrapper.setPtr(0x1000);
    try std.testing.expect(wrapper.ptr != null);

    const argtypes = wrapper.getArgtypes();
    try std.testing.expectEqual(@as(usize, 2), argtypes.len);
}

fn testNullFuncPtr() !void {
    const FuncType = CFUNCTYPE(void, .{});
    const fp = FuncType.init();

    try std.testing.expect(fp.isNull());
    try std.testing.expect(!fp.isValid());
}

fn testValidFuncPtr() !void {
    const FuncType = CFUNCTYPE(i32, .{});
    const fp = FuncType.fromAddress(0x1000);

    try std.testing.expect(!fp.isNull());
    try std.testing.expect(fp.isValid());
}

fn testWINFUNCTYPE() !void {
    const FuncType = WINFUNCTYPE(i32, .{ i32, i32 });
    const fp = FuncType.init();

    try std.testing.expectEqual(@as(usize, 2), FuncType.arg_count);
    try std.testing.expect(fp.isNull());
}

// ============================================================================
// Zig Test Declarations
// ============================================================================

test "cfunctype_basic" {
    try testCFUNCTYPEBasic();
}

test "cfunctype_from_address" {
    try testCFUNCTYPEFromAddress();
}

test "cfunctype_compare" {
    try testCFUNCTYPECompare();
}

test "int_func" {
    try testIntFunc();
}

test "double_func" {
    try testDoubleFunc();
}

test "make_callback" {
    try testMakeCallback();
}

test "callback_holder" {
    try testCallbackHolder();
}

test "callback_holder_with_data" {
    try testCallbackHolderWithData();
}

test "func_ptr_wrapper" {
    try testFuncPtrWrapper();
}

test "null_func_ptr" {
    try testNullFuncPtr();
}

test "valid_func_ptr" {
    try testValidFuncPtr();
}

test "winfunctype" {
    try testWINFUNCTYPE();
}
