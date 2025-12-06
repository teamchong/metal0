/// frame - Frame Object Implementation
/// Mirrors cpython/Python/frame.c and pycore_frame.h
///
/// This module provides:
/// - PyFrameObject: The Python frame object visible to Python code
/// - InterpreterFrame: The internal execution frame
/// - Frame state management (created, executing, suspended, completed)
/// - Stack and locals management
/// - Frame traversal and cleanup

const std = @import("std");

// ============================================================================
// Frame State
// ============================================================================

/// Frame execution state
/// Mirrors: PyFrameState enum
pub const FrameState = enum(i8) {
    created = -3, // Frame created but not yet executing
    suspended = -2, // Frame suspended (e.g., generator yield)
    suspended_yield_from = -1, // Suspended in yield from
    executing = 0, // Currently executing
    completed = 1, // Execution completed normally
    cleared = 4, // Frame has been cleared
};

/// Check if frame state is suspended
pub fn isStateSuspended(state: FrameState) bool {
    return state == .suspended or state == .suspended_yield_from;
}

/// Check if frame state is finished
pub fn isStateFinished(state: FrameState) bool {
    return @intFromEnum(state) >= @intFromEnum(FrameState.completed);
}

// ============================================================================
// Frame Owner
// ============================================================================

/// Who owns this frame
pub const FrameOwner = enum(u8) {
    thread = 0, // Owned by thread (normal execution)
    generator = 1, // Owned by generator/coroutine
    frame_object = 2, // Owned by PyFrameObject
    cstack = 3, // Owned by C stack
    interpreter = 255, // Owned by interpreter (sentinel)
};

// ============================================================================
// Interpreter Frame (Internal)
// ============================================================================

/// Internal interpreter frame structure
/// Mirrors: _PyInterpreterFrame in pycore_interpframe_structs.h
pub const InterpreterFrame = struct {
    /// Previous frame in the call stack
    previous: ?*InterpreterFrame = null,

    /// Code object being executed (as opaque pointer for now)
    f_executable: ?*anyopaque = null,

    /// Function object
    f_funcobj: ?*anyopaque = null,

    /// Global namespace dict
    f_globals: ?*anyopaque = null,

    /// Builtin namespace dict
    f_builtins: ?*anyopaque = null,

    /// Local namespace dict (for exec/eval with explicit locals)
    f_locals: ?*anyopaque = null,

    /// Associated PyFrameObject (if any)
    frame_obj: ?*PyFrameObject = null,

    /// Current instruction pointer offset
    instr_ptr: usize = 0,

    /// Return offset in bytecode
    return_offset: u16 = 0,

    /// Stack top pointer (index into localsplus)
    stackpointer: usize = 0,

    /// Frame owner
    owner: FrameOwner = .thread,

    /// Locals and stack values storage
    /// In CPython this is variable-length localsplus array
    localsplus: [256]?*anyopaque = [_]?*anyopaque{null} ** 256,

    /// Number of local variables + cell/free vars
    nlocalsplus: usize = 0,

    /// Initialize a new interpreter frame
    pub fn init(code: ?*anyopaque, globals: ?*anyopaque, builtins: ?*anyopaque) InterpreterFrame {
        return .{
            .f_executable = code,
            .f_globals = globals,
            .f_builtins = builtins,
        };
    }

    /// Get the code object
    pub fn getCode(self: *const InterpreterFrame) ?*anyopaque {
        return self.f_executable;
    }

    /// Get the function object
    pub fn getFunction(self: *const InterpreterFrame) ?*anyopaque {
        return self.f_funcobj;
    }

    /// Get the last instruction index (in code units)
    pub fn getLasti(self: *const InterpreterFrame) i32 {
        return @intCast(self.instr_ptr);
    }

    /// Get stack base (start of stack after locals)
    pub fn stackBase(self: *InterpreterFrame) usize {
        return self.nlocalsplus;
    }

    /// Push a value onto the stack
    pub fn stackPush(self: *InterpreterFrame, value: ?*anyopaque) void {
        self.localsplus[self.stackpointer] = value;
        self.stackpointer += 1;
    }

    /// Pop a value from the stack
    pub fn stackPop(self: *InterpreterFrame) ?*anyopaque {
        if (self.stackpointer == 0) return null;
        self.stackpointer -= 1;
        const value = self.localsplus[self.stackpointer];
        self.localsplus[self.stackpointer] = null;
        return value;
    }

    /// Peek at top of stack without removing
    pub fn stackPeek(self: *const InterpreterFrame) ?*anyopaque {
        if (self.stackpointer == 0) return null;
        return self.localsplus[self.stackpointer - 1];
    }

    /// Get stack depth
    pub fn stackDepth(self: *const InterpreterFrame) usize {
        if (self.stackpointer < self.stackBase()) return 0;
        return self.stackpointer - self.stackBase();
    }

    /// Get a local variable
    pub fn getLocal(self: *const InterpreterFrame, index: usize) ?*anyopaque {
        if (index >= self.nlocalsplus) return null;
        return self.localsplus[index];
    }

    /// Set a local variable
    pub fn setLocal(self: *InterpreterFrame, index: usize, value: ?*anyopaque) void {
        if (index < self.nlocalsplus) {
            self.localsplus[index] = value;
        }
    }

    /// Clear all locals
    pub fn clearLocals(self: *InterpreterFrame) void {
        // Clear stack
        while (self.stackpointer > self.stackBase()) {
            _ = self.stackPop();
        }
        // Clear locals
        for (0..self.nlocalsplus) |i| {
            self.localsplus[i] = null;
        }
        self.f_locals = null;
    }

    /// Clear frame except code object
    pub fn clearExceptCode(self: *InterpreterFrame) void {
        if (self.frame_obj) |f| {
            // Take ownership if frame object exists
            f.takeOwnership(self);
        }
        self.clearLocals();
        self.f_funcobj = null;
    }

    /// Copy frame to another frame
    pub fn copy(self: *const InterpreterFrame, dest: *InterpreterFrame) void {
        dest.f_executable = self.f_executable;
        dest.previous = null; // Don't leave dangling pointer
        dest.f_funcobj = self.f_funcobj;
        dest.f_globals = self.f_globals;
        dest.f_builtins = self.f_builtins;
        dest.f_locals = self.f_locals;
        dest.frame_obj = self.frame_obj;
        dest.instr_ptr = self.instr_ptr;
        dest.return_offset = self.return_offset;
        dest.stackpointer = self.stackpointer;
        dest.nlocalsplus = self.nlocalsplus;

        // Copy localsplus
        for (0..self.stackpointer) |i| {
            dest.localsplus[i] = self.localsplus[i];
        }
    }

    /// Check if frame is incomplete (not yet started)
    pub fn isIncomplete(self: *const InterpreterFrame) bool {
        return self.owner != .frame_object and
            self.owner != .generator;
    }

    /// Traverse frame for GC
    pub fn traverse(self: *InterpreterFrame, visitor: *const fn (?*anyopaque) void) void {
        visitor(self.f_executable);
        visitor(self.f_funcobj);
        visitor(self.f_globals);
        visitor(self.f_builtins);
        visitor(self.f_locals);
        if (self.frame_obj) |f| {
            visitor(@ptrCast(f));
        }
        for (0..self.stackpointer) |i| {
            visitor(self.localsplus[i]);
        }
    }
};

