/// Bytecode Frame - Call stack frame and code object definitions
///
/// Frame represents a single call stack entry in the bytecode VM.
/// CodeObject represents compiled bytecode for a function or module.
const std = @import("std");
const Allocator = std.mem.Allocator;
const opcodes = @import("opcodes.zig");
const Opcode = opcodes.Opcode;

/// PyValue - the dynamic value type for the VM
/// TODO: Replace with actual PyValue from Objects/object.zig when integrated
pub const PyValue = union(enum) {
    none: void,
    bool: bool,
    int: i64,
    float: f64,
    string: []const u8,
    list: *List,
    tuple: []const PyValue,
    dict: *Dict,
    code: *const CodeObject,
    function: *Function,
    builtin: *const BuiltinFn,
    object: *anyopaque, // Generic object pointer
    iterator: *Iterator, // Iterator for for loops
    range: Range, // range() object
    exception: *Exception, // Exception object
    generator: *Generator, // Generator object

    pub const List = std.ArrayList(PyValue);

    /// Generator object - suspended coroutine
    pub const Generator = struct {
        code: *const CodeObject,
        ip: usize = 0, // Saved instruction pointer
        locals: [256]?PyValue = [_]?PyValue{null} ** 256, // Saved locals
        stack: std.ArrayList(PyValue) = .{}, // Saved stack
        cells: []?*Cell = &.{}, // Closure cells
        globals: *Dict,
        running: bool = false,
        exhausted: bool = false,

        pub fn deinit(self: *Generator, allocator: Allocator) void {
            self.stack.deinit(allocator);
        }
    };

    /// Exception object for exception handling
    pub const Exception = struct {
        exc_type: []const u8, // Exception type name (e.g., "ValueError")
        message: []const u8, // Exception message
        cause: ?*Exception = null, // Chained exception (__cause__)
    };
    /// Dict uses StringHashMapUnmanaged for Zig 0.15 compatibility
    pub const Dict = std.StringHashMapUnmanaged(PyValue);
    pub const BuiltinFn = fn (Allocator, []const PyValue) anyerror!PyValue;

    /// Python range object
    pub const Range = struct {
        start: i64,
        stop: i64,
        step: i64,
    };

    /// Iterator over sequences
    pub const Iterator = struct {
        source: IterSource,
        index: usize = 0,

        pub const IterSource = union(enum) {
            list: *List,
            tuple: []const PyValue,
            string: []const u8,
            range: Range,
        };

        /// Get next value or null if exhausted
        pub fn next(self: *Iterator) ?PyValue {
            switch (self.source) {
                .list => |l| {
                    if (self.index < l.items.len) {
                        const val = l.items[self.index];
                        self.index += 1;
                        return val;
                    }
                    return null;
                },
                .tuple => |t| {
                    if (self.index < t.len) {
                        const val = t[self.index];
                        self.index += 1;
                        return val;
                    }
                    return null;
                },
                .string => |s| {
                    if (self.index < s.len) {
                        const val = PyValue{ .string = s[self.index..][0..1] };
                        self.index += 1;
                        return val;
                    }
                    return null;
                },
                .range => |r| {
                    const current: i64 = r.start + @as(i64, @intCast(self.index)) * r.step;
                    if (r.step > 0) {
                        if (current >= r.stop) return null;
                    } else {
                        if (current <= r.stop) return null;
                    }
                    self.index += 1;
                    return PyValue{ .int = current };
                },
            }
        }
    };

    /// Function object with code and closure
    pub const Function = struct {
        code: *const CodeObject,
        globals: *Dict,
        defaults: []const PyValue,
        cells: []?*Cell,
        name: []const u8,
    };

    /// Cell for closures
    pub const Cell = struct {
        value: ?PyValue = null,
    };

    /// Convert to boolean (Python truthiness)
    pub fn toBool(self: PyValue) bool {
        return switch (self) {
            .none => false,
            .bool => |b| b,
            .int => |i| i != 0,
            .float => |f| f != 0.0,
            .string => |s| s.len > 0,
            .list => |l| l.items.len > 0,
            .tuple => |t| t.len > 0,
            .dict => |d| d.count() > 0,
            .range => |r| {
                // range is truthy if it has any elements
                if (r.step > 0) return r.start < r.stop;
                if (r.step < 0) return r.start > r.stop;
                return false;
            },
            .code, .function, .builtin, .object, .iterator, .exception, .generator => true,
        };
    }

    /// Check if this is an integer
    pub fn isInt(self: PyValue) bool {
        return self == .int;
    }

    /// Check if this is a float
    pub fn isFloat(self: PyValue) bool {
        return self == .float;
    }

    /// Check if this is a string
    pub fn isString(self: PyValue) bool {
        return self == .string;
    }

    /// Get as integer (assumes isInt() is true)
    pub fn asInt(self: PyValue) i64 {
        return self.int;
    }

    /// Get as float, converting int if needed
    pub fn asFloat(self: PyValue) f64 {
        return switch (self) {
            .float => |f| f,
            .int => |i| @floatFromInt(i),
            else => 0.0,
        };
    }

    /// Get as string (assumes isString() is true)
    pub fn asString(self: PyValue) []const u8 {
        return self.string;
    }
};

