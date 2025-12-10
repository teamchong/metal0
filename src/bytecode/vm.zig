/// Stack-based Virtual Machine for eval()/exec()
///
/// Executes bytecode compiled from Python source.
/// Works on all targets: native, browser WASM, WasmEdge WASI.
///
/// Design principles:
/// 1. REUSE existing runtime types (PyValue) - no duplication
/// 2. Dead code elimination - only included if eval()/exec() called
/// 3. Same bytecode format for all targets
const std = @import("std");
const opcode = @import("opcode.zig");
const builtin = @import("builtin");
const hashmap_helper = @import("utils.hashmap_helper");

const OpCode = opcode.OpCode;
const Instruction = opcode.Instruction;
const Value = opcode.Value;
const Program = opcode.Program;

/// Import runtime conditionally to avoid circular deps during standalone testing
const runtime_available = !builtin.is_test;

/// Stack value type - uses runtime.PyValue when available
pub const StackValue = if (runtime_available)
    @import("runtime").PyValue
else
    // Minimal test-only type
    union(enum) {
        int: i64,
        float: f64,
        string: []const u8,
        bool: bool,
        none: void,
        list: []const @This(),
        tuple: []const @This(),
        ptr: *anyopaque,

        pub fn isTruthy(self: @This()) bool {
            return switch (self) {
                .bool => |v| v,
                .int => |v| v != 0,
                .float => |v| v != 0.0,
                .string => |v| v.len > 0,
                .none => false,
                .list => |v| v.len > 0,
                .tuple => |v| v.len > 0,
                .ptr => true,
            };
        }
    };

/// VM execution error
pub const VMError = error{
    StackOverflow,
    StackUnderflow,
    TypeError,
    NameError,
    IndexError,
    KeyError,
    ValueError,
    ZeroDivisionError,
    StopIteration,
    RuntimeError,
    NotImplemented,
    OutOfMemory,
};

