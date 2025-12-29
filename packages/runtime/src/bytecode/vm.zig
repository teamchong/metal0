/// Bytecode VM - Stack-based bytecode executor
///
/// The VM is a thin dispatch layer that calls existing runtime functions
/// for actual Python semantics. This avoids reimplementing arithmetic,
/// comparison, etc.
///
/// Key design:
/// - Uses existing runtime functions (unified_int_ops, equality, etc.)
/// - PyValue for dynamic typing
/// - Frame-based call stack
/// - Exception handler stack per frame
const std = @import("std");
const Allocator = std.mem.Allocator;

const opcodes = @import("opcodes.zig");
const Opcode = opcodes.Opcode;
const decodeVarInt = opcodes.decodeVarInt;

const frame_mod = @import("frame.zig");
const Frame = frame_mod.Frame;
const CodeObject = frame_mod.CodeObject;
const PyValue = frame_mod.PyValue;

/// VM execution errors
pub const VMError = error{
    StackUnderflow,
    StackOverflow,
    UnsupportedOpcode,
    TypeError,
    NameError,
    AttributeError,
    IndexError,
    KeyError,
    ValueError,
    ZeroDivisionError,
    StopIteration,
    OutOfMemory,
    Overflow,
};

/// Bytecode Virtual Machine
pub const VM = struct {
    /// Value stack (Zig 0.15 unmanaged ArrayList)
    stack: std.ArrayList(PyValue) = .{},

    /// Call stack (frames)
    frames: std.ArrayList(*Frame) = .{},

    /// Allocated functions (for cleanup)
    allocated_functions: std.ArrayList(*PyValue.Function) = .{},

    /// Allocated iterators (for cleanup)
    allocated_iterators: std.ArrayList(*PyValue.Iterator) = .{},

    /// Allocated exceptions (for cleanup)
    allocated_exceptions: std.ArrayList(*PyValue.Exception) = .{},

    /// Allocated cells (for closures cleanup)
    allocated_cells: std.ArrayList(*PyValue.Cell) = .{},

    /// Allocated generators (for cleanup)
    allocated_generators: std.ArrayList(*PyValue.Generator) = .{},

    /// Current active exception (for RERAISE)
    current_exception: ?*PyValue.Exception = null,

    /// Global namespace (module globals)
    globals: *PyValue.Dict,

    /// Memory allocator
    allocator: Allocator,

    /// Maximum stack size (prevent infinite recursion)
    max_stack_size: usize = 10000,

    /// Maximum recursion depth
    max_recursion: usize = 1000,

    /// Initialize a new VM
    pub fn init(allocator: Allocator, globals: *PyValue.Dict) VM {
        return .{
            .stack = .{},
            .frames = .{},
            .allocated_functions = .{},
            .allocated_iterators = .{},
            .allocated_exceptions = .{},
            .allocated_cells = .{},
            .allocated_generators = .{},
            .current_exception = null,
            .globals = globals,
            .allocator = allocator,
        };
    }

    /// Clean up VM resources
    pub fn deinit(self: *VM) void {
        // Clean up frames
        for (self.frames.items) |frame| {
            frame.deinit();
            self.allocator.destroy(frame);
        }
        self.frames.deinit(self.allocator);
        self.stack.deinit(self.allocator);

        // Clean up allocated functions
        for (self.allocated_functions.items) |func| {
            self.allocator.destroy(func);
        }
        self.allocated_functions.deinit(self.allocator);

        // Clean up allocated iterators
        for (self.allocated_iterators.items) |iter| {
            self.allocator.destroy(iter);
        }
        self.allocated_iterators.deinit(self.allocator);

        // Clean up allocated exceptions
        for (self.allocated_exceptions.items) |exc| {
            self.allocator.destroy(exc);
        }
        self.allocated_exceptions.deinit(self.allocator);

        // Clean up allocated cells
        for (self.allocated_cells.items) |cell| {
            self.allocator.destroy(cell);
        }
        self.allocated_cells.deinit(self.allocator);

        // Clean up allocated generators
        for (self.allocated_generators.items) |gen| {
            gen.deinit(self.allocator);
            self.allocator.destroy(gen);
        }
        self.allocated_generators.deinit(self.allocator);
    }

    /// Execute a code object and return the result
    pub fn execute(self: *VM, code: *const CodeObject) VMError!PyValue {
        // Create initial frame
        const frame = self.allocator.create(Frame) catch return VMError.OutOfMemory;
        frame.* = Frame.init(self.allocator, code, self.globals) catch return VMError.OutOfMemory;
        self.frames.append(self.allocator, frame) catch return VMError.OutOfMemory;

        // Run the frame
        const result = try self.runFrame(frame);

        // Clean up frame
        _ = self.frames.pop();
        frame.deinit();
        self.allocator.destroy(frame);

        return result;
    }

    /// Run a single frame to completion
    fn runFrame(self: *VM, frame: *Frame) VMError!PyValue {
        const bytecode = frame.code.bytecode;

        while (frame.ip < bytecode.len) {
            const op: Opcode = @enumFromInt(bytecode[frame.ip]);
            frame.ip += 1;

            // Update line number for error messages
            frame.updateLineNo();

            switch (op) {
                // ========================================
                // Stack operations
                // ========================================
                .NOP => {},

                .POP => {
                    _ = self.pop() catch return VMError.StackUnderflow;
                },

                .DUP => {
                    const top = self.peek() catch return VMError.StackUnderflow;
                    try self.push(top);
                },

                .DUP2 => {
                    if (self.stack.items.len < 2) return VMError.StackUnderflow;
                    const a = self.stack.items[self.stack.items.len - 2];
                    const b = self.stack.items[self.stack.items.len - 1];
                    try self.push(a);
                    try self.push(b);
                },

                .ROT2 => {
                    if (self.stack.items.len < 2) return VMError.StackUnderflow;
                    const len = self.stack.items.len;
                    const tmp = self.stack.items[len - 1];
                    self.stack.items[len - 1] = self.stack.items[len - 2];
                    self.stack.items[len - 2] = tmp;
                },

                .ROT3 => {
                    if (self.stack.items.len < 3) return VMError.StackUnderflow;
                    const len = self.stack.items.len;
                    const tmp = self.stack.items[len - 1];
                    self.stack.items[len - 1] = self.stack.items[len - 2];
                    self.stack.items[len - 2] = self.stack.items[len - 3];
                    self.stack.items[len - 3] = tmp;
                },

                .ROT4 => {
                    if (self.stack.items.len < 4) return VMError.StackUnderflow;
                    const len = self.stack.items.len;
                    const tmp = self.stack.items[len - 1];
                    self.stack.items[len - 1] = self.stack.items[len - 2];
                    self.stack.items[len - 2] = self.stack.items[len - 3];
                    self.stack.items[len - 3] = self.stack.items[len - 4];
                    self.stack.items[len - 4] = tmp;
                },

                // ========================================
                // Constants
                // ========================================
                .LOAD_CONST => {
                    const arg = self.readArg(bytecode, &frame.ip);
                    if (arg < frame.code.constants.len) {
                        try self.push(frame.code.constants[arg]);
                    } else {
                        return VMError.IndexError;
                    }
                },

                .LOAD_NONE => try self.push(.{ .none = {} }),
                .LOAD_TRUE => try self.push(.{ .bool = true }),
                .LOAD_FALSE => try self.push(.{ .bool = false }),
                .LOAD_ZERO => try self.push(.{ .int = 0 }),
                .LOAD_ONE => try self.push(.{ .int = 1 }),

                .LOAD_I8 => {
                    const arg = self.readArg(bytecode, &frame.ip);
                    const value: i8 = @bitCast(@as(u8, @intCast(arg & 0xFF)));
                    try self.push(.{ .int = value });
                },

                .LOAD_I16 => {
                    const arg = self.readArg(bytecode, &frame.ip);
                    const value: i16 = @bitCast(@as(u16, @intCast(arg & 0xFFFF)));
                    try self.push(.{ .int = value });
                },

                .LOAD_I32 => {
                    const arg = self.readArg(bytecode, &frame.ip);
                    const value: i32 = @bitCast(arg);
                    try self.push(.{ .int = value });
                },

                // ========================================
                // Local variables
                // ========================================
                .LOAD_FAST => {
                    const arg = self.readArg(bytecode, &frame.ip);
                    if (frame.getLocal(arg)) |value| {
                        try self.push(value);
                    } else {
                        return VMError.NameError;
                    }
                },

                .STORE_FAST => {
                    const arg = self.readArg(bytecode, &frame.ip);
                    const value = self.pop() catch return VMError.StackUnderflow;
                    frame.setLocal(arg, value);
                },

                .DELETE_FAST => {
                    const arg = self.readArg(bytecode, &frame.ip);
                    frame.deleteLocal(arg);
                },

                .LOAD_FAST_0 => {
                    if (frame.getLocal(0)) |value| {
                        try self.push(value);
                    } else {
                        return VMError.NameError;
                    }
                },

                .LOAD_FAST_1 => {
                    if (frame.getLocal(1)) |value| {
                        try self.push(value);
                    } else {
                        return VMError.NameError;
                    }
                },

                .LOAD_FAST_2 => {
                    if (frame.getLocal(2)) |value| {
                        try self.push(value);
                    } else {
                        return VMError.NameError;
                    }
                },

                .LOAD_FAST_3 => {
                    if (frame.getLocal(3)) |value| {
                        try self.push(value);
                    } else {
                        return VMError.NameError;
                    }
                },

                .STORE_FAST_0 => {
                    const value = self.pop() catch return VMError.StackUnderflow;
                    frame.setLocal(0, value);
                },

                .STORE_FAST_1 => {
                    const value = self.pop() catch return VMError.StackUnderflow;
                    frame.setLocal(1, value);
                },

                .STORE_FAST_2 => {
                    const value = self.pop() catch return VMError.StackUnderflow;
                    frame.setLocal(2, value);
                },

                .STORE_FAST_3 => {
                    const value = self.pop() catch return VMError.StackUnderflow;
                    frame.setLocal(3, value);
                },

                // ========================================
                // Names/globals
                // ========================================
                .LOAD_NAME, .LOAD_GLOBAL => {
                    const arg = self.readArg(bytecode, &frame.ip);
                    if (arg < frame.code.names.len) {
                        const name = frame.code.names[arg];
                        // Try locals dict first (for exec())
                        if (frame.locals_dict) |ld| {
                            if (ld.get(name)) |value| {
                                try self.push(value);
                                continue;
                            }
                        }
                        // Then globals
                        if (self.globals.get(name)) |value| {
                            try self.push(value);
                        } else {
                            return VMError.NameError;
                        }
                    } else {
                        return VMError.IndexError;
                    }
                },

                .STORE_NAME, .STORE_GLOBAL => {
                    const arg = self.readArg(bytecode, &frame.ip);
                    const value = self.pop() catch return VMError.StackUnderflow;
                    if (arg < frame.code.names.len) {
                        const name = frame.code.names[arg];
                        // For exec() with locals, store to locals_dict
                        if (op == .STORE_NAME and frame.locals_dict != null) {
                            frame.locals_dict.?.put(self.allocator, name, value) catch return VMError.OutOfMemory;
                        } else {
                            self.globals.put(self.allocator, name, value) catch return VMError.OutOfMemory;
                        }
                    } else {
                        return VMError.IndexError;
                    }
                },

                .DELETE_NAME, .DELETE_GLOBAL => {
                    const arg = self.readArg(bytecode, &frame.ip);
                    if (arg < frame.code.names.len) {
                        const name = frame.code.names[arg];
                        _ = self.globals.remove(name);
                    }
                },

                // ========================================
                // Binary operators
                // ========================================
                .ADD => {
                    const b = self.pop() catch return VMError.StackUnderflow;
                    const a = self.pop() catch return VMError.StackUnderflow;
                    try self.push(try self.vmAdd(a, b));
                },

                .SUB => {
                    const b = self.pop() catch return VMError.StackUnderflow;
                    const a = self.pop() catch return VMError.StackUnderflow;
                    try self.push(try self.vmSub(a, b));
                },

                .MUL => {
                    const b = self.pop() catch return VMError.StackUnderflow;
                    const a = self.pop() catch return VMError.StackUnderflow;
                    try self.push(try self.vmMul(a, b));
                },

                .DIV => {
                    const b = self.pop() catch return VMError.StackUnderflow;
                    const a = self.pop() catch return VMError.StackUnderflow;
                    // True division always returns float
                    const bf = b.asFloat();
                    if (bf == 0.0) return VMError.ZeroDivisionError;
                    try self.push(.{ .float = a.asFloat() / bf });
                },

                .FLOORDIV => {
                    const b = self.pop() catch return VMError.StackUnderflow;
                    const a = self.pop() catch return VMError.StackUnderflow;
                    try self.push(try self.vmFloorDiv(a, b));
                },

                .MOD => {
                    const b = self.pop() catch return VMError.StackUnderflow;
                    const a = self.pop() catch return VMError.StackUnderflow;
                    try self.push(try self.vmMod(a, b));
                },

                .POW => {
                    const b = self.pop() catch return VMError.StackUnderflow;
                    const a = self.pop() catch return VMError.StackUnderflow;
                    try self.push(try self.vmPow(a, b));
                },

                .LSHIFT => {
                    const b = self.pop() catch return VMError.StackUnderflow;
                    const a = self.pop() catch return VMError.StackUnderflow;
                    if (!a.isInt() or !b.isInt()) return VMError.TypeError;
                    const shift = b.asInt();
                    if (shift < 0) return VMError.ValueError;
                    if (shift > 63) {
                        try self.push(.{ .int = 0 }); // Would need BigInt for proper behavior
                    } else {
                        try self.push(.{ .int = a.asInt() << @intCast(shift) });
                    }
                },

                .RSHIFT => {
                    const b = self.pop() catch return VMError.StackUnderflow;
                    const a = self.pop() catch return VMError.StackUnderflow;
                    if (!a.isInt() or !b.isInt()) return VMError.TypeError;
                    const shift = b.asInt();
                    if (shift < 0) return VMError.ValueError;
                    if (shift > 63) {
                        const sign: i64 = if (a.asInt() < 0) -1 else 0;
                        try self.push(.{ .int = sign });
                    } else {
                        try self.push(.{ .int = a.asInt() >> @intCast(shift) });
                    }
                },

                .AND => {
                    const b = self.pop() catch return VMError.StackUnderflow;
                    const a = self.pop() catch return VMError.StackUnderflow;
                    if (!a.isInt() or !b.isInt()) return VMError.TypeError;
                    try self.push(.{ .int = a.asInt() & b.asInt() });
                },

                .OR => {
                    const b = self.pop() catch return VMError.StackUnderflow;
                    const a = self.pop() catch return VMError.StackUnderflow;
                    if (!a.isInt() or !b.isInt()) return VMError.TypeError;
                    try self.push(.{ .int = a.asInt() | b.asInt() });
                },

                .XOR => {
                    const b = self.pop() catch return VMError.StackUnderflow;
                    const a = self.pop() catch return VMError.StackUnderflow;
                    if (!a.isInt() or !b.isInt()) return VMError.TypeError;
                    try self.push(.{ .int = a.asInt() ^ b.asInt() });
                },

                .MATMUL => {
                    // Matrix multiplication - not supported without numpy-like types
                    // For now, return TypeError
                    return VMError.TypeError;
                },

                // ========================================
                // Unary operators
                // ========================================
                .NEG => {
                    const a = self.pop() catch return VMError.StackUnderflow;
                    if (a.isInt()) {
                        try self.push(.{ .int = -a.asInt() });
                    } else if (a.isFloat()) {
                        try self.push(.{ .float = -a.asFloat() });
                    } else {
                        return VMError.TypeError;
                    }
                },

                .POS => {
                    const a = self.pop() catch return VMError.StackUnderflow;
                    if (!a.isInt() and !a.isFloat()) return VMError.TypeError;
                    try self.push(a); // +x is x for numbers
                },

                .NOT => {
                    const a = self.pop() catch return VMError.StackUnderflow;
                    try self.push(.{ .bool = !a.toBool() });
                },

                .INVERT => {
                    const a = self.pop() catch return VMError.StackUnderflow;
                    if (!a.isInt()) return VMError.TypeError;
                    try self.push(.{ .int = ~a.asInt() });
                },

                // ========================================
                // Comparison
                // ========================================
                .LT => {
                    const b = self.pop() catch return VMError.StackUnderflow;
                    const a = self.pop() catch return VMError.StackUnderflow;
                    try self.push(.{ .bool = self.vmCompare(a, b, .lt) });
                },

                .LE => {
                    const b = self.pop() catch return VMError.StackUnderflow;
                    const a = self.pop() catch return VMError.StackUnderflow;
                    try self.push(.{ .bool = self.vmCompare(a, b, .le) });
                },

                .EQ => {
                    const b = self.pop() catch return VMError.StackUnderflow;
                    const a = self.pop() catch return VMError.StackUnderflow;
                    try self.push(.{ .bool = self.vmEqual(a, b) });
                },

                .NE => {
                    const b = self.pop() catch return VMError.StackUnderflow;
                    const a = self.pop() catch return VMError.StackUnderflow;
                    try self.push(.{ .bool = !self.vmEqual(a, b) });
                },

                .GT => {
                    const b = self.pop() catch return VMError.StackUnderflow;
                    const a = self.pop() catch return VMError.StackUnderflow;
                    try self.push(.{ .bool = self.vmCompare(a, b, .gt) });
                },

                .GE => {
                    const b = self.pop() catch return VMError.StackUnderflow;
                    const a = self.pop() catch return VMError.StackUnderflow;
                    try self.push(.{ .bool = self.vmCompare(a, b, .ge) });
                },

                .IS => {
                    const b = self.pop() catch return VMError.StackUnderflow;
                    const a = self.pop() catch return VMError.StackUnderflow;
                    // Identity comparison - for now, use equality for value types
                    try self.push(.{ .bool = self.vmIdentical(a, b) });
                },

                .IS_NOT => {
                    const b = self.pop() catch return VMError.StackUnderflow;
                    const a = self.pop() catch return VMError.StackUnderflow;
                    try self.push(.{ .bool = !self.vmIdentical(a, b) });
                },

                .IN => {
                    const container = self.pop() catch return VMError.StackUnderflow;
                    const element = self.pop() catch return VMError.StackUnderflow;
                    try self.push(.{ .bool = self.vmContains(container, element) });
                },

                .NOT_IN => {
                    const container = self.pop() catch return VMError.StackUnderflow;
                    const element = self.pop() catch return VMError.StackUnderflow;
                    try self.push(.{ .bool = !self.vmContains(container, element) });
                },

                // ========================================
                // Control flow
                // ========================================
                .JUMP => {
                    const target = self.readArg(bytecode, &frame.ip);
                    frame.ip = target;
                },

                .JUMP_IF_TRUE => {
                    const target = self.readArg(bytecode, &frame.ip);
                    const cond = self.pop() catch return VMError.StackUnderflow;
                    if (cond.toBool()) frame.ip = target;
                },

                .JUMP_IF_FALSE => {
                    const target = self.readArg(bytecode, &frame.ip);
                    const cond = self.pop() catch return VMError.StackUnderflow;
                    if (!cond.toBool()) frame.ip = target;
                },

                .JUMP_IF_TRUE_OR_POP => {
                    const target = self.readArg(bytecode, &frame.ip);
                    const cond = self.peek() catch return VMError.StackUnderflow;
                    if (cond.toBool()) {
                        frame.ip = target;
                    } else {
                        _ = self.pop() catch unreachable;
                    }
                },

                .JUMP_IF_FALSE_OR_POP => {
                    const target = self.readArg(bytecode, &frame.ip);
                    const cond = self.peek() catch return VMError.StackUnderflow;
                    if (!cond.toBool()) {
                        frame.ip = target;
                    } else {
                        _ = self.pop() catch unreachable;
                    }
                },

                .GET_ITER => {
                    // Convert TOS to an iterator
                    const iterable = self.pop() catch return VMError.StackUnderflow;
                    const iter_ptr = self.allocator.create(PyValue.Iterator) catch return VMError.OutOfMemory;
                    iter_ptr.* = switch (iterable) {
                        .list => |l| .{ .source = .{ .list = l } },
                        .tuple => |t| .{ .source = .{ .tuple = t } },
                        .string => |s| .{ .source = .{ .string = s } },
                        .range => |r| .{ .source = .{ .range = r } },
                        .iterator => |i| i.*, // Already an iterator, copy it
                        else => return VMError.TypeError,
                    };
                    // Track for cleanup (in case of early exit)
                    self.allocated_iterators.append(self.allocator, iter_ptr) catch return VMError.OutOfMemory;
                    try self.push(.{ .iterator = iter_ptr });
                },

                .FOR_ITER => {
                    // Get jump target for loop exit
                    const jump_target = self.readArg(bytecode, &frame.ip);

                    // Peek at the iterator on TOS (don't pop yet)
                    const iter_val = self.peek() catch return VMError.StackUnderflow;
                    if (iter_val != .iterator) return VMError.TypeError;

                    // Get next value
                    if (iter_val.iterator.next()) |value| {
                        // Push next value for the loop body
                        try self.push(value);
                    } else {
                        // Iterator exhausted - pop it, free it, and jump to exit
                        const exhausted = self.pop() catch unreachable;
                        // Remove from tracking list before destroying
                        for (self.allocated_iterators.items, 0..) |iter, idx| {
                            if (iter == exhausted.iterator) {
                                _ = self.allocated_iterators.orderedRemove(idx);
                                break;
                            }
                        }
                        self.allocator.destroy(exhausted.iterator);
                        frame.ip = jump_target;
                    }
                },

                .GET_LEN => {
                    const container = self.pop() catch return VMError.StackUnderflow;
                    const len: i64 = switch (container) {
                        .list => |l| @intCast(l.items.len),
                        .tuple => |t| @intCast(t.len),
                        .string => |s| @intCast(s.len),
                        .dict => |d| @intCast(d.count()),
                        .range => |r| blk: {
                            // Calculate range length: max(0, ceil((stop - start) / step))
                            if (r.step > 0) {
                                if (r.start >= r.stop) break :blk 0;
                                break :blk @divFloor(r.stop - r.start - 1, r.step) + 1;
                            } else if (r.step < 0) {
                                if (r.start <= r.stop) break :blk 0;
                                break :blk @divFloor(r.start - r.stop - 1, -r.step) + 1;
                            } else {
                                return VMError.ValueError; // step cannot be 0
                            }
                        },
                        else => return VMError.TypeError,
                    };
                    try self.push(.{ .int = len });
                },

                // ========================================
                // Function calls
                // ========================================
                .RETURN => {
                    return self.pop() catch return VMError.StackUnderflow;
                },

                .RETURN_NONE => {
                    return .{ .none = {} };
                },

                .CALL => {
                    const argc = self.readArg(bytecode, &frame.ip);
                    return try self.vmCall(frame, argc);
                },

                .CALL_0 => return try self.vmCall(frame, 0),
                .CALL_1 => return try self.vmCall(frame, 1),
                .CALL_2 => return try self.vmCall(frame, 2),
                .CALL_3 => return try self.vmCall(frame, 3),

                .CALL_KW => {
                    // Call with keyword arguments
                    // Stack: func, args..., kwnames_tuple
                    const argc = self.readArg(bytecode, &frame.ip);
                    const kwnames = self.pop() catch return VMError.StackUnderflow;
                    _ = kwnames; // Keyword names tuple (ignored for now - positional call)
                    return try self.vmCall(frame, argc);
                },

                .CALL_VAR => {
                    // Call with *args
                    // Stack: func, args_tuple
                    const args_val = self.pop() catch return VMError.StackUnderflow;
                    const func = self.pop() catch return VMError.StackUnderflow;

                    // Push back for vmCall
                    try self.push(func);

                    // Unpack args tuple onto stack
                    if (args_val == .tuple) {
                        for (args_val.tuple) |arg| {
                            try self.push(arg);
                        }
                        return try self.vmCall(frame, @intCast(args_val.tuple.len));
                    } else if (args_val == .list) {
                        for (args_val.list.items) |arg| {
                            try self.push(arg);
                        }
                        return try self.vmCall(frame, @intCast(args_val.list.items.len));
                    }
                    return VMError.TypeError;
                },

                .CALL_VAR_KW => {
                    // Call with *args and **kwargs
                    // Stack: func, args_tuple, kwargs_dict
                    _ = self.pop() catch return VMError.StackUnderflow; // kwargs (ignored)
                    const args_val = self.pop() catch return VMError.StackUnderflow;
                    const func = self.pop() catch return VMError.StackUnderflow;

                    try self.push(func);

                    if (args_val == .tuple) {
                        for (args_val.tuple) |arg| {
                            try self.push(arg);
                        }
                        return try self.vmCall(frame, @intCast(args_val.tuple.len));
                    } else if (args_val == .list) {
                        for (args_val.list.items) |arg| {
                            try self.push(arg);
                        }
                        return try self.vmCall(frame, @intCast(args_val.list.items.len));
                    }
                    return VMError.TypeError;
                },

                // ========================================
                // Build containers
                // ========================================
                .BUILD_LIST => {
                    const count = self.readArg(bytecode, &frame.ip);
                    var list: PyValue.List = .{};
                    if (count > 0) {
                        const start_idx = self.stack.items.len - count;
                        list.appendSlice(self.allocator, self.stack.items[start_idx..]) catch return VMError.OutOfMemory;
                        self.stack.items.len = start_idx;
                    }
                    const list_ptr = self.allocator.create(PyValue.List) catch return VMError.OutOfMemory;
                    list_ptr.* = list;
                    try self.push(.{ .list = list_ptr });
                },

                .BUILD_TUPLE => {
                    const count = self.readArg(bytecode, &frame.ip);
                    if (count > 0) {
                        const start_idx = self.stack.items.len - count;
                        const items = self.allocator.dupe(PyValue, self.stack.items[start_idx..]) catch return VMError.OutOfMemory;
                        self.stack.items.len = start_idx;
                        try self.push(.{ .tuple = items });
                    } else {
                        try self.push(.{ .tuple = &.{} });
                    }
                },

                .BUILD_DICT => {
                    const count = self.readArg(bytecode, &frame.ip);
                    var dict: PyValue.Dict = .{};
                    var i: usize = 0;
                    while (i < count) : (i += 1) {
                        const value = self.pop() catch return VMError.StackUnderflow;
                        const key = self.pop() catch return VMError.StackUnderflow;
                        if (!key.isString()) return VMError.TypeError;
                        dict.put(self.allocator, key.asString(), value) catch return VMError.OutOfMemory;
                    }
                    const dict_ptr = self.allocator.create(PyValue.Dict) catch return VMError.OutOfMemory;
                    dict_ptr.* = dict;
                    try self.push(.{ .dict = dict_ptr });
                },

                .BUILD_SET => {
                    // Build a set from stack items (use list internally for now)
                    const count = self.readArg(bytecode, &frame.ip);
                    var list: PyValue.List = .{};
                    var i: usize = 0;
                    while (i < count) : (i += 1) {
                        const item = self.pop() catch return VMError.StackUnderflow;
                        // Simple set: just add to list (no dedup for now)
                        list.append(self.allocator, item) catch return VMError.OutOfMemory;
                    }
                    const list_ptr = self.allocator.create(PyValue.List) catch return VMError.OutOfMemory;
                    list_ptr.* = list;
                    try self.push(.{ .list = list_ptr }); // Use list as set
                },

                .BUILD_SLICE => {
                    // Build a slice object (start, stop, step)
                    const argc = self.readArg(bytecode, &frame.ip);
                    var step: PyValue = .{ .none = {} };
                    var stop: PyValue = .{ .none = {} };
                    var start: PyValue = .{ .none = {} };

                    if (argc >= 3) step = self.pop() catch return VMError.StackUnderflow;
                    if (argc >= 2) stop = self.pop() catch return VMError.StackUnderflow;
                    if (argc >= 1) start = self.pop() catch return VMError.StackUnderflow;

                    // For now, push as a tuple (start, stop, step)
                    const slice_tuple = self.allocator.alloc(PyValue, 3) catch return VMError.OutOfMemory;
                    slice_tuple[0] = start;
                    slice_tuple[1] = stop;
                    slice_tuple[2] = step;
                    try self.push(.{ .tuple = slice_tuple });
                },

                .LIST_APPEND => {
                    // Append to list at position i from bottom of stack
                    const idx = self.readArg(bytecode, &frame.ip);
                    const item = self.pop() catch return VMError.StackUnderflow;

                    // Get list from stack position (idx is 1-based from TOS)
                    if (self.stack.items.len < idx) return VMError.StackUnderflow;
                    const list_val = self.stack.items[self.stack.items.len - idx];
                    if (list_val != .list) return VMError.TypeError;
                    list_val.list.append(self.allocator, item) catch return VMError.OutOfMemory;
                },

                .SET_ADD => {
                    // Add to set at position i (using list as set)
                    const idx = self.readArg(bytecode, &frame.ip);
                    const item = self.pop() catch return VMError.StackUnderflow;

                    if (self.stack.items.len < idx) return VMError.StackUnderflow;
                    const set_val = self.stack.items[self.stack.items.len - idx];
                    if (set_val != .list) return VMError.TypeError;
                    set_val.list.append(self.allocator, item) catch return VMError.OutOfMemory;
                },

                .DICT_UPDATE => {
                    // Update dict with another dict
                    const idx = self.readArg(bytecode, &frame.ip);
                    const update_dict = self.pop() catch return VMError.StackUnderflow;

                    if (self.stack.items.len < idx) return VMError.StackUnderflow;
                    const target_val = self.stack.items[self.stack.items.len - idx];
                    if (target_val != .dict or update_dict != .dict) return VMError.TypeError;

                    var iter = update_dict.dict.iterator();
                    while (iter.next()) |entry| {
                        target_val.dict.put(self.allocator, entry.key_ptr.*, entry.value_ptr.*) catch return VMError.OutOfMemory;
                    }
                },

                // ========================================
                // Subscript access
                // ========================================
                .BINARY_SUBSCR => {
                    const key = self.pop() catch return VMError.StackUnderflow;
                    const container = self.pop() catch return VMError.StackUnderflow;
                    try self.push(try self.vmSubscript(container, key));
                },

                .STORE_SUBSCR => {
                    // Stack: container, key, value (TOS)
                    const value = self.pop() catch return VMError.StackUnderflow;
                    const key = self.pop() catch return VMError.StackUnderflow;
                    const container = self.pop() catch return VMError.StackUnderflow;
                    try self.vmStoreSubscript(container, key, value);
                },

                .DELETE_SUBSCR => {
                    // Stack: container, key (TOS)
                    const key = self.pop() catch return VMError.StackUnderflow;
                    const container = self.pop() catch return VMError.StackUnderflow;
                    try self.vmDeleteSubscript(container, key);
                },

                // ========================================
                // Attribute access
                // ========================================
                .LOAD_ATTR => {
                    const name_idx = self.readArg(bytecode, &frame.ip);
                    if (name_idx >= frame.code.names.len) return VMError.IndexError;
                    const attr_name = frame.code.names[name_idx];
                    const obj = self.pop() catch return VMError.StackUnderflow;
                    try self.push(try self.vmGetAttr(obj, attr_name));
                },

                .STORE_ATTR => {
                    const name_idx = self.readArg(bytecode, &frame.ip);
                    if (name_idx >= frame.code.names.len) return VMError.IndexError;
                    const attr_name = frame.code.names[name_idx];
                    const value = self.pop() catch return VMError.StackUnderflow;
                    const obj = self.pop() catch return VMError.StackUnderflow;
                    try self.vmSetAttr(obj, attr_name, value);
                },

                .DELETE_ATTR => {
                    const name_idx = self.readArg(bytecode, &frame.ip);
                    if (name_idx >= frame.code.names.len) return VMError.IndexError;
                    const attr_name = frame.code.names[name_idx];
                    const obj = self.pop() catch return VMError.StackUnderflow;
                    try self.vmDelAttr(obj, attr_name);
                },

                .LOAD_METHOD => {
                    // Similar to LOAD_ATTR but pushes (method, self) for method calls
                    const name_idx = self.readArg(bytecode, &frame.ip);
                    if (name_idx >= frame.code.names.len) return VMError.IndexError;
                    const attr_name = frame.code.names[name_idx];
                    const obj = self.peek() catch return VMError.StackUnderflow;
                    const method = try self.vmGetAttr(obj, attr_name);
                    // Replace TOS with method (self is already there for bound method call)
                    self.stack.items[self.stack.items.len - 1] = method;
                },

                // ========================================
                // Exception handling
                // ========================================
                .PUSH_EXC_INFO => {
                    const target = self.readArg(bytecode, &frame.ip);
                    frame.pushExcHandler(target, self.stack.items.len) catch return VMError.OutOfMemory;
                },

                .POP_EXC_INFO => {
                    _ = frame.popExcHandler();
                },

                .RAISE => {
                    // Pop exception from stack
                    // Stack can have:
                    // - 0 args: re-raise current exception (same as RERAISE)
                    // - 1 arg: exception value (string or exception object)
                    // - 2 args: exception value, cause
                    const argc = self.readArg(bytecode, &frame.ip);
                    var cause: ?*PyValue.Exception = null;

                    if (argc >= 2) {
                        // Pop cause
                        const cause_val = self.pop() catch return VMError.StackUnderflow;
                        if (cause_val == .exception) {
                            cause = cause_val.exception;
                        }
                    }

                    if (argc >= 1) {
                        // Pop exception value
                        const exc_val = self.pop() catch return VMError.StackUnderflow;

                        // Create exception object
                        const exc = self.allocator.create(PyValue.Exception) catch return VMError.OutOfMemory;
                        exc.* = switch (exc_val) {
                            .string => |msg| .{
                                .exc_type = "Exception",
                                .message = msg,
                                .cause = cause,
                            },
                            .exception => |e| .{
                                .exc_type = e.exc_type,
                                .message = e.message,
                                .cause = cause orelse e.cause,
                            },
                            else => .{
                                .exc_type = "TypeError",
                                .message = "exceptions must be strings or exception objects",
                                .cause = null,
                            },
                        };
                        self.allocated_exceptions.append(self.allocator, exc) catch return VMError.OutOfMemory;
                        self.current_exception = exc;
                    }

                    // If no exception set, this is an error
                    if (self.current_exception == null) {
                        return VMError.ValueError; // No active exception to raise
                    }

                    // Try to find a handler
                    if (try self.handleException(frame)) |target| {
                        frame.ip = target;
                    } else {
                        // No handler found, propagate error
                        return VMError.ValueError; // Unhandled exception
                    }
                },

                .RERAISE => {
                    // Re-raise the current exception
                    if (self.current_exception == null) {
                        return VMError.ValueError; // No active exception
                    }

                    // Try to find a handler (in parent frame)
                    // First pop the current handler since we're re-raising
                    _ = frame.popExcHandler();

                    if (try self.handleException(frame)) |target| {
                        frame.ip = target;
                    } else {
                        return VMError.ValueError; // Unhandled exception
                    }
                },

                .CHECK_EXC_MATCH => {
                    // Pop expected exception type from stack
                    // Check if current exception matches
                    const expected = self.pop() catch return VMError.StackUnderflow;
                    if (self.current_exception) |exc| {
                        // Match by type name
                        const expected_type = switch (expected) {
                            .string => |s| s,
                            .exception => |e| e.exc_type,
                            else => "",
                        };
                        const matches = std.mem.eql(u8, exc.exc_type, expected_type) or
                            std.mem.eql(u8, expected_type, "Exception") or // BaseException matches all
                            std.mem.eql(u8, expected_type, "BaseException");
                        try self.push(.{ .bool = matches });
                    } else {
                        try self.push(.{ .bool = false });
                    }
                },

                .SETUP_FINALLY => {
                    // Push finally handler (like PUSH_EXC_INFO but always executes)
                    const target = self.readArg(bytecode, &frame.ip);
                    frame.pushExcHandler(target, self.stack.items.len) catch return VMError.OutOfMemory;
                },

                // ========================================
                // Closures
                // ========================================
                .MAKE_FUNCTION => {
                    // Flags indicate what's on the stack
                    const flags = self.readArg(bytecode, &frame.ip);

                    // Pop qualified name (always present in Python 3)
                    const _name = self.pop() catch return VMError.StackUnderflow;
                    _ = _name; // name is in code object

                    // Pop code object (always present)
                    const code_val = self.pop() catch return VMError.StackUnderflow;
                    if (code_val != .code) return VMError.TypeError;
                    const code = code_val.code;

                    // Pop optional closure cells (flag 0x08)
                    var cells: []?*PyValue.Cell = &.{};
                    if (flags & 0x08 != 0) {
                        const closure = self.pop() catch return VMError.StackUnderflow;
                        if (closure == .tuple) {
                            // Convert tuple of cells
                            const tuple = closure.tuple;
                            const cell_slice = self.allocator.alloc(?*PyValue.Cell, tuple.len) catch return VMError.OutOfMemory;
                            for (tuple, 0..) |item, i| {
                                if (item == .object) {
                                    cell_slice[i] = @ptrCast(@alignCast(item.object));
                                } else {
                                    cell_slice[i] = null;
                                }
                            }
                            cells = cell_slice;
                        }
                    }

                    // Pop optional annotations (flag 0x04) - ignore for now
                    if (flags & 0x04 != 0) {
                        _ = self.pop() catch return VMError.StackUnderflow;
                    }

                    // Pop optional keyword defaults (flag 0x02) - ignore for now
                    if (flags & 0x02 != 0) {
                        _ = self.pop() catch return VMError.StackUnderflow;
                    }

                    // Pop optional positional defaults (flag 0x01)
                    var defaults: []const PyValue = &.{};
                    if (flags & 0x01 != 0) {
                        const defaults_tuple = self.pop() catch return VMError.StackUnderflow;
                        if (defaults_tuple == .tuple) {
                            defaults = defaults_tuple.tuple;
                        }
                    }

                    // Create function object
                    const func = self.allocator.create(PyValue.Function) catch return VMError.OutOfMemory;
                    func.* = .{
                        .code = code,
                        .globals = self.globals,
                        .defaults = defaults,
                        .cells = cells,
                        .name = code.name,
                    };

                    // Track for cleanup
                    self.allocated_functions.append(self.allocator, func) catch return VMError.OutOfMemory;

                    try self.push(.{ .function = func });
                },

                .LOAD_DEREF => {
                    // Load value from a cell (closure variable)
                    const cell_idx = self.readArg(bytecode, &frame.ip);
                    if (cell_idx >= frame.cells.len) return VMError.IndexError;
                    if (frame.cells[cell_idx]) |cell| {
                        if (cell.value) |value| {
                            try self.push(value);
                        } else {
                            return VMError.NameError; // Unbound cell variable
                        }
                    } else {
                        return VMError.NameError; // Cell not initialized
                    }
                },

                .STORE_DEREF => {
                    // Store value to a cell
                    const cell_idx = self.readArg(bytecode, &frame.ip);
                    const value = self.pop() catch return VMError.StackUnderflow;
                    if (cell_idx >= frame.cells.len) return VMError.IndexError;
                    if (frame.cells[cell_idx]) |cell| {
                        cell.value = value;
                    } else {
                        // Create new cell if not exists
                        const new_cell = self.allocator.create(PyValue.Cell) catch return VMError.OutOfMemory;
                        new_cell.* = .{ .value = value };
                        self.allocated_cells.append(self.allocator, new_cell) catch return VMError.OutOfMemory;
                        frame.cells[cell_idx] = new_cell;
                    }
                },

                .DELETE_DEREF => {
                    // Delete value from a cell (set to null/unbound)
                    const cell_idx = self.readArg(bytecode, &frame.ip);
                    if (cell_idx >= frame.cells.len) return VMError.IndexError;
                    if (frame.cells[cell_idx]) |cell| {
                        cell.value = null;
                    }
                },

                .LOAD_CLOSURE => {
                    // Push a cell onto the stack (for creating closures)
                    const cell_idx = self.readArg(bytecode, &frame.ip);
                    if (cell_idx >= frame.cells.len) return VMError.IndexError;
                    if (frame.cells[cell_idx]) |cell| {
                        // Push the cell as an object pointer
                        try self.push(.{ .object = @ptrCast(cell) });
                    } else {
                        return VMError.NameError; // Cell not initialized
                    }
                },

                .MAKE_CELL => {
                    // Create a new cell from a local variable
                    const local_idx = self.readArg(bytecode, &frame.ip);
                    const cell_idx = self.readArg(bytecode, &frame.ip);

                    // Ensure cells array is large enough
                    if (cell_idx >= frame.cells.len) {
                        // Need to expand cells array - this shouldn't happen with proper compilation
                        return VMError.IndexError;
                    }

                    // Create new cell
                    const new_cell = self.allocator.create(PyValue.Cell) catch return VMError.OutOfMemory;

                    // Copy value from local if it exists
                    if (local_idx < 256) {
                        new_cell.* = .{ .value = frame.locals[local_idx] };
                    } else {
                        new_cell.* = .{ .value = null };
                    }

                    self.allocated_cells.append(self.allocator, new_cell) catch return VMError.OutOfMemory;
                    frame.cells[cell_idx] = new_cell;
                },

                // ========================================
                // Generators (requires frame suspension - complex)
                // ========================================
                .YIELD_VALUE => {
                    // YIELD_VALUE suspends the generator and returns a value
                    // For now, return the value directly (simplified - doesn't actually suspend)
                    // Full generator support requires frame state management
                    const value = self.pop() catch return VMError.StackUnderflow;
                    return value;
                },

                .YIELD_FROM => {
                    // Delegate to sub-iterator - simplified: just iterate and yield
                    // Full implementation requires proper generator protocol
                    const iter_val = self.pop() catch return VMError.StackUnderflow;
                    if (iter_val == .iterator) {
                        if (iter_val.iterator.next()) |value| {
                            return value;
                        }
                    }
                    return .{ .none = {} }; // Iterator exhausted
                },

                .AWAIT => {
                    // Await an awaitable object - simplified: just return the value
                    // Full async support requires event loop integration
                    const awaitable = self.pop() catch return VMError.StackUnderflow;
                    try self.push(awaitable); // Just push it back for now
                },

                .SEND => {
                    // Send value to generator - simplified
                    const value = self.pop() catch return VMError.StackUnderflow;
                    _ = value; // Ignore sent value
                    // Would normally resume generator with sent value
                    try self.push(.{ .none = {} });
                },

                // ========================================
                // Import
                // ========================================
                .IMPORT_NAME => {
                    // Import a module by name
                    // Stack: fromlist, level -> module
                    const name_idx = self.readArg(bytecode, &frame.ip);
                    if (name_idx >= frame.code.names.len) return VMError.IndexError;
                    const module_name = frame.code.names[name_idx];

                    // Pop fromlist and level (ignored for now)
                    _ = self.pop() catch return VMError.StackUnderflow; // fromlist
                    _ = self.pop() catch return VMError.StackUnderflow; // level

                    // Check if module is in globals (already imported)
                    if (self.globals.get(module_name)) |module| {
                        try self.push(module);
                    } else {
                        // Create a simple module dict
                        const module_dict = self.allocator.create(PyValue.Dict) catch return VMError.OutOfMemory;
                        module_dict.* = .{};
                        module_dict.put(self.allocator, "__name__", .{ .string = module_name }) catch return VMError.OutOfMemory;
                        self.globals.put(self.allocator, module_name, .{ .dict = module_dict }) catch return VMError.OutOfMemory;
                        try self.push(.{ .dict = module_dict });
                    }
                },

                .IMPORT_FROM => {
                    // Import an attribute from a module
                    // Stack: module -> module, attr_value
                    const name_idx = self.readArg(bytecode, &frame.ip);
                    if (name_idx >= frame.code.names.len) return VMError.IndexError;
                    const attr_name = frame.code.names[name_idx];

                    const module = self.peek() catch return VMError.StackUnderflow;
                    if (module != .dict) return VMError.TypeError;

                    if (module.dict.get(attr_name)) |value| {
                        try self.push(value);
                    } else {
                        return VMError.AttributeError; // ImportError
                    }
                },

                .IMPORT_STAR => {
                    // Import all names from module into local namespace
                    const module = self.pop() catch return VMError.StackUnderflow;
                    if (module != .dict) return VMError.TypeError;

                    // Copy all non-private names to globals
                    var iter = module.dict.iterator();
                    while (iter.next()) |entry| {
                        const key = entry.key_ptr.*;
                        if (key.len > 0 and key[0] != '_') {
                            self.globals.put(self.allocator, key, entry.value_ptr.*) catch return VMError.OutOfMemory;
                        }
                    }
                },
            }
        }

        // Implicit return None
        return .{ .none = {} };
    }

    // ========================================
    // Stack operations
    // ========================================

    fn push(self: *VM, value: PyValue) VMError!void {
        if (self.stack.items.len >= self.max_stack_size) {
            return VMError.StackOverflow;
        }
        self.stack.append(self.allocator, value) catch return VMError.OutOfMemory;
    }

    fn pop(self: *VM) VMError!PyValue {
        if (self.stack.items.len == 0) return VMError.StackUnderflow;
        const len = self.stack.items.len;
        const value = self.stack.items[len - 1];
        self.stack.items.len = len - 1;
        return value;
    }

    fn peek(self: *VM) VMError!PyValue {
        if (self.stack.items.len == 0) return VMError.StackUnderflow;
        return self.stack.items[self.stack.items.len - 1];
    }

    // ========================================
    // Argument reading
    // ========================================

    fn readArg(self: *VM, bytecode: []const u8, ip: *usize) u32 {
        _ = self;
        if (ip.* >= bytecode.len) return 0;
        const decoded = decodeVarInt(bytecode[ip.*..]);
        ip.* += decoded.size;
        return decoded.value;
    }

    // ========================================
    // Arithmetic helpers - use shared PyValue methods
    // Both VM and AOT now use the same arithmetic implementation
    // ========================================

    /// Add two values using shared PyValue.add implementation
    fn vmAdd(self: *VM, a: PyValue, b: PyValue) VMError!PyValue {
        // String concatenation needs allocation
        if (a.isString() and b.isString()) {
            const str_a = a.asString();
            const str_b = b.asString();
            const result = self.allocator.alloc(u8, str_a.len + str_b.len) catch return VMError.OutOfMemory;
            @memcpy(result[0..str_a.len], str_a);
            @memcpy(result[str_a.len..], str_b);
            return .{ .string = result };
        }
        // Use unified PyValue.add for numeric operations
        const result = a.add(b);
        return if (result == .none) VMError.TypeError else result;
    }

    /// Subtract two values using shared PyValue.sub implementation
    fn vmSub(self: *VM, a: PyValue, b: PyValue) VMError!PyValue {
        _ = self;
        const result = a.sub(b);
        return if (result == .none) VMError.TypeError else result;
    }

    /// Multiply two values using shared PyValue.mul implementation
    fn vmMul(self: *VM, a: PyValue, b: PyValue) VMError!PyValue {
        _ = self;
        const result = a.mul(b);
        return if (result == .none) VMError.TypeError else result;
    }

    /// Floor divide using shared PyValue.floordiv implementation
    fn vmFloorDiv(self: *VM, a: PyValue, b: PyValue) VMError!PyValue {
        _ = self;
        const result = a.floordiv(b);
        return if (result == .none) VMError.ZeroDivisionError else result;
    }

    /// Modulo using shared PyValue.mod implementation
    fn vmMod(self: *VM, a: PyValue, b: PyValue) VMError!PyValue {
        _ = self;
        const result = a.mod(b);
        return if (result == .none) VMError.ZeroDivisionError else result;
    }

    /// Power using shared PyValue.pow implementation
    fn vmPow(self: *VM, a: PyValue, b: PyValue) VMError!PyValue {
        _ = self;
        const result = a.pow(b);
        return if (result == .none) VMError.TypeError else result;
    }

    // ========================================
    // Comparison helpers
    // ========================================

    const CompareOp = enum { lt, le, gt, ge };

    fn vmCompare(self: *VM, a: PyValue, b: PyValue, op: CompareOp) bool {
        _ = self;
        if (a.isInt() and b.isInt()) {
            const ai = a.asInt();
            const bi = b.asInt();
            return switch (op) {
                .lt => ai < bi,
                .le => ai <= bi,
                .gt => ai > bi,
                .ge => ai >= bi,
            };
        }
        // Fall back to float comparison
        const af = a.asFloat();
        const bf = b.asFloat();
        return switch (op) {
            .lt => af < bf,
            .le => af <= bf,
            .gt => af > bf,
            .ge => af >= bf,
        };
    }

    fn vmEqual(self: *VM, a: PyValue, b: PyValue) bool {
        _ = self;
        // Same type comparison
        if (@intFromEnum(a) == @intFromEnum(b)) {
            return switch (a) {
                .none => true,
                .bool => |ab| ab == b.bool,
                .int => |ai| ai == b.int,
                .float => |af| af == b.float,
                .string => |as| std.mem.eql(u8, as, b.string),
                else => false, // Object identity for reference types
            };
        }
        // Cross-type: int vs float
        if ((a.isInt() and b.isFloat()) or (a.isFloat() and b.isInt())) {
            return a.asFloat() == b.asFloat();
        }
        return false;
    }

    fn vmIdentical(self: *VM, a: PyValue, b: PyValue) bool {
        _ = self;
        // Identity comparison
        if (@intFromEnum(a) != @intFromEnum(b)) return false;
        return switch (a) {
            .none => true,
            .bool => |ab| ab == b.bool,
            .int => |ai| ai == b.int,
            .float => |af| af == b.float,
            .string => |as| as.ptr == b.string.ptr and as.len == b.string.len,
            .list => |al| al == b.list,
            .dict => |ad| ad == b.dict,
            else => false,
        };
    }

    /// Check if element is in container (for 'in' operator)
    fn vmContains(self: *VM, container: PyValue, element: PyValue) bool {
        switch (container) {
            .list => |list| {
                for (list.items) |item| {
                    if (self.vmEqual(element, item)) return true;
                }
                return false;
            },
            .tuple => |tuple| {
                for (tuple) |item| {
                    if (self.vmEqual(element, item)) return true;
                }
                return false;
            },
            .string => |str| {
                // String containment: check if element (as string) is a substring
                if (!element.isString()) return false;
                const needle = element.asString();
                if (needle.len == 0) return true;
                if (needle.len > str.len) return false;
                // Simple substring search
                var i: usize = 0;
                while (i + needle.len <= str.len) : (i += 1) {
                    if (std.mem.eql(u8, str[i..][0..needle.len], needle)) return true;
                }
                return false;
            },
            .dict => |dict| {
                // Dict containment checks keys
                if (!element.isString()) return false;
                return dict.get(element.asString()) != null;
            },
            .range => |r| {
                // Range containment: check if element is an int within the range
                if (!element.isInt()) return false;
                const val = element.asInt();
                if (r.step > 0) {
                    if (val < r.start or val >= r.stop) return false;
                    // Check if val is reachable with the step
                    return @mod(val - r.start, r.step) == 0;
                } else if (r.step < 0) {
                    if (val > r.start or val <= r.stop) return false;
                    return @mod(r.start - val, -r.step) == 0;
                }
                return false;
            },
            else => return false,
        }
    }

    // ========================================
    // Subscript access
    // ========================================

    fn vmSubscript(self: *VM, container: PyValue, key: PyValue) VMError!PyValue {
        _ = self;
        switch (container) {
            .list => |list| {
                if (!key.isInt()) return VMError.TypeError;
                var idx = key.asInt();
                const len: i64 = @intCast(list.items.len);
                if (idx < 0) idx += len;
                if (idx < 0 or idx >= len) return VMError.IndexError;
                return list.items[@intCast(idx)];
            },
            .tuple => |tuple| {
                if (!key.isInt()) return VMError.TypeError;
                var idx = key.asInt();
                const len: i64 = @intCast(tuple.len);
                if (idx < 0) idx += len;
                if (idx < 0 or idx >= len) return VMError.IndexError;
                return tuple[@intCast(idx)];
            },
            .dict => |dict| {
                if (!key.isString()) return VMError.TypeError;
                return dict.get(key.asString()) orelse VMError.KeyError;
            },
            .string => |str| {
                if (!key.isInt()) return VMError.TypeError;
                var idx = key.asInt();
                const len: i64 = @intCast(str.len);
                if (idx < 0) idx += len;
                if (idx < 0 or idx >= len) return VMError.IndexError;
                return .{ .string = str[@intCast(idx)..][0..1] };
            },
            else => return VMError.TypeError,
        }
    }

    fn vmStoreSubscript(self: *VM, container: PyValue, key: PyValue, value: PyValue) VMError!void {
        switch (container) {
            .list => |list| {
                if (!key.isInt()) return VMError.TypeError;
                var idx = key.asInt();
                const len: i64 = @intCast(list.items.len);
                if (idx < 0) idx += len;
                if (idx < 0 or idx >= len) return VMError.IndexError;
                list.items[@intCast(idx)] = value;
            },
            .dict => |dict| {
                if (!key.isString()) return VMError.TypeError;
                dict.put(self.allocator, key.asString(), value) catch return VMError.OutOfMemory;
            },
            else => return VMError.TypeError,
        }
    }

    fn vmDeleteSubscript(self: *VM, container: PyValue, key: PyValue) VMError!void {
        _ = self;
        switch (container) {
            .list => |list| {
                if (!key.isInt()) return VMError.TypeError;
                var idx = key.asInt();
                const len: i64 = @intCast(list.items.len);
                if (idx < 0) idx += len;
                if (idx < 0 or idx >= len) return VMError.IndexError;
                _ = list.orderedRemove(@intCast(idx));
            },
            .dict => |dict| {
                if (!key.isString()) return VMError.TypeError;
                if (!dict.remove(key.asString())) return VMError.KeyError;
            },
            else => return VMError.TypeError,
        }
    }

    // ========================================
    // Attribute access
    // ========================================

    fn vmGetAttr(self: *VM, obj: PyValue, attr_name: []const u8) VMError!PyValue {
        _ = self;
        switch (obj) {
            .dict => |dict| {
                // Dict can be used as a simple object with attributes
                return dict.get(attr_name) orelse VMError.AttributeError;
            },
            .function => |func| {
                // Function attributes like __name__, __code__
                if (std.mem.eql(u8, attr_name, "__name__")) {
                    return .{ .string = func.name };
                } else if (std.mem.eql(u8, attr_name, "__code__")) {
                    return .{ .code = func.code };
                }
                return VMError.AttributeError;
            },
            .string => |str| {
                // String has limited attributes
                if (std.mem.eql(u8, attr_name, "__len__")) {
                    // Return length as int (not a method for simplicity)
                    return .{ .int = @intCast(str.len) };
                }
                return VMError.AttributeError;
            },
            .list => |list| {
                if (std.mem.eql(u8, attr_name, "__len__")) {
                    return .{ .int = @intCast(list.items.len) };
                }
                return VMError.AttributeError;
            },
            else => return VMError.AttributeError,
        }
    }

    fn vmSetAttr(self: *VM, obj: PyValue, attr_name: []const u8, value: PyValue) VMError!void {
        switch (obj) {
            .dict => |dict| {
                // Dict can be used as a simple object with attributes
                dict.put(self.allocator, attr_name, value) catch return VMError.OutOfMemory;
            },
            else => return VMError.AttributeError,
        }
    }

    fn vmDelAttr(self: *VM, obj: PyValue, attr_name: []const u8) VMError!void {
        _ = self;
        switch (obj) {
            .dict => |dict| {
                if (!dict.remove(attr_name)) return VMError.AttributeError;
            },
            else => return VMError.AttributeError,
        }
    }

    // ========================================
    // Exception handling
    // ========================================

    /// Find and activate an exception handler
    /// Returns the handler target offset if found, null if exception should propagate
    fn handleException(self: *VM, frame: *Frame) VMError!?usize {
        // Pop handler from frame's handler stack
        if (frame.popExcHandler()) |handler| {
            // Unwind value stack to handler's saved depth
            while (self.stack.items.len > handler.stack_depth) {
                _ = self.pop() catch break;
            }

            // Push the exception onto the stack for the except clause
            if (self.current_exception) |exc| {
                try self.push(.{ .exception = exc });
            }

            return handler.target;
        }

        // No handler in this frame
        return null;
    }

    // ========================================
    // Function calls
    // ========================================

    fn vmCall(self: *VM, caller: *Frame, argc: u32) VMError!PyValue {
        // Pop arguments
        if (self.stack.items.len < argc + 1) return VMError.StackUnderflow;
        const start_idx = self.stack.items.len - argc;
        const args = self.stack.items[start_idx..];
        self.stack.items.len = start_idx;

        // Pop function
        const func_val = self.pop() catch return VMError.StackUnderflow;

        switch (func_val) {
            .builtin => |bf| {
                // Call builtin function
                return bf(self.allocator, args) catch return VMError.TypeError;
            },
            .function => |func| {
                // Check recursion depth
                if (self.frames.items.len >= self.max_recursion) {
                    return VMError.StackOverflow;
                }

                // Create new frame
                const new_frame = self.allocator.create(Frame) catch return VMError.OutOfMemory;
                new_frame.* = Frame.init(self.allocator, func.code, func.globals) catch return VMError.OutOfMemory;
                new_frame.prev = caller;

                // Set arguments as locals
                for (args, 0..) |arg, i| {
                    if (i < 256) new_frame.locals[i] = arg;
                }

                // Set closure cells
                new_frame.cells = func.cells;

                // Push frame
                self.frames.append(self.allocator, new_frame) catch return VMError.OutOfMemory;

                // Run the frame
                const result = try self.runFrame(new_frame);

                // Pop frame
                _ = self.frames.pop();
                new_frame.deinit();
                self.allocator.destroy(new_frame);

                return result;
            },
            .code => |code| {
                // Direct code object call (used by eval)
                if (self.frames.items.len >= self.max_recursion) {
                    return VMError.StackOverflow;
                }

                const new_frame = self.allocator.create(Frame) catch return VMError.OutOfMemory;
                new_frame.* = Frame.init(self.allocator, code, self.globals) catch return VMError.OutOfMemory;
                new_frame.prev = caller;

                for (args, 0..) |arg, i| {
                    if (i < 256) new_frame.locals[i] = arg;
                }

                self.frames.append(self.allocator, new_frame) catch return VMError.OutOfMemory;

                const result = try self.runFrame(new_frame);

                _ = self.frames.pop();
                new_frame.deinit();
                self.allocator.destroy(new_frame);

                return result;
            },
            else => return VMError.TypeError,
        }
    }
};