// ============================================================================
// PyFrameObject (Python-visible)
// ============================================================================

/// Python frame object visible to Python code
/// Mirrors: struct _frame in pycore_frame.h
pub const PyFrameObject = struct {
    /// Previous frame (f_back in Python)
    f_back: ?*PyFrameObject = null,

    /// Pointer to the interpreter frame
    f_frame: ?*InterpreterFrame = null,

    /// Trace function
    f_trace: ?*anyopaque = null,

    /// Current line number (only valid if non-zero)
    f_lineno: i32 = 0,

    /// Emit per-line trace events?
    f_trace_lines: bool = true,

    /// Emit per-opcode trace events?
    f_trace_opcodes: bool = false,

    /// Extra locals dict for user modifications
    f_extra_locals: ?*anyopaque = null,

    /// Cached locals dict for PyEval_GetLocals
    f_locals_cache: ?*anyopaque = null,

    /// Tuple of overwritten fast locals
    f_overwritten_fast_locals: ?*anyopaque = null,

    /// Allocator used for this frame
    allocator: std.mem.Allocator,

    /// Create a new frame object
    pub fn create(allocator: std.mem.Allocator, code: ?*anyopaque) !*PyFrameObject {
        const frame = try allocator.create(PyFrameObject);
        frame.* = .{
            .allocator = allocator,
        };

        // Create interpreter frame
        const iframe = try allocator.create(InterpreterFrame);
        iframe.* = InterpreterFrame.init(code, null, null);
        iframe.frame_obj = frame;
        iframe.owner = .frame_object;
        frame.f_frame = iframe;

        return frame;
    }

    /// Create without GC tracking (internal use)
    pub fn createNoTrack(allocator: std.mem.Allocator, code: ?*anyopaque) !*PyFrameObject {
        return create(allocator, code);
    }

    /// Destroy frame object
    pub fn destroy(self: *PyFrameObject) void {
        if (self.f_frame) |iframe| {
            iframe.clearLocals();
            self.allocator.destroy(iframe);
        }
        self.allocator.destroy(self);
    }

    /// Get the code object
    pub fn getCode(self: *const PyFrameObject) ?*anyopaque {
        if (self.f_frame) |f| {
            return f.getCode();
        }
        return null;
    }

    /// Get the previous frame (f_back)
    pub fn getBack(self: *const PyFrameObject) ?*PyFrameObject {
        return self.f_back;
    }

    /// Get the globals dict
    pub fn getGlobals(self: *const PyFrameObject) ?*anyopaque {
        if (self.f_frame) |f| {
            return f.f_globals;
        }
        return null;
    }

    /// Get the builtins dict
    pub fn getBuiltins(self: *const PyFrameObject) ?*anyopaque {
        if (self.f_frame) |f| {
            return f.f_builtins;
        }
        return null;
    }

    /// Get the locals dict
    pub fn getLocals(self: *const PyFrameObject) ?*anyopaque {
        if (self.f_frame) |f| {
            return f.f_locals;
        }
        return null;
    }

    /// Get the last instruction index
    pub fn getLasti(self: *const PyFrameObject) i32 {
        if (self.f_frame) |f| {
            return f.getLasti();
        }
        return -1;
    }

    /// Get the current line number
    pub fn getLineNo(self: *const PyFrameObject) i32 {
        if (self.f_lineno != 0) {
            return self.f_lineno;
        }
        // Would normally compute from code object and instruction pointer
        return 0;
    }

    /// Set the trace function
    pub fn setTrace(self: *PyFrameObject, trace_func: ?*anyopaque) void {
        self.f_trace = trace_func;
    }

    /// Take ownership of an interpreter frame
    pub fn takeOwnership(self: *PyFrameObject, frame: *InterpreterFrame) void {
        if (self.f_frame) |owned| {
            frame.copy(owned);
            owned.owner = .frame_object;
        }
    }

    /// Clear the frame
    pub fn clear(self: *PyFrameObject) void {
        if (self.f_frame) |f| {
            f.clearLocals();
        }
        self.f_trace = null;
        self.f_extra_locals = null;
        self.f_locals_cache = null;
    }
};

