/// Python Frame Object (Python-visible)
/// Mirrors struct _frame in pycore_frame.h

const std = @import("std");
const InterpreterFrame = @import("interpreter_frame.zig").InterpreterFrame;
const state = @import("state.zig");

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