test "vm basic execution" {
    const testing = std.testing;
    const allocator = testing.allocator;

    var globals: PyValue.Dict = .{};
    defer globals.deinit(allocator);

    // Simple program: LOAD_CONST 0, RETURN
    // Constant 0 = 42
    const code = CodeObject{
        .bytecode = &[_]u8{
            @intFromEnum(Opcode.LOAD_CONST), 0, // Load constant 0
            @intFromEnum(Opcode.RETURN),        // Return
        },
        .constants = &[_]PyValue{.{ .int = 42 }},
        .varnames = &.{},
        .freevars = &.{},
        .cellvars = &.{},
        .names = &.{},
        .nlocals = 0,
        .stacksize = 1,
    };

    var vm = VM.init(allocator, &globals);
    defer vm.deinit();

    const result = try vm.execute(&code);
    try testing.expectEqual(@as(i64, 42), result.int);
}

test "vm arithmetic" {
    const testing = std.testing;
    const allocator = testing.allocator;

    var globals: PyValue.Dict = .{};
    defer globals.deinit(allocator);

    // Program: 1 + 2 * 3 = 7
    // Encoded as: LOAD_CONST 0 (1), LOAD_CONST 1 (2), LOAD_CONST 2 (3), MUL, ADD, RETURN
    const code = CodeObject{
        .bytecode = &[_]u8{
            @intFromEnum(Opcode.LOAD_CONST), 0, // Push 1
            @intFromEnum(Opcode.LOAD_CONST), 1, // Push 2
            @intFromEnum(Opcode.LOAD_CONST), 2, // Push 3
            @intFromEnum(Opcode.MUL),           // 2 * 3 = 6
            @intFromEnum(Opcode.ADD),           // 1 + 6 = 7
            @intFromEnum(Opcode.RETURN),
        },
        .constants = &[_]PyValue{
            .{ .int = 1 },
            .{ .int = 2 },
            .{ .int = 3 },
        },
        .varnames = &.{},
        .freevars = &.{},
        .cellvars = &.{},
        .names = &.{},
        .nlocals = 0,
        .stacksize = 3,
    };

    var vm = VM.init(allocator, &globals);
    defer vm.deinit();

    const result = try vm.execute(&code);
    try testing.expectEqual(@as(i64, 7), result.int);
}

