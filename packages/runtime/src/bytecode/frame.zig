/// Bytecode Frame - Call stack frame for the bytecode VM
///
/// Frame represents a single call stack entry in the bytecode VM.
/// CodeObject is imported from the unified PyValue module.
const std = @import("std");
const Allocator = std.mem.Allocator;
const opcodes = @import("opcodes.zig");
const Opcode = opcodes.Opcode;

// Import unified PyValue from Objects/object.zig - THE SINGLE SOURCE OF TRUTH
// Both VM and AOT code use this same type definition
pub const PyValue = @import("../Objects/object.zig").PyValue;

// Re-export commonly used types from PyValue for convenience
pub const CodeObject = PyValue.CodeObject;
pub const CodeFlags = PyValue.CodeFlags;
pub const ExcEntry = PyValue.ExcEntry;
pub const Function = PyValue.Function;
pub const Cell = PyValue.Cell;
pub const Dict = PyValue.Dict;
pub const Range = PyValue.Range;
pub const Iterator = PyValue.Iterator;
pub const Exception = PyValue.Exception;
pub const Generator = PyValue.Generator;
pub const BuiltinFn = PyValue.BuiltinFn;

/// Exception handler entry (VM-specific, not shared with AOT)
pub const ExcHandler = struct {
    target: usize, // Handler instruction offset
    stack_depth: usize, // Stack depth when handler was pushed
    exc_type: ?PyValue = null, // Exception type to match (null = catch all)
};

/// Execution frame (call stack entry)
///
/// Each function call creates a new Frame. Frames form a linked list
/// via the `prev` pointer.
pub const Frame = struct {
    /// Instruction pointer (offset into bytecode)
    ip: usize = 0,

    /// Code object being executed
    code: *const CodeObject,

    /// Base pointer into value stack (frame's stack base)
    bp: usize = 0,

    /// Local variables (indexed by LOAD_FAST/STORE_FAST)
    locals: [256]?PyValue = [_]?PyValue{null} ** 256,

    /// Closure cells (for free variables)
    cells: []?*PyValue.Cell = &.{},

    /// Global namespace
    globals: *PyValue.Dict,

    /// Local namespace for exec() (optional)
    locals_dict: ?*PyValue.Dict = null,

    /// Previous frame in call stack
    prev: ?*Frame = null,

    /// Exception handler stack (Zig 0.15 unmanaged ArrayList)
    exc_handlers: std.ArrayList(ExcHandler) = .{},

    /// Source filename (for error messages)
    filename: []const u8,

    /// Current line number (updated during execution)
    lineno: u32 = 1,

    /// Allocator for this frame
    allocator: Allocator,

    /// Initialize a new frame
    pub fn init(
        allocator: Allocator,
        code: *const CodeObject,
        globals: *PyValue.Dict,
    ) !Frame {
        return .{
            .code = code,
            .globals = globals,
            .exc_handlers = .{},
            .filename = code.filename,
            .lineno = code.firstlineno,
            .allocator = allocator,
        };
    }

    /// Clean up frame resources
    pub fn deinit(self: *Frame) void {
        self.exc_handlers.deinit(self.allocator);
    }

    /// Get local variable by index
    pub fn getLocal(self: *const Frame, index: usize) ?PyValue {
        if (index < 256) {
            return self.locals[index];
        }
        return null;
    }

    /// Set local variable by index
    pub fn setLocal(self: *Frame, index: usize, value: PyValue) void {
        if (index < 256) {
            self.locals[index] = value;
        }
    }

    /// Delete local variable by index
    pub fn deleteLocal(self: *Frame, index: usize) void {
        if (index < 256) {
            self.locals[index] = null;
        }
    }

    /// Get current line number from bytecode offset
    pub fn updateLineNo(self: *Frame) void {
        self.lineno = self.code.getLineNo(self.ip);
    }

    /// Push exception handler
    pub fn pushExcHandler(self: *Frame, target: usize, stack_depth: usize) !void {
        try self.exc_handlers.append(self.allocator, .{
            .target = target,
            .stack_depth = stack_depth,
        });
    }

    /// Pop exception handler
    pub fn popExcHandler(self: *Frame) ?ExcHandler {
        if (self.exc_handlers.items.len == 0) return null;
        const len = self.exc_handlers.items.len;
        const handler = self.exc_handlers.items[len - 1];
        self.exc_handlers.items.len = len - 1;
        return handler;
    }
};

test "frame init" {
    const testing = std.testing;
    const allocator = testing.allocator;

    var globals: PyValue.Dict = .{};
    defer globals.deinit(allocator);

    const code = CodeObject{
        .bytecode = &.{},
        .constants = &.{},
        .varnames = &.{},
        .freevars = &.{},
        .cellvars = &.{},
        .names = &.{},
        .nlocals = 0,
        .stacksize = 10,
    };

    var frame = try Frame.init(allocator, &code, &globals);
    defer frame.deinit();

    try testing.expectEqual(@as(usize, 0), frame.ip);
    try testing.expectEqual(&code, frame.code);
}

test "frame locals" {
    const testing = std.testing;
    const allocator = testing.allocator;

    var globals: PyValue.Dict = .{};
    defer globals.deinit(allocator);

    const code = CodeObject{
        .bytecode = &.{},
        .constants = &.{},
        .varnames = &.{},
        .freevars = &.{},
        .cellvars = &.{},
        .names = &.{},
        .nlocals = 0,
        .stacksize = 10,
    };

    var frame = try Frame.init(allocator, &code, &globals);
    defer frame.deinit();

    // Initially null
    try testing.expect(frame.getLocal(0) == null);

    // Set and get
    frame.setLocal(0, .{ .int = 42 });
    const val = frame.getLocal(0);
    try testing.expect(val != null);
    try testing.expectEqual(@as(i64, 42), val.?.int);

    // Delete
    frame.deleteLocal(0);
    try testing.expect(frame.getLocal(0) == null);
}

test "pyvalue truthiness" {
    const testing = std.testing;

    try testing.expect(!PyValue.toBool(.{ .none = {} }));
    try testing.expect(!PyValue.toBool(.{ .bool = false }));
    try testing.expect(PyValue.toBool(.{ .bool = true }));
    try testing.expect(!PyValue.toBool(.{ .int = 0 }));
    try testing.expect(PyValue.toBool(.{ .int = 1 }));
    try testing.expect(!PyValue.toBool(.{ .string = "" }));
    try testing.expect(PyValue.toBool(.{ .string = "hello" }));
}
