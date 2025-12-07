/// emscripten_trampoline - Emscripten Trampoline
/// Mirrors cpython/Python/emscripten_trampoline.c
///
/// Function call trampolines for Emscripten/WebAssembly.
/// Handles indirect function calls across WASM module boundaries.

const std = @import("std");
const builtin = @import("builtin");

// ============================================================================
// Platform Detection
// ============================================================================

/// Check if running on Emscripten/WASM
pub const is_emscripten = builtin.os.tag == .emscripten or builtin.cpu.arch == .wasm32;

// ============================================================================
// Trampoline Types
// ============================================================================

/// Generic function pointer type
pub const FuncPtr = *const fn () callconv(.C) void;

/// Function signature types for trampolines
pub const CallSignature = enum {
    /// void func(void)
    void_void,
    /// void* func(void*)
    ptr_ptr,
    /// void* func(void*, void*)
    ptr_ptr_ptr,
    /// void* func(void*, void*, void*)
    ptr_ptr_ptr_ptr,
    /// int func(void*)
    int_ptr,
    /// int func(void*, void*)
    int_ptr_ptr,
    /// int func(int)
    int_int,
    /// int func(int, int)
    int_int_int,
};

/// Trampoline entry
pub const TrampolineEntry = struct {
    /// Function pointer
    func: FuncPtr,
    /// Call signature
    signature: CallSignature,
    /// User data
    data: ?*anyopaque = null,
};

// ============================================================================
// Trampoline Table
// ============================================================================

/// Table of registered trampolines
pub const TrampolineTable = struct {
    const Self = @This();
    const MAX_ENTRIES = 1024;

    /// Trampoline entries
    entries: [MAX_ENTRIES]?TrampolineEntry = [_]?TrampolineEntry{null} ** MAX_ENTRIES,
    /// Number of registered entries
    count: usize = 0,
    /// Next free index
    next_free: usize = 0,

    /// Register a trampoline
    pub fn register(self: *Self, func: FuncPtr, sig: CallSignature, data: ?*anyopaque) ?usize {
        if (self.next_free >= MAX_ENTRIES) {
            // Find a free slot
            for (self.entries, 0..) |entry, i| {
                if (entry == null) {
                    self.entries[i] = TrampolineEntry{
                        .func = func,
                        .signature = sig,
                        .data = data,
                    };
                    self.count += 1;
                    return i;
                }
            }
            return null;
        }

        const idx = self.next_free;
        self.entries[idx] = TrampolineEntry{
            .func = func,
            .signature = sig,
            .data = data,
        };
        self.next_free += 1;
        self.count += 1;
        return idx;
    }

    /// Unregister a trampoline
    pub fn unregister(self: *Self, idx: usize) bool {
        if (idx >= MAX_ENTRIES) return false;
        if (self.entries[idx] == null) return false;

        self.entries[idx] = null;
        self.count -= 1;
        return true;
    }

    /// Get a trampoline entry
    pub fn get(self: *const Self, idx: usize) ?TrampolineEntry {
        if (idx >= MAX_ENTRIES) return null;
        return self.entries[idx];
    }

    /// Call a trampoline by index
    pub fn call(self: *const Self, idx: usize, args: anytype) ?*anyopaque {
        const entry = self.get(idx) orelse return null;
        return callTrampoline(entry, args);
    }
};

/// Call a trampoline with given arguments
fn callTrampoline(entry: TrampolineEntry, args: anytype) ?*anyopaque {
    _ = args;
    switch (entry.signature) {
        .void_void => {
            entry.func();
            return null;
        },
        .ptr_ptr => {
            const f: *const fn (*anyopaque) callconv(.C) ?*anyopaque = @ptrCast(entry.func);
            return f(entry.data orelse return null);
        },
        else => return null,
    }
}

// ============================================================================
// Python Call Trampolines
// ============================================================================

/// Python object pointer
pub const PyObject = *anyopaque;

/// PyCFunction signature (METH_VARARGS)
pub const PyCFunction = *const fn (PyObject, PyObject) callconv(.C) PyObject;

/// PyCFunctionWithKeywords signature (METH_VARARGS | METH_KEYWORDS)
pub const PyCFunctionWithKeywords = *const fn (PyObject, PyObject, PyObject) callconv(.C) PyObject;