/// Virtual Machine state
pub const VM = struct {
    allocator: std.mem.Allocator,
    /// Operand stack
    stack: std.ArrayList(StackValue),
    /// Call frames for function calls
    frames: std.ArrayList(Frame),
    /// Global variables
    globals: hashmap_helper.StringHashMap(StackValue),

    pub const Frame = struct {
        program: *const Program,
        ip: usize,
        locals: hashmap_helper.StringHashMap(StackValue),
    };

    pub fn init(allocator: std.mem.Allocator) VM {
        return .{
            .allocator = allocator,
            .stack = std.ArrayList(StackValue){},
            .frames = std.ArrayList(Frame){},
            .globals = hashmap_helper.StringHashMap(StackValue).init(allocator),
        };
    }

    pub fn deinit(self: *VM) void {
        self.stack.deinit(self.allocator);
        for (self.frames.items) |*frame| {
            frame.locals.deinit();
        }
        self.frames.deinit(self.allocator);
        self.globals.deinit();
    }

    /// Set globals from a PyObject dict
    /// Converts PyObject dict entries to StackValue and populates vm.globals
    pub fn setGlobals(self: *VM, globals_dict: *anyopaque) !void {
        if (runtime_available) {
            const runtime_mod = @import("runtime");
            const obj: *runtime_mod.PyObject = @ptrCast(@alignCast(globals_dict));

            if (!runtime_mod.PyDict_Check(obj)) return;

            const dict_obj: *runtime_mod.PyDictObject = @ptrCast(@alignCast(obj));
            if (dict_obj.ma_keys == null) return;

            const map: *hashmap_helper.StringHashMap(*runtime_mod.PyObject) = @ptrCast(@alignCast(dict_obj.ma_keys.?));

            // Iterate dict and convert to StackValue
            var iter = map.iterator();
            while (iter.next()) |entry| {
                const key = entry.key_ptr.*;
                const value = entry.value_ptr.*;
                const stack_val = pyObjectToStackValue(value);
                try self.globals.put(key, stack_val);
            }
        }
    }

    /// Set locals for current frame from a PyObject dict
    pub fn setLocals(self: *VM, locals_dict: *anyopaque) !void {
        if (runtime_available and self.frames.items.len > 0) {
            const runtime_mod = @import("runtime");
            const obj: *runtime_mod.PyObject = @ptrCast(@alignCast(locals_dict));

            if (!runtime_mod.PyDict_Check(obj)) return;

            const dict_obj: *runtime_mod.PyDictObject = @ptrCast(@alignCast(obj));
            if (dict_obj.ma_keys == null) return;

            const map: *hashmap_helper.StringHashMap(*runtime_mod.PyObject) = @ptrCast(@alignCast(dict_obj.ma_keys.?));

            var frame = &self.frames.items[self.frames.items.len - 1];

            var iter = map.iterator();
            while (iter.next()) |entry| {
                const key = entry.key_ptr.*;
                const value = entry.value_ptr.*;
                const stack_val = pyObjectToStackValue(value);
                try frame.locals.put(key, stack_val);
            }
        }
    }

    /// Export globals back to a PyObject dict
    /// Updates the dict with any new/modified variables from execution
    pub fn exportGlobals(self: *VM, globals_dict: *anyopaque) !void {
        if (runtime_available) {
            const runtime_mod = @import("runtime");
            const obj: *runtime_mod.PyObject = @ptrCast(@alignCast(globals_dict));

            if (!runtime_mod.PyDict_Check(obj)) return;

            var iter = self.globals.iterator();
            while (iter.next()) |entry| {
                const key = entry.key_ptr.*;
                const value = entry.value_ptr.*;
                const py_obj = try stackValueToPyObject(self.allocator, value);
                try runtime_mod.PyDict.set(obj, key, py_obj);
            }
        }
    }

    /// Export locals back to a PyObject dict
    pub fn exportLocals(self: *VM, locals_dict: *anyopaque) !void {
        if (runtime_available and self.frames.items.len > 0) {
            const runtime_mod = @import("runtime");
            const obj: *runtime_mod.PyObject = @ptrCast(@alignCast(locals_dict));

            if (!runtime_mod.PyDict_Check(obj)) return;

            const frame = &self.frames.items[self.frames.items.len - 1];

            var iter = frame.locals.iterator();
            while (iter.next()) |entry| {
                const key = entry.key_ptr.*;
                const value = entry.value_ptr.*;
                const py_obj = try stackValueToPyObject(self.allocator, value);
                try runtime_mod.PyDict.set(obj, key, py_obj);
            }
        }
    }

    /// Execute a program and return the result
    pub fn execute(self: *VM, program: *const Program) VMError!StackValue {
        try self.frames.append(self.allocator, .{
            .program = program,
            .ip = 0,
            .locals = hashmap_helper.StringHashMap(StackValue).init(self.allocator),
        });

        while (self.frames.items.len > 0) {
            const frame = &self.frames.items[self.frames.items.len - 1];
            if (frame.ip >= frame.program.instructions.len) {
                frame.locals.deinit();
                _ = self.frames.pop();
                continue;
            }

            const inst = frame.program.instructions[frame.ip];
            frame.ip += 1;

            try self.executeInstruction(inst, frame);
        }

        return if (self.stack.items.len > 0) self.stack.pop().? else .{ .none = {} };
    }

    fn executeInstruction(self: *VM, inst: Instruction, frame: *Frame) VMError!void {
        switch (inst.opcode) {
            .POP_TOP => _ = self.pop() catch {},
            .DUP_TOP => try self.push(try self.peek()),
            .NOP => {},

            // Load/Store
            .LOAD_CONST => try self.push(self.loadConstant(frame.program.constants[inst.arg])),
            .LOAD_NAME, .LOAD_GLOBAL => {
                const name = frame.program.names[inst.arg];
                const val = frame.locals.get(name) orelse self.globals.get(name) orelse return VMError.NameError;
                try self.push(val);
            },
            .STORE_NAME => {
                const name = frame.program.names[inst.arg];
                try frame.locals.put(name, try self.pop());
            },

            // Unary
            .UNARY_NEGATIVE => {
                const val = try self.pop();
                try self.push(switch (val) {
                    .int => |i| .{ .int = -i },
                    .float => |f| .{ .float = -f },
                    else => return VMError.TypeError,
                });
            },
            .UNARY_NOT => try self.push(.{ .bool = !(try self.pop()).isTruthy() }),

            // Binary
            .BINARY_ADD => try self.binaryOp(.add),
            .BINARY_SUBTRACT => try self.binaryOp(.sub),
            .BINARY_MULTIPLY => try self.binaryOp(.mul),
            .BINARY_TRUE_DIVIDE => try self.binaryOp(.div),
            .BINARY_FLOOR_DIVIDE => try self.binaryOp(.floor_div),
            .BINARY_MODULO => try self.binaryOp(.mod),
            .BINARY_POWER => try self.binaryOp(.pow),

            // Comparison
            .COMPARE_LT => try self.compareOp(.lt),
            .COMPARE_LE => try self.compareOp(.le),
            .COMPARE_EQ => try self.compareOp(.eq),
            .COMPARE_NE => try self.compareOp(.ne),
            .COMPARE_GT => try self.compareOp(.gt),
            .COMPARE_GE => try self.compareOp(.ge),

            // Control flow
            .JUMP_ABSOLUTE => frame.ip = inst.arg,
            .JUMP_FORWARD => frame.ip += inst.arg,
            .POP_JUMP_IF_FALSE => if (!(try self.pop()).isTruthy()) {
                frame.ip = inst.arg;
            },
            .POP_JUMP_IF_TRUE => if ((try self.pop()).isTruthy()) {
                frame.ip = inst.arg;
            },

            // Build
            .BUILD_TUPLE => {
                const items = try self.allocator.alloc(StackValue, inst.arg);
                var i: usize = inst.arg;
                while (i > 0) {
                    i -= 1;
                    items[i] = try self.pop();
                }
                try self.push(.{ .tuple = items });
            },
            .BUILD_LIST => {
                const items = try self.allocator.alloc(StackValue, inst.arg);
                var i: usize = inst.arg;
                while (i > 0) {
                    i -= 1;
                    items[i] = try self.pop();
                }
                try self.push(.{ .list = items });
            },

            // Subscript
            .BINARY_SUBSCR => {
                const index = try self.pop();
                const obj = try self.pop();
                try self.push(switch (obj) {
                    .list, .tuple => |items| blk: {
                        if (index != .int) return VMError.TypeError;
                        const idx: usize = if (index.int < 0)
                            @intCast(@as(i64, @intCast(items.len)) + index.int)
                        else
                            @intCast(index.int);
                        if (idx >= items.len) return VMError.IndexError;
                        break :blk items[idx];
                    },
                    .string => |s| blk: {
                        if (index != .int) return VMError.TypeError;
                        const idx: usize = if (index.int < 0)
                            @intCast(@as(i64, @intCast(s.len)) + index.int)
                        else
                            @intCast(index.int);
                        if (idx >= s.len) return VMError.IndexError;
                        break :blk .{ .string = s[idx .. idx + 1] };
                    },
                    else => return VMError.TypeError,
                });
            },

            // Function calls
            .CALL_FUNCTION => {
                const argc = inst.arg;
                const args = try self.allocator.alloc(StackValue, argc);
                defer self.allocator.free(args);
                var i: usize = argc;
                while (i > 0) {
                    i -= 1;
                    args[i] = try self.pop();
                }

                // Pop function object
                const func = try self.pop();

                // Dispatch based on function type
                const result = try self.callFunction(func, args);
                try self.push(result);
            },

            // Function calls with keyword arguments
            .CALL_FUNCTION_KW => {
                const argc = inst.arg;

                // Pop keyword name tuple
                _ = try self.pop();

                // Pop arguments (both positional and keyword values)
                const args = try self.allocator.alloc(StackValue, argc);
                defer self.allocator.free(args);
                var i: usize = argc;
                while (i > 0) {
                    i -= 1;
                    args[i] = try self.pop();
                }

                // Pop function object
                const func = try self.pop();

                // Dispatch (keyword mapping happens in compiled code)
                const result = try self.callFunction(func, args);
                try self.push(result);
            },

            .RETURN_VALUE => {
                const ret = try self.pop();
                if (self.frames.pop()) |f| {
                    var mf = f;
                    mf.locals.deinit();
                }
                try self.push(ret);
            },

            .HALT => {
                while (self.frames.pop()) |f| {
                    var mf = f;
                    mf.locals.deinit();
                }
            },

            else => return VMError.NotImplemented,
        }
    }

    fn push(self: *VM, val: StackValue) VMError!void {
        if (self.stack.items.len >= opcode.MAX_STACK_DEPTH) return VMError.StackOverflow;
        self.stack.append(self.allocator, val) catch return VMError.OutOfMemory;
    }

    fn pop(self: *VM) VMError!StackValue {
        if (self.stack.items.len == 0) return VMError.StackUnderflow;
        return self.stack.pop().?;
    }

    fn peek(self: *VM) VMError!StackValue {
        if (self.stack.items.len == 0) return VMError.StackUnderflow;
        return self.stack.items[self.stack.items.len - 1];
    }

    fn loadConstant(_: *VM, val: Value) StackValue {
        return switch (val) {
            .none => .{ .none = {} },
            .bool => |b| .{ .bool = b },
            .int => |i| .{ .int = i },
            .float => |f| .{ .float = f },
            .string => |s| .{ .string = s },
            else => .{ .none = {} },
        };
    }

    const BinaryOp = enum { add, sub, mul, div, floor_div, mod, pow };

    fn binaryOp(self: *VM, op: BinaryOp) VMError!void {
        const b = try self.pop();
        const a = try self.pop();

        try self.push(switch (a) {
            .int => |ai| switch (b) {
                .int => |bi| switch (op) {
                    .add => .{ .int = ai + bi },
                    .sub => .{ .int = ai - bi },
                    .mul => .{ .int = ai * bi },
                    .div => .{ .float = @as(f64, @floatFromInt(ai)) / @as(f64, @floatFromInt(bi)) },
                    .floor_div => if (bi == 0) return VMError.ZeroDivisionError else .{ .int = @divFloor(ai, bi) },
                    .mod => if (bi == 0) return VMError.ZeroDivisionError else .{ .int = @mod(ai, bi) },
                    .pow => .{ .int = std.math.pow(i64, ai, @intCast(bi)) },
                },
                .float => |bf| .{ .float = switch (op) {
                    .add => @as(f64, @floatFromInt(ai)) + bf,
                    .sub => @as(f64, @floatFromInt(ai)) - bf,
                    .mul => @as(f64, @floatFromInt(ai)) * bf,
                    .div => @as(f64, @floatFromInt(ai)) / bf,
                    .pow => std.math.pow(f64, @floatFromInt(ai), bf),
                    else => return VMError.TypeError,
                } },
                else => return VMError.TypeError,
            },
            .float => |af| .{ .float = switch (b) {
                .int => |bi| switch (op) {
                    .add => af + @as(f64, @floatFromInt(bi)),
                    .sub => af - @as(f64, @floatFromInt(bi)),
                    .mul => af * @as(f64, @floatFromInt(bi)),
                    .div => af / @as(f64, @floatFromInt(bi)),
                    .pow => std.math.pow(f64, af, @floatFromInt(bi)),
                    else => return VMError.TypeError,
                },
                .float => |bf| switch (op) {
                    .add => af + bf,
                    .sub => af - bf,
                    .mul => af * bf,
                    .div => af / bf,
                    .pow => std.math.pow(f64, af, bf),
                    else => return VMError.TypeError,
                },
                else => return VMError.TypeError,
            } },
            .string => |as| switch (b) {
                .string => |bs| switch (op) {
                    .add => blk: {
                        const new = try self.allocator.alloc(u8, as.len + bs.len);
                        @memcpy(new[0..as.len], as);
                        @memcpy(new[as.len..], bs);
                        break :blk .{ .string = new };
                    },
                    else => return VMError.TypeError,
                },
                else => return VMError.TypeError,
            },
            else => return VMError.TypeError,
        });
    }

    const CompareOp = enum { lt, le, eq, ne, gt, ge };

    fn compareOp(self: *VM, op: CompareOp) VMError!void {
        const b = try self.pop();
        const a = try self.pop();

        try self.push(.{ .bool = switch (a) {
            .int => |ai| switch (b) {
                .int => |bi| switch (op) {
                    .lt => ai < bi,
                    .le => ai <= bi,
                    .eq => ai == bi,
                    .ne => ai != bi,
                    .gt => ai > bi,
                    .ge => ai >= bi,
                },
                .float => |bf| switch (op) {
                    .lt => @as(f64, @floatFromInt(ai)) < bf,
                    .le => @as(f64, @floatFromInt(ai)) <= bf,
                    .eq => @as(f64, @floatFromInt(ai)) == bf,
                    .ne => @as(f64, @floatFromInt(ai)) != bf,
                    .gt => @as(f64, @floatFromInt(ai)) > bf,
                    .ge => @as(f64, @floatFromInt(ai)) >= bf,
                },
                else => op == .ne,
            },
            .float => |af| switch (b) {
                .int => |bi| switch (op) {
                    .lt => af < @as(f64, @floatFromInt(bi)),
                    .le => af <= @as(f64, @floatFromInt(bi)),
                    .eq => af == @as(f64, @floatFromInt(bi)),
                    .ne => af != @as(f64, @floatFromInt(bi)),
                    .gt => af > @as(f64, @floatFromInt(bi)),
                    .ge => af >= @as(f64, @floatFromInt(bi)),
                },
                .float => |bf| switch (op) {
                    .lt => af < bf,
                    .le => af <= bf,
                    .eq => af == bf,
                    .ne => af != bf,
                    .gt => af > bf,
                    .ge => af >= bf,
                },
                else => op == .ne,
            },
            .string => |as| switch (b) {
                .string => |bs| switch (op) {
                    .lt => std.mem.order(u8, as, bs) == .lt,
                    .le => std.mem.order(u8, as, bs) != .gt,
                    .eq => std.mem.eql(u8, as, bs),
                    .ne => !std.mem.eql(u8, as, bs),
                    .gt => std.mem.order(u8, as, bs) == .gt,
                    .ge => std.mem.order(u8, as, bs) != .lt,
                },
                else => op == .ne,
            },
            .none => switch (b) {
                .none => op == .eq,
                else => op == .ne,
            },
            else => op == .ne,
        } });
    }

    /// Call a function with the given arguments
    fn callFunction(self: *VM, func: StackValue, args: []StackValue) VMError!StackValue {
        switch (func) {
            // Code object (user-defined function) - represented as ptr
            .ptr => |ptr| {
                const code: *const Program = @ptrCast(@alignCast(ptr));

                // Create new call frame
                var frame = Frame{
                    .program = code,
                    .ip = 0,
                    .locals = hashmap_helper.StringHashMap(StackValue).init(self.allocator),
                };

                // Bind arguments to parameter names
                const bind_count = @min(args.len, code.varnames.len);
                for (0..bind_count) |i| {
                    frame.locals.put(code.varnames[i], args[i]) catch return VMError.OutOfMemory;
                }

                // Push frame and execute
                self.frames.append(self.allocator, frame) catch return VMError.OutOfMemory;

                // Execute until return
                while (self.frames.items.len > 0) {
                    const current_frame = &self.frames.items[self.frames.items.len - 1];
                    if (current_frame.ip >= current_frame.program.instructions.len) break;
                    const inst = current_frame.program.instructions[current_frame.ip];
                    current_frame.ip += 1;
                    try self.executeInstruction(inst, current_frame);
                }

                return try self.pop();
            },

            // String - check for builtin function name
            .string => |name| {
                return self.callBuiltin(name, args);
            },

            else => return VMError.TypeError,
        }
    }

    /// Call a builtin function by name
    fn callBuiltin(_: *VM, name: []const u8, args: []StackValue) VMError!StackValue {
        if (std.mem.eql(u8, name, "len")) {
            if (args.len != 1) return VMError.TypeError;
            return switch (args[0]) {
                .string => |s| .{ .int = @intCast(s.len) },
                .list => |l| .{ .int = @intCast(l.len) },
                .tuple => |t| .{ .int = @intCast(t.len) },
                else => VMError.TypeError,
            };
        }
        if (std.mem.eql(u8, name, "int")) {
            if (args.len != 1) return VMError.TypeError;
            return switch (args[0]) {
                .int => args[0],
                .float => |f| .{ .int = @intFromFloat(f) },
                .bool => |b| .{ .int = if (b) 1 else 0 },
                else => VMError.TypeError,
            };
        }
        if (std.mem.eql(u8, name, "float")) {
            if (args.len != 1) return VMError.TypeError;
            return switch (args[0]) {
                .float => args[0],
                .int => |i| .{ .float = @floatFromInt(i) },
                .bool => |b| .{ .float = if (b) 1.0 else 0.0 },
                else => VMError.TypeError,
            };
        }
        if (std.mem.eql(u8, name, "bool")) {
            if (args.len != 1) return VMError.TypeError;
            return .{ .bool = args[0].isTruthy() };
        }
        if (std.mem.eql(u8, name, "abs")) {
            if (args.len != 1) return VMError.TypeError;
            return switch (args[0]) {
                .int => |i| .{ .int = if (i < 0) -i else i },
                .float => |f| .{ .float = @abs(f) },
                else => VMError.TypeError,
            };
        }
        if (std.mem.eql(u8, name, "print")) {
            return .{ .none = {} };
        }
        if (std.mem.eql(u8, name, "type")) {
            if (args.len != 1) return VMError.TypeError;
            return switch (args[0]) {
                .int => .{ .string = "<class 'int'>" },
                .float => .{ .string = "<class 'float'>" },
                .string => .{ .string = "<class 'str'>" },
                .bool => .{ .string = "<class 'bool'>" },
                .none => .{ .string = "<class 'NoneType'>" },
                else => .{ .string = "<class 'object'>" },
            };
        }
        return VMError.NameError;
    }
};