/// Exception handler entry
pub const ExcHandler = struct {
    target: usize,                      // Handler instruction offset
    stack_depth: usize,                 // Stack depth when handler was pushed
    exc_type: ?PyValue = null,          // Exception type to match (null = catch all)
};

/// Code object flags
pub const CodeFlags = packed struct {
    generator: bool = false,
    coroutine: bool = false,
    async_generator: bool = false,
    varargs: bool = false,          // Function accepts *args
    varkeywords: bool = false,      // Function accepts **kwargs
    nested: bool = false,           // Nested function
    nofree: bool = false,           // No free variables
    _padding: u1 = 0,
};

/// Exception table entry for mapping bytecode ranges to handlers
pub const ExcEntry = struct {
    start: u32,     // Start of try block
    end: u32,       // End of try block
    target: u32,    // Handler target
    depth: u16,     // Stack depth at start
    lasti: bool,    // Push lasti to stack
};

/// Compiled code object
///
/// Contains bytecode, constants, and metadata for a function or module.
/// Immutable once created.
pub const CodeObject = struct {
    /// Raw bytecode instructions
    bytecode: []const u8,

    /// Constant pool (literals, nested code objects, etc.)
    constants: []const PyValue,

    /// Local variable names (indexed by LOAD_FAST/STORE_FAST)
    varnames: []const []const u8,

    /// Free variable names (closures from enclosing scopes)
    freevars: []const []const u8,

    /// Cell variable names (locals captured by nested functions)
    cellvars: []const []const u8,

    /// Global/attribute names (indexed by LOAD_GLOBAL/LOAD_ATTR)
    names: []const []const u8,

    /// Number of local variables
    nlocals: u16,

    /// Maximum stack depth needed
    stacksize: u16,

    /// Number of arguments (positional)
    argcount: u16 = 0,

    /// Number of positional-only arguments
    posonlyargcount: u16 = 0,

    /// Number of keyword-only arguments
    kwonlyargcount: u16 = 0,

    /// Code flags
    flags: CodeFlags = .{},

    /// Source filename
    filename: []const u8 = "<unknown>",

    /// Function/module name
    name: []const u8 = "<module>",

    /// First source line number
    firstlineno: u32 = 1,

    /// Line number table (maps bytecode offset to source line)
    linetable: []const u8 = &.{},

    /// Exception table
    exctable: []const ExcEntry = &.{},

    /// Get line number for bytecode offset
    pub fn getLineNo(self: *const CodeObject, offset: usize) u32 {
        // Simple line table format: pairs of (bytecode_delta, line_delta)
        var current_offset: usize = 0;
        var current_line: u32 = self.firstlineno;
        var i: usize = 0;

        while (i + 1 < self.linetable.len) {
            const bc_delta = self.linetable[i];
            const line_delta: i8 = @bitCast(self.linetable[i + 1]);
            current_offset += bc_delta;
            if (current_offset > offset) break;
            current_line = @intCast(@as(i64, current_line) + line_delta);
            i += 2;
        }

        return current_line;
    }

    /// Find exception handler for offset
    pub fn findHandler(self: *const CodeObject, offset: usize) ?*const ExcEntry {
        for (self.exctable) |*entry| {
            if (offset >= entry.start and offset < entry.end) {
                return entry;
            }
        }
        return null;
    }
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