/// Trampoline for calling Python C functions
pub fn callPyCFunction(func: PyCFunction, self: PyObject, args: PyObject) PyObject {
    return func(self, args);
}

/// Trampoline for calling Python C functions with keywords
pub fn callPyCFunctionWithKeywords(
    func: PyCFunctionWithKeywords,
    self: PyObject,
    args: PyObject,
    kwargs: PyObject,
) PyObject {
    return func(self, args, kwargs);
}

// ============================================================================
// Vectorcall Trampolines
// ============================================================================

/// Vectorcall function signature
pub const VectorcallFunc = *const fn (
    PyObject, // callable
    [*]const PyObject, // args
    usize, // nargsf
    ?PyObject, // kwnames
) callconv(.C) PyObject;

/// Trampoline for vectorcall
pub fn callVectorcall(
    func: VectorcallFunc,
    callable: PyObject,
    args: [*]const PyObject,
    nargsf: usize,
    kwnames: ?PyObject,
) PyObject {
    return func(callable, args, nargsf, kwnames);
}

/// Extract positional arg count from nargsf
pub fn vectorcallNargs(nargsf: usize) usize {
    return nargsf & ~@as(usize, 1 << 63);
}

/// Check if vectorcall has method flag
pub fn vectorcallIsMethod(nargsf: usize) bool {
    return (nargsf & (@as(usize, 1) << 63)) != 0;
}

// ============================================================================
// Async Trampoline Support
// ============================================================================

/// Async callback signature
pub const AsyncCallback = *const fn (?*anyopaque) callconv(.C) void;

/// Schedule an async callback (for Emscripten main loop)
pub fn scheduleAsync(callback: AsyncCallback, data: ?*anyopaque, delay_ms: u32) void {
    _ = callback;
    _ = data;
    _ = delay_ms;
    // Would call emscripten_async_call in real implementation
}

/// Yield to main loop
pub fn yieldToMainLoop() void {
    // Would call emscripten_sleep(0) in real implementation
}

// ============================================================================
// Module State
// ============================================================================

var initialized: bool = false;
var trampoline_table: TrampolineTable = .{};

/// Initialize the emscripten_trampoline module
pub fn init() void {
    if (initialized) return;
    initialized = true;
}

/// Get trampoline table
pub fn getTable() *TrampolineTable {
    return &trampoline_table;
}

/// Reset module state
pub fn reset() void {
    trampoline_table = .{};
    initialized = false;
}

// ============================================================================
// Tests
// ============================================================================

test "trampoline table register" {
    var table = TrampolineTable{};

    const dummy_func: FuncPtr = @ptrFromInt(0x1000);
    const idx = table.register(dummy_func, .void_void, null);

    try std.testing.expect(idx != null);
    try std.testing.expectEqual(@as(usize, 0), idx.?);
    try std.testing.expectEqual(@as(usize, 1), table.count);
}

test "trampoline table get" {
    var table = TrampolineTable{};

    const dummy_func: FuncPtr = @ptrFromInt(0x1000);
    const idx = table.register(dummy_func, .ptr_ptr, null).?;

    const entry = table.get(idx);
    try std.testing.expect(entry != null);
    try std.testing.expectEqual(CallSignature.ptr_ptr, entry.?.signature);
}

test "trampoline table unregister" {
    var table = TrampolineTable{};

    const dummy_func: FuncPtr = @ptrFromInt(0x1000);
    const idx = table.register(dummy_func, .void_void, null).?;

    try std.testing.expect(table.unregister(idx));
    try std.testing.expectEqual(@as(usize, 0), table.count);
    try std.testing.expect(table.get(idx) == null);
}

test "vectorcall helpers" {
    const nargsf: usize = 5;
    try std.testing.expectEqual(@as(usize, 5), vectorcallNargs(nargsf));
    try std.testing.expect(!vectorcallIsMethod(nargsf));

    const method_nargsf: usize = 5 | (@as(usize, 1) << 63);
    try std.testing.expect(vectorcallIsMethod(method_nargsf));
    try std.testing.expectEqual(@as(usize, 5), vectorcallNargs(method_nargsf));
}

test "call signature enum" {
    try std.testing.expectEqual(CallSignature.void_void, CallSignature.void_void);
    try std.testing.expectEqual(CallSignature.ptr_ptr, CallSignature.ptr_ptr);
}
