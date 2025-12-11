/// Internal Interpreter Frame Implementation
/// Mirrors _PyInterpreterFrame in pycore_interpframe_structs.h

const state = @import("state.zig");

// Forward declaration for PyFrameObject
pub const PyFrameObject = @import("frame_object.zig").PyFrameObject;

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
    owner: state.FrameOwner = .thread,

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