test "vm locals" {
    const testing = std.testing;
    const allocator = testing.allocator;

    var globals: PyValue.Dict = .{};
    defer globals.deinit(allocator);

    // Program: x = 10; return x
    const code = CodeObject{
        .bytecode = &[_]u8{
            @intFromEnum(Opcode.LOAD_CONST), 0, // Push 10
            @intFromEnum(Opcode.STORE_FAST_0),  // Store to local 0
            @intFromEnum(Opcode.LOAD_FAST_0),   // Load from local 0
            @intFromEnum(Opcode.RETURN),
        },
        .constants = &[_]PyValue{.{ .int = 10 }},
        .varnames = &[_][]const u8{"x"},
        .freevars = &.{},
        .cellvars = &.{},
        .names = &.{},
        .nlocals = 1,
        .stacksize = 1,
    };

    var vm = VM.init(allocator, &globals);
    defer vm.deinit();

    const result = try vm.execute(&code);
    try testing.expectEqual(@as(i64, 10), result.int);
}

test "vm comparison" {
    const testing = std.testing;
    const allocator = testing.allocator;

    var globals: PyValue.Dict = .{};
    defer globals.deinit(allocator);

    // Program: 5 < 10 = True
    const code = CodeObject{
        .bytecode = &[_]u8{
            @intFromEnum(Opcode.LOAD_CONST), 0, // Push 5
            @intFromEnum(Opcode.LOAD_CONST), 1, // Push 10
            @intFromEnum(Opcode.LT),            // 5 < 10
            @intFromEnum(Opcode.RETURN),
        },
        .constants = &[_]PyValue{
            .{ .int = 5 },
            .{ .int = 10 },
        },
        .varnames = &.{},
        .freevars = &.{},
        .cellvars = &.{},
        .names = &.{},
        .nlocals = 0,
        .stacksize = 2,
    };

    var vm = VM.init(allocator, &globals);
    defer vm.deinit();

    const result = try vm.execute(&code);
    try testing.expect(result.bool == true);
}

