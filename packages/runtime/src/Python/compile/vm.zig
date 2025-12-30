/// Bytecode VM executor with stack-based operations
const std = @import("std");
const runtime = @import("../../runtime.zig");
const PyObject = runtime.PyObject;
const PyInt = @import("../../Objects/intobject.zig").PyInt;
const PyFloat = @import("../../Objects/floatobject.zig").PyFloat;
const PyComplex = @import("../../Objects/complexobject.zig").PyComplex;
const PyBool = @import("../../Objects/boolobject.zig").PyBool;
const PyString = @import("../../Objects/stringlib/core.zig").PyString;
const BigInt = @import("bigint").BigInt;
const constants = @import("constants.zig");
const program = @import("program.zig");
const helpers = @import("helpers.zig");
const OpCode = constants.OpCode;
const BytecodeProgram = program.BytecodeProgram;
const PyBigInt = helpers.PyBigInt;
const createPyBytes = helpers.createPyBytes;

/// PyDict operations for scope lookups
const PyDict = @import("../../Objects/dictobject.zig").PyDict;

/// PyBuiltinFunction for callable builtins
const builtinfunc = @import("../../Objects/builtinfunc.zig");
const PyBuiltinFunction = builtinfunc.PyBuiltinFunction;
const PyBuiltinFunction_Check = builtinfunc.PyBuiltinFunction_Check;