/// Convert PyObject to StackValue
fn pyObjectToStackValue(obj: anytype) StackValue {
    if (runtime_available) {
        const runtime_mod = @import("runtime");
        const py_obj: *runtime_mod.PyObject = @ptrCast(@alignCast(obj));

        // Check type and convert
        if (runtime_mod.PyLong_Check(py_obj)) {
            const long_obj: *runtime_mod.PyLongObject = @ptrCast(@alignCast(py_obj));
            return .{ .int = @intCast(long_obj.ob_digit) };
        }
        if (runtime_mod.PyFloat_Check(py_obj)) {
            const float_obj: *runtime_mod.PyFloatObject = @ptrCast(@alignCast(py_obj));
            return .{ .float = float_obj.ob_fval };
        }
        if (runtime_mod.PyBool_Check(py_obj)) {
            const bool_obj: *runtime_mod.PyBoolObject = @ptrCast(@alignCast(py_obj));
            return .{ .bool = bool_obj.ob_digit != 0 };
        }
        if (runtime_mod.PyUnicode_Check(py_obj)) {
            const str_obj: *runtime_mod.PyUnicodeObject = @ptrCast(@alignCast(py_obj));
            const len: usize = @intCast(str_obj.length);
            return .{ .string = str_obj.data[0..len] };
        }
        if (runtime_mod.Py_IsNone(py_obj)) {
            return .{ .none = {} };
        }
        // For lists and other types, store as pointer
        return .{ .ptr = @ptrCast(py_obj) };
    }
    return .{ .none = {} };
}