test "vm conditional jump" {
    const testing = std.testing;
    const allocator = testing.allocator;

    var globals: PyValue.Dict = .{};
    defer globals.deinit(allocator);

    // Program: if True: return 1 else: return 2
    const code = CodeObject{
        .bytecode = &[_]u8{
            @intFromEnum(Opcode.LOAD_TRUE),      // Push True
            @intFromEnum(Opcode.JUMP_IF_FALSE), 8, // Jump to offset 8 if false
            @intFromEnum(Opcode.LOAD_CONST), 0,  // Push 1
            @intFromEnum(Opcode.RETURN),         // Return 1
            @intFromEnum(Opcode.LOAD_CONST), 1,  // offset 8: Push 2
            @intFromEnum(Opcode.RETURN),         // Return 2
        },
        .constants = &[_]PyValue{
            .{ .int = 1 },
            .{ .int = 2 },
        },
        .varnames = &.{},
        .freevars = &.{},
        .cellvars = &.{},
        .names = &.{},
        .nlocals = 0,
        .stacksize = 1,
    };

    var vm = VM.init(allocator, &globals);
    defer vm.deinit();

    const result = try vm.execute(&code);
    try testing.expectEqual(@as(i64, 1), result.int);
}

test "vm range iteration" {
    const testing = std.testing;
    const allocator = testing.allocator;

    var globals: PyValue.Dict = .{};
    defer globals.deinit(allocator);

    // Program: sum = 0; for i in range(3): sum += i; return sum
    // Expected: 0 + 1 + 2 = 3
    // Bytecode layout:
    //   0-1: LOAD_ZERO              - Push 0 (sum)
    //   2:   STORE_FAST_0           - Store sum
    //   3-5: LOAD_CONST 0           - Push range(0, 3, 1)
    //   6:   GET_ITER               - Convert to iterator
    // loop_start (offset 7):
    //   7-9: FOR_ITER, target=22    - Get next or jump to end
    //   10:  STORE_FAST_1           - Store i
    //   11:  LOAD_FAST_0            - Load sum
    //   12:  LOAD_FAST_1            - Load i
    //   13:  ADD                    - sum + i
    //   14:  STORE_FAST_0           - Store sum
    //   15-17: JUMP 7               - Jump to loop start
    // loop_end (offset 18):
    //   18:  LOAD_FAST_0            - Load sum
    //   19:  RETURN                 - Return sum
    const code = CodeObject{
        .bytecode = &[_]u8{
            @intFromEnum(Opcode.LOAD_ZERO),       // 0: Push 0
            @intFromEnum(Opcode.STORE_FAST_0),    // 1: sum = 0
            @intFromEnum(Opcode.LOAD_CONST), 0,   // 2-3: Push range constant
            @intFromEnum(Opcode.GET_ITER),        // 4: Convert to iterator
            @intFromEnum(Opcode.FOR_ITER), 14,    // 5-6: Get next or jump to offset 14
            @intFromEnum(Opcode.STORE_FAST_1),    // 7: i = next_value
            @intFromEnum(Opcode.LOAD_FAST_0),     // 8: Load sum
            @intFromEnum(Opcode.LOAD_FAST_1),     // 9: Load i
            @intFromEnum(Opcode.ADD),             // 10: sum + i
            @intFromEnum(Opcode.STORE_FAST_0),    // 11: Store sum
            @intFromEnum(Opcode.JUMP), 5,         // 12-13: Jump back to FOR_ITER
            @intFromEnum(Opcode.LOAD_FAST_0),     // 14: Load sum (loop exit target)
            @intFromEnum(Opcode.RETURN),          // 15: Return
        },
        .constants = &[_]PyValue{
            .{ .range = .{ .start = 0, .stop = 3, .step = 1 } },
        },
        .varnames = &[_][]const u8{ "sum", "i" },
        .freevars = &.{},
        .cellvars = &.{},
        .names = &.{},
        .nlocals = 2,
        .stacksize = 3,
    };

    var vm = VM.init(allocator, &globals);
    defer vm.deinit();

    const result = try vm.execute(&code);
    try testing.expectEqual(@as(i64, 3), result.int);
}

