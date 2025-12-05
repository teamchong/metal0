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
    globals: std.StringHashMap(StackValue),

    pub const Frame = struct {
        program: *const Program,
        ip: usize,
        locals: std.StringHashMap(StackValue),
    };

    pub fn init(allocator: std.mem.Allocator) VM {
        return .{
            .allocator = allocator,
            .stack = std.ArrayList(StackValue){},
            .frames = std.ArrayList(Frame){},
            .globals = std.StringHashMap(StackValue).init(allocator),
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

    /// Execute a program and return the result
    pub fn execute(self: *VM, program: *const Program) VMError!StackValue {
        try self.frames.append(self.allocator, .{
            .program = program,
            .ip = 0,
            .locals = std.StringHashMap(StackValue).init(self.allocator),
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
                _ = try self.pop(); // function - TODO: call it
                try self.push(.{ .none = {} }); // placeholder return
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
};

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