/// Bytecode VM executor
pub const VM = struct {
    stack: std.ArrayList(*PyObject),
    allocator: std.mem.Allocator,
    globals: ?*PyObject, // Global scope dict (optional)
    locals: ?*PyObject, // Local scope dict (optional)
    builtins: ?*PyObject, // Builtins scope dict (optional)

    pub fn init(allocator: std.mem.Allocator) VM {
        return .{
            .stack = .{},
            .allocator = allocator,
            .globals = null,
            .locals = null,
            .builtins = null,
        };
    }

    /// Initialize VM with globals and locals scope dicts
    pub fn initWithScope(allocator: std.mem.Allocator, globals: ?*PyObject, locals: ?*PyObject) VM {
        return .{
            .stack = .{},
            .allocator = allocator,
            .globals = globals,
            .locals = locals,
            .builtins = null,
        };
    }

    /// Initialize VM with full scope: globals, locals, and builtins
    pub fn initWithFullScope(allocator: std.mem.Allocator, globals: ?*PyObject, locals: ?*PyObject, builtins: ?*PyObject) VM {
        return .{
            .stack = .{},
            .allocator = allocator,
            .globals = globals,
            .locals = locals,
            .builtins = builtins,
        };
    }

    pub fn deinit(self: *VM) void {
        self.stack.deinit(self.allocator);
    }

    /// Look up a name in scope: locals -> globals -> builtins -> NameError
    fn lookupName(self: *VM, name: []const u8) !*PyObject {
        // Try locals first
        if (self.locals) |locals_dict| {
            if (PyDict.getItemString(locals_dict, name)) |value| {
                return value;
            }
        }

        // Then try globals
        if (self.globals) |globals_dict| {
            if (PyDict.getItemString(globals_dict, name)) |value| {
                return value;
            }
        }

        // Then try builtins
        if (self.builtins) |builtins_dict| {
            if (PyDict.getItemString(builtins_dict, name)) |value| {
                return value;
            }
        }

        // Name not found - NameError
        return error.NameError;
    }

    /// Look up a name in globals only
    fn lookupGlobal(self: *VM, name: []const u8) !*PyObject {
        if (self.globals) |globals_dict| {
            if (PyDict.getItemString(globals_dict, name)) |value| {
                return value;
            }
        }
        return error.NameError;
    }

    /// Look up a name in locals only
    fn lookupLocal(self: *VM, name: []const u8) !*PyObject {
        if (self.locals) |locals_dict| {
            if (PyDict.getItemString(locals_dict, name)) |value| {
                return value;
            }
        }
        return error.NameError;
    }

    /// Execute bytecode program
    pub fn execute(self: *VM, prog: *const BytecodeProgram) !*PyObject {
        var ip: usize = 0;

        while (ip < prog.instructions.len) {
            const inst = prog.instructions[ip];

            switch (inst.op) {
                .LoadConst => {
                    const constant = prog.constants[inst.arg];
                    const obj: *PyObject = switch (constant) {
                        .int => |i| try PyInt.create(self.allocator, i),
                        .float => |f| try PyFloat.create(self.allocator, f),
                        .complex => |c| try PyComplex.create(self.allocator, 0.0, c),
                        .string => |s| try PyString.create(self.allocator, s),
                        .bytes => |b| try createPyBytes(self.allocator, b),
                        .bool => |b| try PyBool.create(self.allocator, b),
                        .bigint => |s| try PyBigInt.create(self.allocator, s),
                        .none => @import("../../cpython.zig").Py_None,
                    };
                    try self.stack.append(self.allocator, obj);
                },

                .Add => try self.binaryOp(.Add),
                .Sub => try self.binaryOp(.Sub),
                .Mult => try self.binaryOp(.Mult),
                .Div => try self.binaryOp(.Div),
                .FloorDiv => try self.binaryOp(.FloorDiv),
                .Mod => try self.binaryOp(.Mod),
                .Pow => try self.binaryOp(.Pow),

                .Invert => try self.unaryInvert(),
                .UAdd => try self.unaryAdd(),
                .USub => try self.unarySub(),
                .Not => try self.unaryNot(),

                .Eq => try self.compareOp(.Eq),
                .NotEq => try self.compareOp(.NotEq),
                .Lt => try self.compareOp(.Lt),
                .Gt => try self.compareOp(.Gt),
                .LtE => try self.compareOp(.LtE),
                .GtE => try self.compareOp(.GtE),

                .Return => {
                    if (self.stack.items.len == 0) return error.EmptyStack;
                    return self.stack.pop() orelse return error.EmptyStack;
                },

                .BuildList => {
                    const count = inst.arg;
                    const listobject = @import("../../Objects/listobject.zig");

                    // Create empty list
                    const list = try listobject.PyList.create(self.allocator);

                    // Append items from stack (first pushed = first element)
                    if (count > 0) {
                        const start_idx = self.stack.items.len - count;
                        var i: usize = 0;
                        while (i < count) : (i += 1) {
                            const item = self.stack.items[start_idx + i];
                            try listobject.PyList.append(list, item);
                        }
                        // Remove items from stack
                        self.stack.items.len = start_idx;
                    }

                    try self.stack.append(self.allocator, list);
                },

                .LoadName => {
                    // Load variable: tries locals -> globals
                    const name_idx = inst.arg;
                    if (name_idx >= prog.names.len) return error.InvalidNameIndex;
                    const name = prog.names[name_idx];
                    const value = try self.lookupName(name);
                    try self.stack.append(self.allocator, value);
                },

                .LoadGlobal => {
                    // Load from globals dict only
                    const name_idx = inst.arg;
                    if (name_idx >= prog.names.len) return error.InvalidNameIndex;
                    const name = prog.names[name_idx];
                    const value = try self.lookupGlobal(name);
                    try self.stack.append(self.allocator, value);
                },

                .LoadLocal => {
                    // Load from locals dict only
                    const name_idx = inst.arg;
                    if (name_idx >= prog.names.len) return error.InvalidNameIndex;
                    const name = prog.names[name_idx];
                    const value = try self.lookupLocal(name);
                    try self.stack.append(self.allocator, value);
                },

                .StoreName => {
                    // Store to current scope (locals if available, else globals)
                    const name_idx = inst.arg;
                    if (name_idx >= prog.names.len) return error.InvalidNameIndex;
                    const name = prog.names[name_idx];
                    const value = self.stack.pop() orelse return error.StackUnderflow;
                    const target = self.locals orelse self.globals orelse return error.NoScope;
                    try PyDict.setItemString(target, name, value);
                },

                .StoreGlobal => {
                    // Store to globals
                    const name_idx = inst.arg;
                    if (name_idx >= prog.names.len) return error.InvalidNameIndex;
                    const name = prog.names[name_idx];
                    const value = self.stack.pop() orelse return error.StackUnderflow;
                    const globals_dict = self.globals orelse return error.NoScope;
                    try PyDict.setItemString(globals_dict, name, value);
                },

                .StoreLocal => {
                    // Store to locals
                    const name_idx = inst.arg;
                    if (name_idx >= prog.names.len) return error.InvalidNameIndex;
                    const name = prog.names[name_idx];
                    const value = self.stack.pop() orelse return error.StackUnderflow;
                    const locals_dict = self.locals orelse return error.NoScope;
                    try PyDict.setItemString(locals_dict, name, value);
                },

                .Pop => {
                    // Discard top of stack
                    _ = self.stack.pop() orelse return error.StackUnderflow;
                },

                .Call => {
                    // Call a callable with arg_count arguments
                    const arg_count = inst.arg;

                    // Need at least arg_count + 1 items (args + callable)
                    if (self.stack.items.len < arg_count + 1) return error.StackUnderflow;

                    // Pop args from stack (in reverse order, so last arg is on top)
                    var args = try self.allocator.alloc(*PyObject, arg_count);
                    defer self.allocator.free(args);

                    var i: usize = arg_count;
                    while (i > 0) {
                        i -= 1;
                        args[i] = self.stack.pop() orelse return error.StackUnderflow;
                    }

                    // Pop callable
                    const callable = self.stack.pop() orelse return error.StackUnderflow;

                    // Check if it's a PyBuiltinFunction
                    if (PyBuiltinFunction_Check(callable)) {
                        const result = try PyBuiltinFunction.call(callable, self.allocator, args);
                        try self.stack.append(self.allocator, result);
                    } else {
                        // Not a callable we recognize
                        return error.TypeError;
                    }
                },
            }

            ip += 1;
        }

        return error.NoReturnValue;
    }

    fn binaryOp(self: *VM, op: OpCode) !void {
        if (self.stack.items.len < 2) return error.StackUnderflow;

        const right = self.stack.pop() orelse return error.StackUnderflow;
        const left = self.stack.pop() orelse return error.StackUnderflow;

        // Check operand types
        const left_is_float = runtime.PyFloat_Check(left);
        const right_is_float = runtime.PyFloat_Check(right);
        const left_is_bigint = runtime.PyBigInt_Check(left);
        const right_is_bigint = runtime.PyBigInt_Check(right);

        if (left_is_float or right_is_float) {
            // Float arithmetic
            const left_val: f64 = if (left_is_float) PyFloat.getValue(left) else if (left_is_bigint) PyBigInt.getValue(left).toFloat() else @floatFromInt(PyInt.getValue(left));
            const right_val: f64 = if (right_is_float) PyFloat.getValue(right) else if (right_is_bigint) PyBigInt.getValue(right).toFloat() else @floatFromInt(PyInt.getValue(right));

            const result_val: f64 = switch (op) {
                .Add => left_val + right_val,
                .Sub => left_val - right_val,
                .Mult => left_val * right_val,
                .Div => left_val / right_val,
                .FloorDiv => @floor(left_val / right_val),
                .Mod => @mod(left_val, right_val),
                .Pow => std.math.pow(f64, left_val, right_val),
                else => return error.UnsupportedOp,
            };

            const result = try PyFloat.create(self.allocator, result_val);
            try self.stack.append(self.allocator, result);
        } else if (left_is_bigint or right_is_bigint) {
            // BigInt arithmetic - promote int to bigint if needed
            var left_big: BigInt = undefined;
            var right_big: BigInt = undefined;
            var left_needs_free = false;
            var right_needs_free = false;

            if (left_is_bigint) {
                left_big = try PyBigInt.getValue(left).clone(self.allocator);
            } else {
                left_big = try BigInt.fromInt(self.allocator, PyInt.getValue(left));
                left_needs_free = true;
            }
            errdefer if (left_needs_free) left_big.deinit();

            if (right_is_bigint) {
                right_big = try PyBigInt.getValue(right).clone(self.allocator);
            } else {
                right_big = try BigInt.fromInt(self.allocator, PyInt.getValue(right));
                right_needs_free = true;
            }
            errdefer if (right_needs_free) right_big.deinit();

            const result_big: BigInt = switch (op) {
                .Add => try left_big.add(&right_big, self.allocator),
                .Sub => try left_big.sub(&right_big, self.allocator),
                .Mult => try left_big.mul(&right_big, self.allocator),
                .FloorDiv => try left_big.floorDiv(&right_big, self.allocator),
                .Mod => try left_big.mod(&right_big, self.allocator),
                .Pow => blk: {
                    // For pow, exponent must fit in u32
                    const exp = right_big.toInt(i64) catch return error.UnsupportedOp;
                    if (exp < 0) return error.UnsupportedOp;
                    break :blk try left_big.pow(@intCast(exp), self.allocator);
                },
                .Div => {
                    // True division returns float
                    const left_f = left_big.toFloat();
                    const right_f = right_big.toFloat();
                    if (left_needs_free) left_big.deinit();
                    if (right_needs_free) right_big.deinit();
                    const result = try PyFloat.create(self.allocator, left_f / right_f);
                    try self.stack.append(self.allocator, result);
                    return;
                },
                else => return error.UnsupportedOp,
            };

            // Free temporaries
            if (left_needs_free) left_big.deinit();
            if (right_needs_free) right_big.deinit();

            const result = try PyBigInt.createFromBigInt(self.allocator, result_big);
            try self.stack.append(self.allocator, result);
        } else {
            // Integer arithmetic
            const left_val = PyInt.getValue(left);
            const right_val = PyInt.getValue(right);

            // True division (/) returns float in Python 3
            if (op == .Div) {
                const result_float = @as(f64, @floatFromInt(left_val)) / @as(f64, @floatFromInt(right_val));
                const result = try PyFloat.create(self.allocator, result_float);
                try self.stack.append(self.allocator, result);
                return;
            }

            const result_val: i64 = switch (op) {
                .Add => left_val + right_val,
                .Sub => left_val - right_val,
                .Mult => left_val * right_val,
                .FloorDiv => @divFloor(left_val, right_val),
                .Mod => @mod(left_val, right_val),
                .Pow => std.math.pow(i64, left_val, @intCast(right_val)),
                else => return error.UnsupportedOp,
            };

            const result = try PyInt.create(self.allocator, result_val);
            try self.stack.append(self.allocator, result);
        }
    }

    fn compareOp(self: *VM, op: OpCode) !void {
        if (self.stack.items.len < 2) return error.StackUnderflow;

        const right = self.stack.pop() orelse return error.StackUnderflow;
        const left = self.stack.pop() orelse return error.StackUnderflow;

        // Check if either operand is a float
        const left_is_float = runtime.PyFloat_Check(left);
        const right_is_float = runtime.PyFloat_Check(right);

        const left_val: f64 = if (left_is_float) PyFloat.getValue(left) else @floatFromInt(PyInt.getValue(left));
        const right_val: f64 = if (right_is_float) PyFloat.getValue(right) else @floatFromInt(PyInt.getValue(right));

        const result_val: bool = switch (op) {
            .Eq => left_val == right_val,
            .NotEq => left_val != right_val,
            .Lt => left_val < right_val,
            .Gt => left_val > right_val,
            .LtE => left_val <= right_val,
            .GtE => left_val >= right_val,
            else => return error.UnsupportedOp,
        };

        const result = try PyBool.create(self.allocator, result_val);
        try self.stack.append(self.allocator, result);
    }

    fn unaryInvert(self: *VM) !void {
        if (self.stack.items.len < 1) return error.StackUnderflow;

        const val = self.stack.pop() orelse return error.StackUnderflow;

        // Float, complex, string, bytes cannot be inverted - raise TypeError
        if (runtime.PyFloat_Check(val) or
            runtime.PyComplex_Check(val) or
            runtime.PyUnicode_Check(val) or
            runtime.PyBytes_Check(val))
        {
            return error.TypeError;
        }

        if (runtime.PyBigInt_Check(val)) {
            // BigInt invert: ~x = -(x+1)
            const big_val = PyBigInt.getValue(val);
            var one = try BigInt.fromInt(self.allocator, 1);
            defer one.deinit();
            var plus_one = try big_val.add(&one, self.allocator);
            defer plus_one.deinit();
            const result_big = try plus_one.neg(self.allocator);
            const result = try PyBigInt.createFromBigInt(self.allocator, result_big);
            try self.stack.append(self.allocator, result);
        } else if (runtime.PyBool_Check(val)) {
            // Bool first (before int check since bool is a subclass of int)
            const int_val: i64 = if (PyBool.getValue(val)) 1 else 0;
            const result_val = ~int_val;
            const result = try PyInt.create(self.allocator, result_val);
            try self.stack.append(self.allocator, result);
        } else if (runtime.PyLong_Check(val)) {
            const int_val = PyInt.getValue(val);
            const result_val = ~int_val;
            const result = try PyInt.create(self.allocator, result_val);
            try self.stack.append(self.allocator, result);
        } else {
            // Unknown type - raise TypeError
            return error.TypeError;
        }
    }

    fn unaryAdd(self: *VM) !void {
        if (self.stack.items.len < 1) return error.StackUnderflow;

        const val = self.stack.items[self.stack.items.len - 1];

        // Unary + only works on numbers - raise TypeError for strings/bytes
        if (runtime.PyUnicode_Check(val) or runtime.PyBytes_Check(val)) {
            return error.TypeError;
        }

        // For numbers, +x is just x - leave on stack
        // (int, float, bool, bigint all just pass through)
    }

    fn unarySub(self: *VM) !void {
        if (self.stack.items.len < 1) return error.StackUnderflow;

        const val = self.stack.pop() orelse return error.StackUnderflow;

        // Unary - raises TypeError for strings/bytes
        if (runtime.PyUnicode_Check(val) or runtime.PyBytes_Check(val)) {
            return error.TypeError;
        }

        if (runtime.PyFloat_Check(val)) {
            const float_val = PyFloat.getValue(val);
            const result = try PyFloat.create(self.allocator, -float_val);
            try self.stack.append(self.allocator, result);
        } else if (runtime.PyBigInt_Check(val)) {
            const big_val = PyBigInt.getValue(val);
            const result_big = try big_val.neg(self.allocator);
            const result = try PyBigInt.createFromBigInt(self.allocator, result_big);
            try self.stack.append(self.allocator, result);
        } else if (runtime.PyBool_Check(val)) {
            const int_val: i64 = if (PyBool.getValue(val)) 1 else 0;
            const result = try PyInt.create(self.allocator, -int_val);
            try self.stack.append(self.allocator, result);
        } else if (runtime.PyLong_Check(val)) {
            const int_val = PyInt.getValue(val);
            const result = try PyInt.create(self.allocator, -int_val);
            try self.stack.append(self.allocator, result);
        } else {
            return error.TypeError;
        }
    }

    /// Boolean NOT: not x
    fn unaryNot(self: *VM) !void {
        if (self.stack.items.len < 1) return error.StackUnderflow;

        const val = self.stack.pop() orelse return error.StackUnderflow;

        // Get truth value and negate
        const is_truthy = blk: {
            if (runtime.PyBool_Check(val)) {
                break :blk PyBool.getValue(val);
            } else if (runtime.PyLong_Check(val)) {
                break :blk PyInt.getValue(val) != 0;
            } else if (runtime.PyFloat_Check(val)) {
                break :blk PyFloat.getValue(val) != 0.0;
            } else if (runtime.PyUnicode_Check(val)) {
                const str = PyString.getValue(val);
                break :blk str.len > 0;
            } else if (runtime.PyBytes_Check(val)) {
                // Access ob_size from PyBytesObject
                const bytes_obj: *runtime.PyBytesObject = @ptrCast(@alignCast(val));
                break :blk bytes_obj.ob_base.ob_size > 0;
            } else if (val == runtime.Py_None) {
                break :blk false;
            } else if (runtime.PyList_Check(val)) {
                // Access ob_size from PyListObject
                const list_obj: *runtime.cpython.PyListObject = @ptrCast(@alignCast(val));
                break :blk list_obj.ob_base.ob_size > 0;
            } else if (runtime.PyTuple_Check(val)) {
                // Access ob_size from PyTupleObject
                const tuple_obj: *runtime.cpython.PyTupleObject = @ptrCast(@alignCast(val));
                break :blk tuple_obj.ob_base.ob_size > 0;
            } else if (runtime.PyBigInt_Check(val)) {
                const big = PyBigInt.getValue(val);
                break :blk !big.isZero();
            } else {
                // Other objects are truthy by default
                break :blk true;
            }
        };

        // Push the negated boolean
        const result = try PyBool.create(self.allocator, !is_truthy);
        try self.stack.append(self.allocator, result);
    }
};