test "vm list iteration" {
    const testing = std.testing;
    const allocator = testing.allocator;

    var globals: PyValue.Dict = .{};
    defer globals.deinit(allocator);

    // Create a list [10, 20, 30]
    var list: PyValue.List = .{};
    defer list.deinit(allocator);
    try list.append(allocator, .{ .int = 10 });
    try list.append(allocator, .{ .int = 20 });
    try list.append(allocator, .{ .int = 30 });

    const list_ptr = try allocator.create(PyValue.List);
    defer allocator.destroy(list_ptr);
    list_ptr.* = list;

    // Program: sum = 0; for x in [10,20,30]: sum += x; return sum
    // Expected: 10 + 20 + 30 = 60
    const code = CodeObject{
        .bytecode = &[_]u8{
            @intFromEnum(Opcode.LOAD_ZERO),       // 0: Push 0
            @intFromEnum(Opcode.STORE_FAST_0),    // 1: sum = 0
            @intFromEnum(Opcode.LOAD_CONST), 0,   // 2-3: Push list
            @intFromEnum(Opcode.GET_ITER),        // 4: Convert to iterator
            @intFromEnum(Opcode.FOR_ITER), 14,    // 5-6: Get next or jump to offset 14
            @intFromEnum(Opcode.STORE_FAST_1),    // 7: x = next_value
            @intFromEnum(Opcode.LOAD_FAST_0),     // 8: Load sum
            @intFromEnum(Opcode.LOAD_FAST_1),     // 9: Load x
            @intFromEnum(Opcode.ADD),             // 10: sum + x
            @intFromEnum(Opcode.STORE_FAST_0),    // 11: Store sum
            @intFromEnum(Opcode.JUMP), 5,         // 12-13: Jump back to FOR_ITER
            @intFromEnum(Opcode.LOAD_FAST_0),     // 14: Load sum (loop exit target)
            @intFromEnum(Opcode.RETURN),          // 15: Return
        },
        .constants = &[_]PyValue{
            .{ .list = list_ptr },
        },
        .varnames = &[_][]const u8{ "sum", "x" },
        .freevars = &.{},
        .cellvars = &.{},
        .names = &.{},
        .nlocals = 2,
        .stacksize = 3,
    };

    var vm = VM.init(allocator, &globals);
    defer vm.deinit();

    const result = try vm.execute(&code);
    try testing.expectEqual(@as(i64, 60), result.int);
}