// ============================================================================
// Frame Stack Management
// ============================================================================

/// Thread-local current frame
threadlocal var current_frame: ?*InterpreterFrame = null;

/// Get the current interpreter frame
pub fn getCurrentFrame() ?*InterpreterFrame {
    return current_frame;
}

/// Set the current interpreter frame
pub fn setCurrentFrame(frame: ?*InterpreterFrame) void {
    current_frame = frame;
}

/// Push a frame onto the stack
pub fn pushFrame(frame: *InterpreterFrame) void {
    frame.previous = current_frame;
    current_frame = frame;
}

/// Pop the current frame from the stack
pub fn popFrame() ?*InterpreterFrame {
    const frame = current_frame;
    if (frame) |f| {
        current_frame = f.previous;
    }
    return frame;
}

/// Get the first complete frame in the chain
pub fn getFirstComplete(frame: ?*InterpreterFrame) ?*InterpreterFrame {
    var f = frame;
    while (f) |fr| {
        if (!fr.isIncomplete()) {
            return fr;
        }
        f = fr.previous;
    }
    return null;
}

/// Get or create a frame object for an interpreter frame
pub fn getFrameObject(allocator: std.mem.Allocator, frame: *InterpreterFrame) !*PyFrameObject {
    if (frame.frame_obj) |f| {
        return f;
    }
    const f = try makeAndSetFrameObject(allocator, frame);
    return f;
}

/// Create and associate a frame object with an interpreter frame
/// Mirrors: _PyFrame_MakeAndSetFrameObject
pub fn makeAndSetFrameObject(allocator: std.mem.Allocator, frame: *InterpreterFrame) !*PyFrameObject {
    if (frame.frame_obj != null) {
        return frame.frame_obj.?;
    }

    const f = try PyFrameObject.createNoTrack(allocator, frame.getCode());

    // Link the interpreter frame
    f.f_frame = frame;
    frame.frame_obj = f;

    // Link f_back to previous frame's PyFrameObject
    const prev = getFirstComplete(frame.previous);
    if (prev) |p| {
        const back = try getFrameObject(allocator, p);
        f.f_back = back;
    }

    return f;
}

// ============================================================================
// Line Number Computation
// ============================================================================

/// Get line number for a frame (would use code object line table)
/// Mirrors: PyUnstable_InterpreterFrame_GetLine
pub fn getFrameLine(_: *InterpreterFrame) i32 {
    // In real implementation, would use code object's linetable
    // For now, return 0 indicating unknown
    return 0;
}

// ============================================================================
// Executable Kinds
// ============================================================================