/// Convert StackValue to PyObject
fn stackValueToPyObject(allocator: std.mem.Allocator, val: StackValue) !*anyopaque {
    if (runtime_available) {
        const runtime_mod = @import("runtime");

        return switch (val) {
            .int => |i| @ptrCast(try runtime_mod.PyInt.create(allocator, i)),
            .float => |f| @ptrCast(try runtime_mod.PyFloat.create(allocator, f)),
            .bool => |b| @ptrCast(try runtime_mod.PyBool.create(allocator, b)),
            .string => |s| @ptrCast(try runtime_mod.PyString.create(allocator, s)),
            .none => @ptrCast(runtime_mod.Py_None()),
            .list => |items| blk: {
                const list = try runtime_mod.PyList.create(allocator);
                for (items) |item| {
                    const py_item: *runtime_mod.PyObject = @ptrCast(@alignCast(try stackValueToPyObject(allocator, item)));
                    try runtime_mod.PyList.append(list, py_item);
                }
                break :blk @ptrCast(list);
            },
            .tuple => |items| blk: {
                const tuple = try runtime_mod.PyTuple.create(allocator, items.len);
                for (items, 0..) |item, i| {
                    const py_item: *runtime_mod.PyObject = @ptrCast(@alignCast(try stackValueToPyObject(allocator, item)));
                    runtime_mod.PyTuple.setItem(tuple, i, py_item);
                }
                break :blk @ptrCast(tuple);
            },
            .ptr => |p| p,
        };
    }
    return @ptrFromInt(0);
}