test "vm get_len" {
    const testing = std.testing;
    const allocator = testing.allocator;

    var globals: PyValue.Dict = .{};
    defer globals.deinit(allocator);

    // Program: return len(range(0, 5, 1))  = 5
    const code = CodeObject{
        .bytecode = &[_]u8{
            @intFromEnum(Opcode.LOAD_CONST), 0, // Push range
            @intFromEnum(Opcode.GET_LEN),       // Get length
            @intFromEnum(Opcode.RETURN),
        },
        .constants = &[_]PyValue{
            .{ .range = .{ .start = 0, .stop = 5, .step = 1 } },
        },
        .varnames = &.{},
        .freevars = &.{},
        .cellvars = &.{},
        .names = &.{},
        .nlocals = 0,
        .stacksize = 1,
    };

    var vm = VM.init(allocator, &globals);
    defer vm.deinit();

    const result = try vm.execute(&code);
    try testing.expectEqual(@as(i64, 5), result.int);
}

test "vm get_len with step" {
    const testing = std.testing;
    const allocator = testing.allocator;

    var globals: PyValue.Dict = .{};
    defer globals.deinit(allocator);

    // Program: return len(range(0, 10, 2))  = 5 (0, 2, 4, 6, 8)
    const code = CodeObject{
        .bytecode = &[_]u8{
            @intFromEnum(Opcode.LOAD_CONST), 0, // Push range
            @intFromEnum(Opcode.GET_LEN),       // Get length
            @intFromEnum(Opcode.RETURN),
        },
        .constants = &[_]PyValue{
            .{ .range = .{ .start = 0, .stop = 10, .step = 2 } },
        },
        .varnames = &.{},
        .freevars = &.{},
        .cellvars = &.{},
        .names = &.{},
        .nlocals = 0,
        .stacksize = 1,
    };

    var vm = VM.init(allocator, &globals);
    defer vm.deinit();

    const result = try vm.execute(&code);
    try testing.expectEqual(@as(i64, 5), result.int);
}

test "vm string iteration" {
    const testing = std.testing;
    const allocator = testing.allocator;

    var globals: PyValue.Dict = .{};
    defer globals.deinit(allocator);

    // Program: count = 0; for c in "abc": count += 1; return count
    // Expected: 3
    const code = CodeObject{
        .bytecode = &[_]u8{
            @intFromEnum(Opcode.LOAD_ZERO),       // 0: Push 0
            @intFromEnum(Opcode.STORE_FAST_0),    // 1: count = 0
            @intFromEnum(Opcode.LOAD_CONST), 0,   // 2-3: Push "abc"
            @intFromEnum(Opcode.GET_ITER),        // 4: Convert to iterator
            @intFromEnum(Opcode.FOR_ITER), 14,    // 5-6: Get next or jump to offset 14
            @intFromEnum(Opcode.STORE_FAST_1),    // 7: c = next_value
            @intFromEnum(Opcode.LOAD_FAST_0),     // 8: Load count
            @intFromEnum(Opcode.LOAD_ONE),        // 9: Push 1
            @intFromEnum(Opcode.ADD),             // 10: count + 1
            @intFromEnum(Opcode.STORE_FAST_0),    // 11: Store count
            @intFromEnum(Opcode.JUMP), 5,         // 12-13: Jump back to FOR_ITER
            @intFromEnum(Opcode.LOAD_FAST_0),     // 14: Load count (loop exit target)
            @intFromEnum(Opcode.RETURN),          // 15: Return
        },
        .constants = &[_]PyValue{
            .{ .string = "abc" },
        },
        .varnames = &[_][]const u8{ "count", "c" },
        .freevars = &.{},
        .cellvars = &.{},
        .names = &.{},
        .nlocals = 2,
        .stacksize = 3,
    };

    var vm = VM.init(allocator, &globals);
    defer vm.deinit();

    const result = try vm.execute(&code);
    try testing.expectEqual(@as(i64, 3), result.int);
}

test "vm in operator list" {
    const testing = std.testing;
    const allocator = testing.allocator;

    var globals: PyValue.Dict = .{};
    defer globals.deinit(allocator);

    // Create a list [1, 2, 3]
    var list: PyValue.List = .{};
    defer list.deinit(allocator);
    try list.append(allocator, .{ .int = 1 });
    try list.append(allocator, .{ .int = 2 });
    try list.append(allocator, .{ .int = 3 });

    const list_ptr = try allocator.create(PyValue.List);
    defer allocator.destroy(list_ptr);
    list_ptr.* = list;

    // Program: return 2 in [1, 2, 3]  -> True
    const code = CodeObject{
        .bytecode = &[_]u8{
            @intFromEnum(Opcode.LOAD_CONST), 0, // Push 2
            @intFromEnum(Opcode.LOAD_CONST), 1, // Push list
            @intFromEnum(Opcode.IN),            // 2 in list
            @intFromEnum(Opcode.RETURN),
        },
        .constants = &[_]PyValue{
            .{ .int = 2 },
            .{ .list = list_ptr },
        },
        .varnames = &.{},
        .freevars = &.{},
        .cellvars = &.{},
        .names = &.{},
        .nlocals = 0,
        .stacksize = 2,
    };

    var vm = VM.init(allocator, &globals);
    defer vm.deinit();

    const result = try vm.execute(&code);
    try testing.expect(result.bool == true);
}

test "vm not in operator" {
    const testing = std.testing;
    const allocator = testing.allocator;

    var globals: PyValue.Dict = .{};
    defer globals.deinit(allocator);

    // Program: return 5 not in range(0, 3, 1) -> True
    const code = CodeObject{
        .bytecode = &[_]u8{
            @intFromEnum(Opcode.LOAD_CONST), 0, // Push 5
            @intFromEnum(Opcode.LOAD_CONST), 1, // Push range
            @intFromEnum(Opcode.NOT_IN),        // 5 not in range
            @intFromEnum(Opcode.RETURN),
        },
        .constants = &[_]PyValue{
            .{ .int = 5 },
            .{ .range = .{ .start = 0, .stop = 3, .step = 1 } },
        },
        .varnames = &.{},
        .freevars = &.{},
        .cellvars = &.{},
        .names = &.{},
        .nlocals = 0,
        .stacksize = 2,
    };

    var vm = VM.init(allocator, &globals);
    defer vm.deinit();

    const result = try vm.execute(&code);
    try testing.expect(result.bool == true);
}

test "vm in operator string" {
    const testing = std.testing;
    const allocator = testing.allocator;

    var globals: PyValue.Dict = .{};
    defer globals.deinit(allocator);

    // Program: return "el" in "hello" -> True
    const code = CodeObject{
        .bytecode = &[_]u8{
            @intFromEnum(Opcode.LOAD_CONST), 0, // Push "el"
            @intFromEnum(Opcode.LOAD_CONST), 1, // Push "hello"
            @intFromEnum(Opcode.IN),            // "el" in "hello"
            @intFromEnum(Opcode.RETURN),
        },
        .constants = &[_]PyValue{
            .{ .string = "el" },
            .{ .string = "hello" },
        },
        .varnames = &.{},
        .freevars = &.{},
        .cellvars = &.{},
        .names = &.{},
        .nlocals = 0,
        .stacksize = 2,
    };

    var vm = VM.init(allocator, &globals);
    defer vm.deinit();

    const result = try vm.execute(&code);
    try testing.expect(result.bool == true);
}

test "vm store_subscr list" {
    const testing = std.testing;
    const allocator = testing.allocator;

    var globals: PyValue.Dict = .{};
    defer globals.deinit(allocator);

    // Create a list [1, 2, 3]
    var list: PyValue.List = .{};
    defer list.deinit(allocator);
    try list.append(allocator, .{ .int = 1 });
    try list.append(allocator, .{ .int = 2 });
    try list.append(allocator, .{ .int = 3 });

    const list_ptr = try allocator.create(PyValue.List);
    defer allocator.destroy(list_ptr);
    list_ptr.* = list;

    // Program: lst[1] = 99; return lst[1]
    const code = CodeObject{
        .bytecode = &[_]u8{
            @intFromEnum(Opcode.LOAD_CONST), 0, // Push list
            @intFromEnum(Opcode.LOAD_CONST), 1, // Push index 1
            @intFromEnum(Opcode.LOAD_CONST), 2, // Push value 99
            @intFromEnum(Opcode.STORE_SUBSCR),  // lst[1] = 99
            @intFromEnum(Opcode.LOAD_CONST), 0, // Push list
            @intFromEnum(Opcode.LOAD_CONST), 1, // Push index 1
            @intFromEnum(Opcode.BINARY_SUBSCR), // Get lst[1]
            @intFromEnum(Opcode.RETURN),
        },
        .constants = &[_]PyValue{
            .{ .list = list_ptr },
            .{ .int = 1 },
            .{ .int = 99 },
        },
        .varnames = &.{},
        .freevars = &.{},
        .cellvars = &.{},
        .names = &.{},
        .nlocals = 0,
        .stacksize = 3,
    };

    var vm = VM.init(allocator, &globals);
    defer vm.deinit();

    const result = try vm.execute(&code);
    try testing.expectEqual(@as(i64, 99), result.int);
}

test "vm delete_subscr list" {
    const testing = std.testing;
    const allocator = testing.allocator;

    var globals: PyValue.Dict = .{};
    defer globals.deinit(allocator);

    // Create a list [1, 2, 3]
    var list: PyValue.List = .{};
    defer list.deinit(allocator);
    try list.append(allocator, .{ .int = 1 });
    try list.append(allocator, .{ .int = 2 });
    try list.append(allocator, .{ .int = 3 });

    const list_ptr = try allocator.create(PyValue.List);
    defer allocator.destroy(list_ptr);
    list_ptr.* = list;

    // Program: del lst[0]; return len(lst) (should be 2)
    const code = CodeObject{
        .bytecode = &[_]u8{
            @intFromEnum(Opcode.LOAD_CONST), 0, // Push list
            @intFromEnum(Opcode.LOAD_CONST), 1, // Push index 0
            @intFromEnum(Opcode.DELETE_SUBSCR), // del lst[0]
            @intFromEnum(Opcode.LOAD_CONST), 0, // Push list
            @intFromEnum(Opcode.GET_LEN),       // len(lst)
            @intFromEnum(Opcode.RETURN),
        },
        .constants = &[_]PyValue{
            .{ .list = list_ptr },
            .{ .int = 0 },
        },
        .varnames = &.{},
        .freevars = &.{},
        .cellvars = &.{},
        .names = &.{},
        .nlocals = 0,
        .stacksize = 2,
    };

    var vm = VM.init(allocator, &globals);
    defer vm.deinit();

    const result = try vm.execute(&code);
    try testing.expectEqual(@as(i64, 2), result.int);
}

