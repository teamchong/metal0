/// Generic Traceback Implementation with Comptime Optimization
///
/// Uses comptime to create specialized traceback types with conditional fields.
/// Traceback is a linked list of stack frames.
///
/// Key insight: Most tracebacks don't need locals (just frame + lineno).
/// We use comptime to include locals only when needed for debugging!

const std = @import("std");

/// PyObject forward declaration
const PyObject = extern struct {
    ob_refcnt: isize,
    ob_type: *anyopaque,
};

/// PyVarObject forward declaration
const PyVarObject = extern struct {
    ob_base: PyObject,
    ob_size: isize,
};

/// PyFrameObject - Execution frame
pub const PyFrameObject = extern struct {
    ob_base: PyVarObject,
    f_back: ?*PyFrameObject,        // Previous frame
    f_code: ?*PyCodeObject,          // Code object
    f_builtins: ?*PyDict,            // Built-in namespace
    f_globals: ?*PyDict,             // Global namespace
    f_locals: ?*PyDict,              // Local namespace
    f_trace: ?*PyObject,             // Trace function
    f_gen: ?*PyObject,               // Generator object
    f_lasti: isize,                  // Last instruction
    f_lineno: isize,                 // Current line number
    f_iblock: c_int,                 // Index in block stack
    f_executing: u8,                 // Whether frame is executing
    f_state: u8,                     // State (FRAME_*)
};

/// PyCodeObject - Code object
const PyCodeObject = extern struct {
    ob_base: PyObject,
    co_argcount: c_int,
    co_posonlyargcount: c_int,
    co_kwonlyargcount: c_int,
    co_nlocals: c_int,
    co_stacksize: c_int,
    co_flags: c_int,
    co_code: ?*PyObject,             // Bytecode
    co_consts: ?*PyObject,           // Constants
    co_names: ?*PyObject,            // Names
    co_varnames: ?*PyObject,         // Var names
    co_filename: ?*PyObject,         // Filename
    co_name: ?*PyObject,             // Function name
    co_firstlineno: c_int,           // First line number
    co_lnotab: ?*PyObject,           // Line number table
};

/// PyDict forward declaration
const PyDict = opaque {};

/// Generic Traceback Implementation
///
/// Creates a specialized traceback type based on Config struct.
/// Config controls whether to include locals at comptime.
///
/// Example Config:
/// ```zig
/// const MinimalTracebackConfig = struct {
///     pub const with_locals = false;  // Don't store locals!
/// };
/// ```
pub fn TracebackImpl(comptime Config: type) type {
    return extern struct {
        ob_base: PyObject,
        tb_next: ?*Self,            // Next frame in stack
        tb_frame: ?*PyFrameObject,  // Frame object
        tb_lasti: isize,            // Last instruction
        tb_lineno: isize,           // Line number

        // Comptime: only if Config.with_locals
        tb_locals: if (@hasDecl(Config, "with_locals") and Config.with_locals) ?*PyDict else void,

        const Self = @This();

        /// Initialize traceback
        pub fn init(alloc: std.mem.Allocator, frame: ?*PyFrameObject, lasti: isize, lineno: isize) !*Self {
            const tb = try alloc.create(Self);
            tb.ob_base = .{
                .ob_refcnt = 1,
                .ob_type = undefined, // Set by caller
            };
            tb.tb_next = null;
            tb.tb_frame = frame;
            tb.tb_lasti = lasti;
            tb.tb_lineno = lineno;

            // Initialize locals if configured
            if (@hasDecl(Config, "with_locals") and Config.with_locals) {
                tb.tb_locals = if (frame) |f| f.f_locals else null;
            }

            return tb;
        }

        /// Chain traceback to next frame
        pub fn chain(self: *Self, next: ?*Self) void {
            if (next) |n| {
                n.ob_base.ob_refcnt += 1; // INCREF
            }
            self.tb_next = next;
        }

        /// Get depth of traceback chain
        pub fn depth(self: *const Self) usize {
            var count: usize = 1;
            var current = self.tb_next;
            while (current) |tb| : (current = tb.tb_next) {
                count += 1;
            }
            return count;
        }

        /// Free traceback and chain
        pub fn deinit(self: *Self, alloc: std.mem.Allocator) void {
            // Release next traceback in chain
            if (self.tb_next) |next| {
                next.ob_base.ob_refcnt -= 1; // DECREF
                if (next.ob_base.ob_refcnt == 0) {
                    next.deinit(alloc);
                }
            }

            // Release frame
            if (self.tb_frame) |frame| {
                frame.ob_base.ob_base.ob_refcnt -= 1; // DECREF
            }

            alloc.destroy(self);
        }
    };
}