/// Types of executables that can be in a frame
pub const ExecutableKind = enum(u8) {
    skip = 0, // Skip this frame (None)
    py_function = 1, // Python function (code object)
    builtin_function = 2, // Built-in function
    method_descriptor = 3, // Method descriptor
};

// ============================================================================
// Frame Utilities
// ============================================================================

/// Calculate number of slots needed for a code object
pub fn numSlotsForCode(code_framesize: usize) usize {
    const specials_size = @sizeOf(InterpreterFrame) / @sizeOf(?*anyopaque);
    if (code_framesize < specials_size) return 0;
    return code_framesize - specials_size;
}

/// Get the locals array from a frame
pub fn getLocalsArray(frame: *InterpreterFrame) []?*anyopaque {
    return frame.localsplus[0..frame.nlocalsplus];
}

/// Get the stack base pointer
pub fn getStackbase(frame: *InterpreterFrame) []?*anyopaque {
    const base = frame.stackBase();
    return frame.localsplus[base..frame.stackpointer];
}

/// Set the stack pointer
pub fn setStackPointer(frame: *InterpreterFrame, sp: usize) void {
    frame.stackpointer = sp;
}

// ============================================================================
// Initialization
// ============================================================================

/// Initialize the frame subsystem
pub fn init() void {
    current_frame = null;
}

/// Finalize the frame subsystem
pub fn fini() void {
    current_frame = null;
}

// ============================================================================
// Tests
// ============================================================================

test "frame state helpers" {
    try std.testing.expect(isStateSuspended(.suspended));
    try std.testing.expect(isStateSuspended(.suspended_yield_from));
    try std.testing.expect(!isStateSuspended(.executing));

    try std.testing.expect(isStateFinished(.completed));
    try std.testing.expect(isStateFinished(.cleared));
    try std.testing.expect(!isStateFinished(.executing));
}

test "interpreter frame basics" {
    var frame = InterpreterFrame.init(null, null, null);
    frame.nlocalsplus = 3;

    // Test locals
    frame.setLocal(0, @ptrFromInt(0x1000));
    try std.testing.expectEqual(@as(?*anyopaque, @ptrFromInt(0x1000)), frame.getLocal(0));

    // Test stack
    frame.stackpointer = frame.stackBase();
    try std.testing.expectEqual(@as(usize, 0), frame.stackDepth());

    frame.stackPush(@ptrFromInt(0x2000));
    try std.testing.expectEqual(@as(usize, 1), frame.stackDepth());
    try std.testing.expectEqual(@as(?*anyopaque, @ptrFromInt(0x2000)), frame.stackPeek());

    const popped = frame.stackPop();
    try std.testing.expectEqual(@as(?*anyopaque, @ptrFromInt(0x2000)), popped);
    try std.testing.expectEqual(@as(usize, 0), frame.stackDepth());
}

test "frame object creation" {
    const allocator = std.testing.allocator;

    const frame = try PyFrameObject.create(allocator, null);
    defer frame.destroy();

    try std.testing.expect(frame.f_frame != null);
    try std.testing.expect(frame.f_frame.?.frame_obj == frame);
    try std.testing.expectEqual(FrameOwner.frame_object, frame.f_frame.?.owner);
}

test "frame stack management" {
    var frame1 = InterpreterFrame.init(null, null, null);
    var frame2 = InterpreterFrame.init(null, null, null);

    try std.testing.expect(getCurrentFrame() == null);

    pushFrame(&frame1);
    try std.testing.expect(getCurrentFrame() == &frame1);

    pushFrame(&frame2);
    try std.testing.expect(getCurrentFrame() == &frame2);
    try std.testing.expect(frame2.previous == &frame1);

    _ = popFrame();
    try std.testing.expect(getCurrentFrame() == &frame1);

    _ = popFrame();
    try std.testing.expect(getCurrentFrame() == null);
}

test "frame copy" {
    var src = InterpreterFrame.init(@ptrFromInt(0x1000), @ptrFromInt(0x2000), @ptrFromInt(0x3000));
    src.nlocalsplus = 2;
    src.stackpointer = 4;
    src.setLocal(0, @ptrFromInt(0x4000));
    src.setLocal(1, @ptrFromInt(0x5000));

    var dest: InterpreterFrame = undefined;
    src.copy(&dest);

    try std.testing.expectEqual(src.f_executable, dest.f_executable);
    try std.testing.expectEqual(src.f_globals, dest.f_globals);
    try std.testing.expectEqual(src.f_builtins, dest.f_builtins);
    try std.testing.expectEqual(src.nlocalsplus, dest.nlocalsplus);
    try std.testing.expectEqual(src.stackpointer, dest.stackpointer);
    try std.testing.expectEqual(src.getLocal(0), dest.getLocal(0));
    try std.testing.expect(dest.previous == null); // Should not copy previous
}