test "vm make_function and call" {
    const testing = std.testing;
    const allocator = testing.allocator;

    var globals: PyValue.Dict = .{};
    defer globals.deinit(allocator);

    // Inner function: def add_one(x): return x + 1
    const inner_code = CodeObject{
        .bytecode = &[_]u8{
            @intFromEnum(Opcode.LOAD_FAST_0),   // Load x
            @intFromEnum(Opcode.LOAD_ONE),      // Push 1
            @intFromEnum(Opcode.ADD),           // x + 1
            @intFromEnum(Opcode.RETURN),
        },
        .constants = &.{},
        .varnames = &[_][]const u8{"x"},
        .freevars = &.{},
        .cellvars = &.{},
        .names = &.{},
        .nlocals = 1,
        .stacksize = 2,
        .argcount = 1,
        .name = "add_one",
    };

    // Outer: create function, call it with 5, return result
    // def add_one(x): return x + 1
    // return add_one(5)
    const code = CodeObject{
        .bytecode = &[_]u8{
            @intFromEnum(Opcode.LOAD_CONST), 0,   // Push code object
            @intFromEnum(Opcode.LOAD_CONST), 1,   // Push function name
            @intFromEnum(Opcode.MAKE_FUNCTION), 0, // Create function (no defaults/closure)
            @intFromEnum(Opcode.STORE_FAST_0),    // Store as local
            @intFromEnum(Opcode.LOAD_FAST_0),     // Load function
            @intFromEnum(Opcode.LOAD_CONST), 2,   // Push argument 5
            @intFromEnum(Opcode.CALL_1),          // Call with 1 arg
            @intFromEnum(Opcode.RETURN),
        },
        .constants = &[_]PyValue{
            .{ .code = &inner_code },
            .{ .string = "add_one" },
            .{ .int = 5 },
        },
        .varnames = &[_][]const u8{"add_one"},
        .freevars = &.{},
        .cellvars = &.{},
        .names = &.{},
        .nlocals = 1,
        .stacksize = 3,
    };

    var vm = VM.init(allocator, &globals);
    defer vm.deinit();

    const result = try vm.execute(&code);
    try testing.expectEqual(@as(i64, 6), result.int);
}

test "vm load_attr dict" {
    const testing = std.testing;
    const allocator = testing.allocator;

    var globals: PyValue.Dict = .{};
    defer globals.deinit(allocator);

    // Create a dict {"x": 42, "y": 100}
    var obj_dict: PyValue.Dict = .{};
    try obj_dict.put(allocator, "x", .{ .int = 42 });
    try obj_dict.put(allocator, "y", .{ .int = 100 });
    defer obj_dict.deinit(allocator);

    const dict_ptr = try allocator.create(PyValue.Dict);
    defer allocator.destroy(dict_ptr);
    dict_ptr.* = obj_dict;

    // Program: return obj.x
    const code = CodeObject{
        .bytecode = &[_]u8{
            @intFromEnum(Opcode.LOAD_CONST), 0, // Push dict
            @intFromEnum(Opcode.LOAD_ATTR), 0,  // Get attr "x"
            @intFromEnum(Opcode.RETURN),
        },
        .constants = &[_]PyValue{
            .{ .dict = dict_ptr },
        },
        .varnames = &.{},
        .freevars = &.{},
        .cellvars = &.{},
        .names = &[_][]const u8{"x"},
        .nlocals = 0,
        .stacksize = 1,
    };

    var vm = VM.init(allocator, &globals);
    defer vm.deinit();

    const result = try vm.execute(&code);
    try testing.expectEqual(@as(i64, 42), result.int);
}

test "vm store_attr dict" {
    const testing = std.testing;
    const allocator = testing.allocator;

    var globals: PyValue.Dict = .{};
    defer globals.deinit(allocator);

    // Create an empty dict (directly in allocated memory)
    const dict_ptr = try allocator.create(PyValue.Dict);
    dict_ptr.* = .{};
    defer {
        dict_ptr.deinit(allocator);
        allocator.destroy(dict_ptr);
    }

    // Program: obj.x = 99; return obj.x
    const code = CodeObject{
        .bytecode = &[_]u8{
            @intFromEnum(Opcode.LOAD_CONST), 0, // Push dict
            @intFromEnum(Opcode.LOAD_CONST), 1, // Push 99
            @intFromEnum(Opcode.STORE_ATTR), 0, // obj.x = 99
            @intFromEnum(Opcode.LOAD_CONST), 0, // Push dict again
            @intFromEnum(Opcode.LOAD_ATTR), 0,  // Get attr "x"
            @intFromEnum(Opcode.RETURN),
        },
        .constants = &[_]PyValue{
            .{ .dict = dict_ptr },
            .{ .int = 99 },
        },
        .varnames = &.{},
        .freevars = &.{},
        .cellvars = &.{},
        .names = &[_][]const u8{"x"},
        .nlocals = 0,
        .stacksize = 2,
    };

    var vm = VM.init(allocator, &globals);
    defer vm.deinit();

    const result = try vm.execute(&code);
    try testing.expectEqual(@as(i64, 99), result.int);
}

test "vm delete_attr dict" {
    const testing = std.testing;
    const allocator = testing.allocator;

    var globals: PyValue.Dict = .{};
    defer globals.deinit(allocator);

    // Create a dict {"x": 42, "y": 100}
    var obj_dict: PyValue.Dict = .{};
    try obj_dict.put(allocator, "x", .{ .int = 42 });
    try obj_dict.put(allocator, "y", .{ .int = 100 });
    defer obj_dict.deinit(allocator);

    const dict_ptr = try allocator.create(PyValue.Dict);
    defer allocator.destroy(dict_ptr);
    dict_ptr.* = obj_dict;

    // Program: del obj.x; return obj.y (should still work)
    const code = CodeObject{
        .bytecode = &[_]u8{
            @intFromEnum(Opcode.LOAD_CONST), 0, // Push dict
            @intFromEnum(Opcode.DELETE_ATTR), 0, // del obj.x
            @intFromEnum(Opcode.LOAD_CONST), 0,  // Push dict again
            @intFromEnum(Opcode.LOAD_ATTR), 1,   // Get attr "y"
            @intFromEnum(Opcode.RETURN),
        },
        .constants = &[_]PyValue{
            .{ .dict = dict_ptr },
        },
        .varnames = &.{},
        .freevars = &.{},
        .cellvars = &.{},
        .names = &[_][]const u8{ "x", "y" },
        .nlocals = 0,
        .stacksize = 1,
    };

    var vm = VM.init(allocator, &globals);
    defer vm.deinit();

    const result = try vm.execute(&code);
    try testing.expectEqual(@as(i64, 100), result.int);
}

test "vm load_attr function __name__" {
    const testing = std.testing;
    const allocator = testing.allocator;

    var globals: PyValue.Dict = .{};
    defer globals.deinit(allocator);

    // Create a function code object
    const inner_code = CodeObject{
        .bytecode = &[_]u8{
            @intFromEnum(Opcode.LOAD_NONE),
            @intFromEnum(Opcode.RETURN),
        },
        .constants = &.{},
        .varnames = &.{},
        .freevars = &.{},
        .cellvars = &.{},
        .names = &.{},
        .nlocals = 0,
        .stacksize = 1,
        .name = "my_function",
    };

    // Program: create function, return func.__name__
    const code = CodeObject{
        .bytecode = &[_]u8{
            @intFromEnum(Opcode.LOAD_CONST), 0,   // Push code object
            @intFromEnum(Opcode.LOAD_CONST), 1,   // Push function name
            @intFromEnum(Opcode.MAKE_FUNCTION), 0, // Create function
            @intFromEnum(Opcode.LOAD_ATTR), 0,    // Get __name__
            @intFromEnum(Opcode.RETURN),
        },
        .constants = &[_]PyValue{
            .{ .code = &inner_code },
            .{ .string = "my_function" },
        },
        .varnames = &.{},
        .freevars = &.{},
        .cellvars = &.{},
        .names = &[_][]const u8{"__name__"},
        .nlocals = 0,
        .stacksize = 2,
    };

    var vm = VM.init(allocator, &globals);
    defer vm.deinit();

    const result = try vm.execute(&code);
    try testing.expectEqualStrings("my_function", result.string);
}

test "vm raise and catch exception" {
    const testing = std.testing;
    const allocator = testing.allocator;

    var globals: PyValue.Dict = .{};
    defer globals.deinit(allocator);

    // Program: try: raise "error"; except: return 99
    // Should catch the exception and return 99
    const code = CodeObject{
        .bytecode = &[_]u8{
            @intFromEnum(Opcode.PUSH_EXC_INFO), 10, // 0-1: Push handler at offset 10
            @intFromEnum(Opcode.LOAD_CONST), 0,    // 2-3: Push "error" message
            @intFromEnum(Opcode.RAISE), 1,         // 4-5: Raise with 1 arg
            @intFromEnum(Opcode.LOAD_ZERO),        // 6: (unreachable)
            @intFromEnum(Opcode.RETURN),           // 7: (unreachable)
            0, 0,                                  // 8-9: padding
            @intFromEnum(Opcode.POP),              // 10: Pop exception (handler target)
            @intFromEnum(Opcode.POP_EXC_INFO),     // 11: Pop handler
            @intFromEnum(Opcode.LOAD_CONST), 1,    // 12-13: Load 99
            @intFromEnum(Opcode.RETURN),           // 14: Return 99
        },
        .constants = &[_]PyValue{
            .{ .string = "error" },
            .{ .int = 99 },
        },
        .varnames = &.{},
        .freevars = &.{},
        .cellvars = &.{},
        .names = &.{},
        .nlocals = 0,
        .stacksize = 2,
    };

    var vm = VM.init(allocator, &globals);
    defer vm.deinit();

    const result = try vm.execute(&code);
    try testing.expectEqual(@as(i64, 99), result.int);
}

test "vm check_exc_match" {
    const testing = std.testing;
    const allocator = testing.allocator;

    var globals: PyValue.Dict = .{};
    defer globals.deinit(allocator);

    // Program: raise "error", check if matches "Exception", return result
    const code = CodeObject{
        .bytecode = &[_]u8{
            @intFromEnum(Opcode.PUSH_EXC_INFO), 10, // 0-1: Push handler
            @intFromEnum(Opcode.LOAD_CONST), 0,    // 2-3: Push "error"
            @intFromEnum(Opcode.RAISE), 1,         // 4-5: Raise
            @intFromEnum(Opcode.LOAD_ZERO),        // 6: (unreachable)
            @intFromEnum(Opcode.RETURN),           // 7: (unreachable)
            0, 0,                                  // 8-9: padding
            @intFromEnum(Opcode.POP),              // 10: Pop exception
            @intFromEnum(Opcode.LOAD_CONST), 1,    // 11-12: Load "Exception"
            @intFromEnum(Opcode.CHECK_EXC_MATCH),  // 13: Check match
            @intFromEnum(Opcode.POP_EXC_INFO),     // 14: Pop handler
            @intFromEnum(Opcode.RETURN),           // 15: Return match result
        },
        .constants = &[_]PyValue{
            .{ .string = "error" },
            .{ .string = "Exception" },
        },
        .varnames = &.{},
        .freevars = &.{},
        .cellvars = &.{},
        .names = &.{},
        .nlocals = 0,
        .stacksize = 2,
    };

    var vm = VM.init(allocator, &globals);
    defer vm.deinit();

    const result = try vm.execute(&code);
    // "Exception" matches all exceptions
    try testing.expect(result.bool == true);
}

test "vm unhandled exception" {
    const testing = std.testing;
    const allocator = testing.allocator;

    var globals: PyValue.Dict = .{};
    defer globals.deinit(allocator);

    // Program: raise "error" with no handler
    const code = CodeObject{
        .bytecode = &[_]u8{
            @intFromEnum(Opcode.LOAD_CONST), 0, // Push "error"
            @intFromEnum(Opcode.RAISE), 1,      // Raise
            @intFromEnum(Opcode.RETURN),
        },
        .constants = &[_]PyValue{
            .{ .string = "error" },
        },
        .varnames = &.{},
        .freevars = &.{},
        .cellvars = &.{},
        .names = &.{},
        .nlocals = 0,
        .stacksize = 1,
    };

    var vm = VM.init(allocator, &globals);
    defer vm.deinit();

    // Should return an error (unhandled exception)
    const result = vm.execute(&code);
    try testing.expectError(VMError.ValueError, result);
}