// ============================================================================
//                         TRACEBACK CONFIGS
// ============================================================================

/// Minimal traceback (no locals - most common)
pub const MinimalTracebackConfig = struct {
    pub const with_locals = false;
};

/// Full traceback (with locals - for debugging)
pub const FullTracebackConfig = struct {
    pub const with_locals = true;
};

/// Default traceback type (minimal)
pub const PyTraceback = TracebackImpl(MinimalTracebackConfig);

/// Debug traceback type (with locals)
pub const PyTracebackDebug = TracebackImpl(FullTracebackConfig);

// ============================================================================
//                          C API EXPORTS
// ============================================================================

/// Create traceback at current frame
export fn PyTraceback_Here(frame: ?*PyFrameObject) callconv(.c) ?*PyObject {
    if (frame == null) return null;

    const f = frame.?;
    const tb = PyTraceback.init(
        std.heap.c_allocator,
        f,
        f.f_lasti,
        f.f_lineno,
    ) catch return null;

    return @ptrCast(&tb.ob_base);
}

/// Print traceback to file
export fn PyTraceback_Print(tb_obj: ?*PyObject, file: ?*PyObject) callconv(.c) c_int {
    _ = file;

    if (tb_obj == null) return 0;

    const tb = @as(*PyTraceback, @ptrCast(tb_obj.?));

    // Walk traceback chain and print each frame
    var current: ?*PyTraceback = tb;
    while (current) |_| {
        current = if (current) |c| c.tb_next else null;
        // TODO: Actually print to file
        // For now, just count frames
    }

    return 0;
}

/// Get traceback depth
export fn PyTraceback_Depth(tb_obj: ?*PyObject) callconv(.c) c_int {
    if (tb_obj == null) return 0;

    const tb = @as(*PyTraceback, @ptrCast(tb_obj.?));
    return @intCast(tb.depth());
}

// ============================================================================
//                              TESTS
// ============================================================================

test "TracebackImpl - minimal" {
    const MinimalTb = TracebackImpl(MinimalTracebackConfig);

    var tb = try MinimalTb.init(std.testing.allocator, null, 0, 42);
    defer tb.deinit(std.testing.allocator);

    try std.testing.expectEqual(@as(isize, 42), tb.tb_lineno);
    try std.testing.expectEqual(@as(isize, 0), tb.tb_lasti);
    try std.testing.expect(tb.tb_next == null);

    // Verify no locals field (would fail to compile if accessed)
    // tb.tb_locals; // Compile error!
}

test "TracebackImpl - with locals" {
    const FullTb = TracebackImpl(FullTracebackConfig);

    var tb = try FullTb.init(std.testing.allocator, null, 0, 42);
    defer tb.deinit(std.testing.allocator);

    try std.testing.expectEqual(@as(isize, 42), tb.tb_lineno);

    // FullTb has locals field!
    try std.testing.expect(tb.tb_locals == null);
}

test "TracebackImpl - chaining" {
    var tb1 = try PyTraceback.init(std.testing.allocator, null, 0, 10);
    defer tb1.deinit(std.testing.allocator);

    const tb2 = try PyTraceback.init(std.testing.allocator, null, 5, 20);

    tb1.chain(tb2);

    try std.testing.expectEqual(@as(usize, 2), tb1.depth());
    try std.testing.expectEqual(tb2, tb1.tb_next.?);

    // Decrement refcount so tb1.deinit doesn't try to free it twice
    tb2.ob_base.ob_refcnt = 1;
}

test "TracebackImpl - size optimization" {
    const MinimalTb = TracebackImpl(MinimalTracebackConfig);
    const FullTb = TracebackImpl(FullTracebackConfig);

    // FullTb should be larger (has locals pointer)
    try std.testing.expect(@sizeOf(FullTb) > @sizeOf(MinimalTb));

    // Verify size difference matches expected field
    const locals_size = @sizeOf(?*PyDict);
    try std.testing.expectEqual(@sizeOf(FullTb), @sizeOf(MinimalTb) + locals_size);
}