test "vm basic operations" {
    const allocator = std.testing.allocator;

    var vm = VM.init(allocator);
    defer vm.deinit();

    // Test: 1 + 2 = 3
    const instructions = [_]Instruction{
        Instruction.init(.LOAD_CONST, 0),
        Instruction.init(.LOAD_CONST, 1),
        Instruction.init(.BINARY_ADD, 0),
        Instruction.init(.RETURN_VALUE, 0),
    };

    const constants = [_]Value{ .{ .int = 1 }, .{ .int = 2 } };

    const program = Program{
        .instructions = &instructions,
        .constants = &constants,
        .varnames = &.{},
        .names = &.{},
        .cellvars = &.{},
        .freevars = &.{},
        .source_map = &.{},
        .filename = "<test>",
        .name = "<expr>",
        .firstlineno = 1,
        .argcount = 0,
        .posonlyargcount = 0,
        .kwonlyargcount = 0,
        .stacksize = 256,
        .flags = .{},
    };

    const result = try vm.execute(&program);
    try std.testing.expectEqual(@as(i64, 3), result.int);
}

test "vm comparison" {
    const allocator = std.testing.allocator;

    var vm = VM.init(allocator);
    defer vm.deinit();

    // Test: 5 > 3 = true
    const instructions = [_]Instruction{
        Instruction.init(.LOAD_CONST, 0),
        Instruction.init(.LOAD_CONST, 1),
        Instruction.init(.COMPARE_GT, 0),
        Instruction.init(.RETURN_VALUE, 0),
    };

    const constants = [_]Value{ .{ .int = 5 }, .{ .int = 3 } };

    const program = Program{
        .instructions = &instructions,
        .constants = &constants,
        .varnames = &.{},
        .names = &.{},
        .cellvars = &.{},
        .freevars = &.{},
        .source_map = &.{},
        .filename = "<test>",
        .name = "<expr>",
        .firstlineno = 1,
        .argcount = 0,
        .posonlyargcount = 0,
        .kwonlyargcount = 0,
        .stacksize = 256,
        .flags = .{},
    };

    const result = try vm.execute(&program);
    try std.testing.expectEqual(true, result.bool);
}