test "vm closure load_deref" {
    const testing = std.testing;
    const allocator = testing.allocator;

    var globals: PyValue.Dict = .{};
    defer globals.deinit(allocator);

    // Create a cell with value 42
    const cell = try allocator.create(PyValue.Cell);
    defer allocator.destroy(cell);
    cell.* = .{ .value = .{ .int = 42 } };

    // Program: return cell[0] (the captured value)
    const code = CodeObject{
        .bytecode = &[_]u8{
            @intFromEnum(Opcode.LOAD_DEREF), 0, // Load from cell 0
            @intFromEnum(Opcode.RETURN),
        },
        .constants = &.{},
        .varnames = &.{},
        .freevars = &[_][]const u8{"x"},
        .cellvars = &.{},
        .names = &.{},
        .nlocals = 0,
        .stacksize = 1,
    };

    var vm = VM.init(allocator, &globals);
    defer vm.deinit();

    // Create frame with cell (not tracked by VM)
    var frame = try Frame.init(allocator, &code, &globals);
    defer frame.deinit();

    // Allocate cells array
    var cells_array = [_]?*PyValue.Cell{cell};
    frame.cells = &cells_array;

    // Execute frame directly (frame is local, not in vm.frames)
    const result = try vm.runFrame(&frame);

    try testing.expectEqual(@as(i64, 42), result.int);
}

test "vm closure store_deref" {
    const testing = std.testing;
    const allocator = testing.allocator;

    var globals: PyValue.Dict = .{};
    defer globals.deinit(allocator);

    // Create a cell with initial value
    const cell = try allocator.create(PyValue.Cell);
    defer allocator.destroy(cell);
    cell.* = .{ .value = .{ .int = 0 } };

    // Program: cell[0] = 99; return cell[0]
    const code = CodeObject{
        .bytecode = &[_]u8{
            @intFromEnum(Opcode.LOAD_CONST), 0,  // Push 99
            @intFromEnum(Opcode.STORE_DEREF), 0, // Store to cell 0
            @intFromEnum(Opcode.LOAD_DEREF), 0,  // Load from cell 0
            @intFromEnum(Opcode.RETURN),
        },
        .constants = &[_]PyValue{.{ .int = 99 }},
        .varnames = &.{},
        .freevars = &[_][]const u8{"x"},
        .cellvars = &.{},
        .names = &.{},
        .nlocals = 0,
        .stacksize = 1,
    };

    var vm = VM.init(allocator, &globals);
    defer vm.deinit();

    // Create frame with cell (not tracked by VM)
    var frame = try Frame.init(allocator, &code, &globals);
    defer frame.deinit();

    // Allocate cells array
    var cells_array = [_]?*PyValue.Cell{cell};
    frame.cells = &cells_array;

    // Execute frame directly
    const result = try vm.runFrame(&frame);

    try testing.expectEqual(@as(i64, 99), result.int);
    // Also verify the cell was updated
    try testing.expectEqual(@as(i64, 99), cell.value.?.int);
}

test "vm import_name" {
    const testing = std.testing;
    const allocator = testing.allocator;

    var globals: PyValue.Dict = .{};
    defer globals.deinit(allocator);

    // Program: import mymodule; return mymodule.__name__
    const code = CodeObject{
        .bytecode = &[_]u8{
            @intFromEnum(Opcode.LOAD_NONE),       // 0: Push None (fromlist)
            @intFromEnum(Opcode.LOAD_ZERO),       // 1: Push 0 (level)
            @intFromEnum(Opcode.IMPORT_NAME), 0,  // 2-3: Import "mymodule"
            @intFromEnum(Opcode.LOAD_ATTR), 1,    // 4-5: Get __name__
            @intFromEnum(Opcode.RETURN),          // 6
        },
        .constants = &.{},
        .varnames = &.{},
        .freevars = &.{},
        .cellvars = &.{},
        .names = &[_][]const u8{ "mymodule", "__name__" },
        .nlocals = 0,
        .stacksize = 3,
    };

    var vm = VM.init(allocator, &globals);
    defer vm.deinit();

    const result = try vm.execute(&code);
    try testing.expectEqualStrings("mymodule", result.string);

    // Clean up the created module dict
    if (globals.get("mymodule")) |mod| {
        if (mod == .dict) {
            mod.dict.deinit(allocator);
            allocator.destroy(mod.dict);
        }
    }
}

test "vm import_from" {
    const testing = std.testing;
    const allocator = testing.allocator;

    var globals: PyValue.Dict = .{};
    defer globals.deinit(allocator);

    // Pre-create a module with an attribute
    const module_dict = try allocator.create(PyValue.Dict);
    module_dict.* = .{};
    defer {
        module_dict.deinit(allocator);
        allocator.destroy(module_dict);
    }
    try module_dict.put(allocator, "__name__", .{ .string = "mymod" });
    try module_dict.put(allocator, "foo", .{ .int = 42 });
    try globals.put(allocator, "mymod", .{ .dict = module_dict });

    // Program: from mymod import foo; return foo
    const code = CodeObject{
        .bytecode = &[_]u8{
            @intFromEnum(Opcode.LOAD_NONE),       // 0: Push None (fromlist)
            @intFromEnum(Opcode.LOAD_ZERO),       // 1: Push 0 (level)
            @intFromEnum(Opcode.IMPORT_NAME), 0,  // 2-3: Import "mymod"
            @intFromEnum(Opcode.IMPORT_FROM), 1,  // 4-5: Import "foo" from module
            @intFromEnum(Opcode.STORE_FAST_0),    // 6: Store foo
            @intFromEnum(Opcode.POP),             // 7: Pop module
            @intFromEnum(Opcode.LOAD_FAST_0),     // 8: Load foo
            @intFromEnum(Opcode.RETURN),          // 9
        },
        .constants = &.{},
        .varnames = &[_][]const u8{"foo"},
        .freevars = &.{},
        .cellvars = &.{},
        .names = &[_][]const u8{ "mymod", "foo" },
        .nlocals = 1,
        .stacksize = 3,
    };

    var vm = VM.init(allocator, &globals);
    defer vm.deinit();

    const result = try vm.execute(&code);
    try testing.expectEqual(@as(i64, 42), result.int);
}

test "vm yield_value simple" {
    const testing = std.testing;
    const allocator = testing.allocator;

    var globals: PyValue.Dict = .{};
    defer globals.deinit(allocator);

    // Program: yield 123 (simplified - just returns the value)
    const code = CodeObject{
        .bytecode = &[_]u8{
            @intFromEnum(Opcode.LOAD_CONST), 0, // Push 123
            @intFromEnum(Opcode.YIELD_VALUE),   // Yield (returns immediately)
        },
        .constants = &[_]PyValue{.{ .int = 123 }},
        .varnames = &.{},
        .freevars = &.{},
        .cellvars = &.{},
        .names = &.{},
        .nlocals = 0,
        .stacksize = 1,
    };

    var vm = VM.init(allocator, &globals);
    defer vm.deinit();

    const result = try vm.execute(&code);
    try testing.expectEqual(@as(i64, 123), result.int);
}

// ========================================
// Integration tests: Compiler + VM
// ========================================

test "integration: compile and execute simple int" {
    const testing = std.testing;
    const allocator = testing.allocator;
    const compiler_mod = @import("compiler.zig");

    var globals: PyValue.Dict = .{};
    defer globals.deinit(allocator);

    // Compile: return 42
    var compiler = compiler_mod.Compiler.init(allocator);
    defer compiler.deinit();
    try compiler.compileInt(42);
    try compiler.compileReturn();
    const code = try compiler.finalize();
    defer {
        allocator.free(code.bytecode);
        allocator.free(code.constants);
        allocator.free(code.varnames);
        allocator.free(code.freevars);
        allocator.free(code.cellvars);
        allocator.free(code.names);
        allocator.destroy(code);
    }

    // Execute
    var vm = VM.init(allocator, &globals);
    defer vm.deinit();
    const result = try vm.execute(code);
    try testing.expectEqual(@as(i64, 42), result.int);
}

test "integration: compile and execute arithmetic" {
    const testing = std.testing;
    const allocator = testing.allocator;
    const compiler_mod = @import("compiler.zig");

    var globals: PyValue.Dict = .{};
    defer globals.deinit(allocator);

    // Compile: return 10 + 20 * 2
    var compiler = compiler_mod.Compiler.init(allocator);
    defer compiler.deinit();
    try compiler.compileInt(10);
    try compiler.compileInt(20);
    try compiler.compileInt(2);
    try compiler.compileBinOp(.mul); // 20 * 2 = 40
    try compiler.compileBinOp(.add); // 10 + 40 = 50
    try compiler.compileReturn();
    const code = try compiler.finalize();
    defer {
        allocator.free(code.bytecode);
        allocator.free(code.constants);
        allocator.free(code.varnames);
        allocator.free(code.freevars);
        allocator.free(code.cellvars);
        allocator.free(code.names);
        allocator.destroy(code);
    }

    // Execute
    var vm = VM.init(allocator, &globals);
    defer vm.deinit();
    const result = try vm.execute(code);
    try testing.expectEqual(@as(i64, 50), result.int);
}

test "integration: compile and execute with variables" {
    const testing = std.testing;
    const allocator = testing.allocator;
    const compiler_mod = @import("compiler.zig");

    var globals: PyValue.Dict = .{};
    defer globals.deinit(allocator);

    // Compile: x = 100; y = 200; return x + y
    var compiler = compiler_mod.Compiler.init(allocator);
    defer compiler.deinit();
    try compiler.compileInt(100);
    try compiler.compileStoreLocal("x");
    try compiler.compileInt(200);
    try compiler.compileStoreLocal("y");
    try compiler.compileLoadLocal("x");
    try compiler.compileLoadLocal("y");
    try compiler.compileBinOp(.add);
    try compiler.compileReturn();
    const code = try compiler.finalize();
    defer {
        allocator.free(code.bytecode);
        allocator.free(code.constants);
        allocator.free(code.varnames);
        allocator.free(code.freevars);
        allocator.free(code.cellvars);
        allocator.free(code.names);
        allocator.destroy(code);
    }

    // Execute
    var vm = VM.init(allocator, &globals);
    defer vm.deinit();
    const result = try vm.execute(code);
    try testing.expectEqual(@as(i64, 300), result.int);
}

test "integration: compile and execute comparison" {
    const testing = std.testing;
    const allocator = testing.allocator;
    const compiler_mod = @import("compiler.zig");

    var globals: PyValue.Dict = .{};
    defer globals.deinit(allocator);

    // Compile: return 5 < 10
    var compiler = compiler_mod.Compiler.init(allocator);
    defer compiler.deinit();
    try compiler.compileInt(5);
    try compiler.compileInt(10);
    try compiler.compileCompare(.lt);
    try compiler.compileReturn();
    const code = try compiler.finalize();
    defer {
        allocator.free(code.bytecode);
        allocator.free(code.constants);
        allocator.free(code.varnames);
        allocator.free(code.freevars);
        allocator.free(code.cellvars);
        allocator.free(code.names);
        allocator.destroy(code);
    }

    // Execute
    var vm = VM.init(allocator, &globals);
    defer vm.deinit();
    const result = try vm.execute(code);
    try testing.expectEqual(true, result.bool);
}

test "integration: compile and execute conditional" {
    const testing = std.testing;
    const allocator = testing.allocator;
    const compiler_mod = @import("compiler.zig");

    var globals: PyValue.Dict = .{};
    defer globals.deinit(allocator);

    // Compile: if True: return 1 else: return 2
    var compiler = compiler_mod.Compiler.init(allocator);
    defer compiler.deinit();
    try compiler.compileTrue();
    const else_jump = try compiler.compileJumpIfFalse();
    try compiler.compileInt(1);
    try compiler.compileReturn();
    compiler.patchJumpHere(else_jump);
    try compiler.compileInt(2);
    try compiler.compileReturn();
    const code = try compiler.finalize();
    defer {
        allocator.free(code.bytecode);
        allocator.free(code.constants);
        allocator.free(code.varnames);
        allocator.free(code.freevars);
        allocator.free(code.cellvars);
        allocator.free(code.names);
        allocator.destroy(code);
    }

    // Execute
    var vm = VM.init(allocator, &globals);
    defer vm.deinit();
    const result = try vm.execute(code);
    try testing.expectEqual(@as(i64, 1), result.int);
}

test "integration: compile and execute build list" {
    const testing = std.testing;
    const allocator = testing.allocator;
    const compiler_mod = @import("compiler.zig");

    var globals: PyValue.Dict = .{};
    defer globals.deinit(allocator);

    // Compile: return [1, 2, 3]
    var compiler = compiler_mod.Compiler.init(allocator);
    defer compiler.deinit();
    try compiler.compileInt(1);
    try compiler.compileInt(2);
    try compiler.compileInt(3);
    try compiler.compileBuildList(3);
    try compiler.compileReturn();
    const code = try compiler.finalize();
    defer {
        allocator.free(code.bytecode);
        allocator.free(code.constants);
        allocator.free(code.varnames);
        allocator.free(code.freevars);
        allocator.free(code.cellvars);
        allocator.free(code.names);
        allocator.destroy(code);
    }

    // Execute
    var vm = VM.init(allocator, &globals);
    defer vm.deinit();
    const result = try vm.execute(code);
    defer {
        // Clean up the returned list
        result.list.deinit(allocator);
        allocator.destroy(result.list);
    }
    try testing.expect(result == .list);
    try testing.expectEqual(@as(usize, 3), result.list.items.len);
    try testing.expectEqual(@as(i64, 1), result.list.items[0].int);
    try testing.expectEqual(@as(i64, 2), result.list.items[1].int);
    try testing.expectEqual(@as(i64, 3), result.list.items[2].int);
}
