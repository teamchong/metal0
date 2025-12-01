/// Bytecode representation for cached eval/exec
/// Compact instruction set for dynamic execution
const std = @import("std");
const ast_executor = @import("ast_executor.zig");
const runtime = @import("runtime.zig");
const PyObject = runtime.PyObject;
const PyInt = @import("pyint.zig").PyInt;
const PyFloat = @import("pyfloat.zig").PyFloat;
const PyBool = @import("pybool.zig").PyBool;
const BigInt = @import("bigint").BigInt;

/// Bytecode instruction opcodes
pub const OpCode = enum(u8) {
    // Stack operations
    LoadConst, // Push constant to stack
    Pop, // Pop from stack

    // Arithmetic
    Add, // Pop 2, push result
    Sub,
    Mult,
    Div,
    FloorDiv,
    Mod,
    Pow,

    // Unary operations
    Invert, // Bitwise NOT ~

    // Comparisons
    Eq,
    NotEq,
    Lt,
    Gt,
    LtE,
    GtE,

    // Control
    Return, // Return top of stack
    Call, // Call builtin function
};

/// Bytecode instruction
pub const Instruction = struct {
    op: OpCode,
    arg: u32 = 0, // Argument (constant index, etc.)
};

/// Constant pool value
pub const Constant = union(enum) {
    int: i64,
    float: f64,
    string: []const u8,
    bool: bool,
    bigint: []const u8, // BigInt stored as decimal string for serialization
};

/// Compiled bytecode program
pub const BytecodeProgram = struct {
    instructions: []Instruction,
    constants: []Constant,
    allocator: std.mem.Allocator,

    pub fn deinit(self: *BytecodeProgram) void {
        self.allocator.free(self.instructions);
        self.allocator.free(self.constants);
    }

    /// Serialize bytecode to binary format for subprocess IPC
    /// Format: [magic][version][num_constants][constants...][num_instructions][instructions...]
    pub fn serialize(self: *const BytecodeProgram, allocator: std.mem.Allocator) ![]u8 {
        var buffer = std.ArrayList(u8).init(allocator);
        errdefer buffer.deinit();

        // Magic: "PYBC" (4 bytes)
        try buffer.appendSlice("PYBC");

        // Version: 1 (4 bytes, little endian)
        try buffer.appendSlice(&std.mem.toBytes(@as(u32, 1)));

        // Number of constants (4 bytes)
        try buffer.appendSlice(&std.mem.toBytes(@as(u32, @intCast(self.constants.len))));

        // Constants
        for (self.constants) |constant| {
            switch (constant) {
                .int => |i| {
                    try buffer.append(0); // type tag: int
                    try buffer.appendSlice(&std.mem.toBytes(i));
                },
                .float => |f| {
                    try buffer.append(2); // type tag: float
                    try buffer.appendSlice(&std.mem.toBytes(f));
                },
                .string => |s| {
                    try buffer.append(1); // type tag: string
                    try buffer.appendSlice(&std.mem.toBytes(@as(u32, @intCast(s.len))));
                    try buffer.appendSlice(s);
                },
                .bool => |b| {
                    try buffer.append(3); // type tag: bool
                    try buffer.append(if (b) 1 else 0);
                },
                .bigint => |s| {
                    try buffer.append(4); // type tag: bigint (stored as string)
                    try buffer.appendSlice(&std.mem.toBytes(@as(u32, @intCast(s.len))));
                    try buffer.appendSlice(s);
                },
            }
        }

        // Number of instructions (4 bytes)
        try buffer.appendSlice(&std.mem.toBytes(@as(u32, @intCast(self.instructions.len))));

        // Instructions (5 bytes each: 1 opcode + 4 arg)
        for (self.instructions) |inst| {
            try buffer.append(@intFromEnum(inst.op));
            try buffer.appendSlice(&std.mem.toBytes(inst.arg));
        }

        return buffer.toOwnedSlice();
    }

    /// Deserialize bytecode from binary format (subprocess output)
    pub fn deserialize(allocator: std.mem.Allocator, data: []const u8) !BytecodeProgram {
        if (data.len < 12) return error.InvalidBytecode; // magic + version + num_constants

        var pos: usize = 0;

        // Check magic
        if (!std.mem.eql(u8, data[0..4], "PYBC")) return error.InvalidMagic;
        pos += 4;

        // Check version
        const version = std.mem.readInt(u32, data[pos..][0..4], .little);
        if (version != 1) return error.UnsupportedVersion;
        pos += 4;

        // Read constants
        const num_constants = std.mem.readInt(u32, data[pos..][0..4], .little);
        pos += 4;

        var constants = try allocator.alloc(Constant, num_constants);
        errdefer allocator.free(constants);

        for (0..num_constants) |i| {
            if (pos >= data.len) return error.UnexpectedEof;
            const type_tag = data[pos];
            pos += 1;

            switch (type_tag) {
                0 => { // int
                    if (pos + 8 > data.len) return error.UnexpectedEof;
                    constants[i] = .{ .int = std.mem.readInt(i64, data[pos..][0..8], .little) };
                    pos += 8;
                },
                1 => { // string
                    if (pos + 4 > data.len) return error.UnexpectedEof;
                    const str_len = std.mem.readInt(u32, data[pos..][0..4], .little);
                    pos += 4;
                    if (pos + str_len > data.len) return error.UnexpectedEof;
                    constants[i] = .{ .string = try allocator.dupe(u8, data[pos..][0..str_len]) };
                    pos += str_len;
                },
                2 => { // float
                    if (pos + 8 > data.len) return error.UnexpectedEof;
                    constants[i] = .{ .float = @bitCast(std.mem.readInt(u64, data[pos..][0..8], .little)) };
                    pos += 8;
                },
                3 => { // bool
                    if (pos + 1 > data.len) return error.UnexpectedEof;
                    constants[i] = .{ .bool = data[pos] != 0 };
                    pos += 1;
                },
                4 => { // bigint (stored as string)
                    if (pos + 4 > data.len) return error.UnexpectedEof;
                    const str_len = std.mem.readInt(u32, data[pos..][0..4], .little);
                    pos += 4;
                    if (pos + str_len > data.len) return error.UnexpectedEof;
                    constants[i] = .{ .bigint = try allocator.dupe(u8, data[pos..][0..str_len]) };
                    pos += str_len;
                },
                else => return error.InvalidConstantType,
            }
        }

        // Read instructions
        if (pos + 4 > data.len) return error.UnexpectedEof;
        const num_instructions = std.mem.readInt(u32, data[pos..][0..4], .little);
        pos += 4;

        var instructions = try allocator.alloc(Instruction, num_instructions);
        errdefer allocator.free(instructions);

        for (0..num_instructions) |i| {
            if (pos + 5 > data.len) return error.UnexpectedEof;
            instructions[i] = .{
                .op = @enumFromInt(data[pos]),
                .arg = std.mem.readInt(u32, data[pos + 1 ..][0..4], .little),
            };
            pos += 5;
        }

        return .{
            .instructions = instructions,
            .constants = constants,
            .allocator = allocator,
        };
    }
};

/// Bytecode compiler - converts AST to bytecode
pub const Compiler = struct {
    instructions: std.ArrayList(Instruction),
    constants: std.ArrayList(Constant),
    allocator: std.mem.Allocator,

    pub fn init(allocator: std.mem.Allocator) Compiler {
        return .{
            .instructions = .{},
            .constants = .{},
            .allocator = allocator,
        };
    }

    pub fn deinit(self: *Compiler) void {
        self.instructions.deinit(self.allocator);
        self.constants.deinit(self.allocator);
    }

    /// Compile AST node to bytecode
    pub fn compile(self: *Compiler, node: *const ast_executor.Node) !BytecodeProgram {
        try self.compileNode(node);
        try self.instructions.append(self.allocator, .{ .op = .Return });

        return .{
            .instructions = try self.instructions.toOwnedSlice(self.allocator),
            .constants = try self.constants.toOwnedSlice(self.allocator),
            .allocator = self.allocator,
        };
    }

    fn compileNode(self: *Compiler, node: *const ast_executor.Node) !void {
        switch (node.*) {
            .constant => |c| {
                const const_idx = @as(u32, @intCast(self.constants.items.len));
                try self.constants.append(self.allocator, switch (c.value) {
                    .int => |i| .{ .int = i },
                    .string => |s| .{ .string = s },
                    else => return error.UnsupportedConstant,
                });
                try self.instructions.append(self.allocator, .{ .op = .LoadConst, .arg = const_idx });
            },

            .binop => |b| {
                // Compile left and right (leaves values on stack)
                try self.compileNode(b.left);
                try self.compileNode(b.right);

                // Emit operation
                const op: OpCode = switch (b.op) {
                    .Add => .Add,
                    .Sub => .Sub,
                    .Mult => .Mult,
                    .Div => .Div,
                    .FloorDiv => .FloorDiv,
                    .Mod => .Mod,
                    .Pow => .Pow,
                };
                try self.instructions.append(self.allocator, .{ .op = op });
            },

            else => return error.NotImplemented,
        }
    }
};

/// Bytecode VM executor
pub const VM = struct {
    stack: std.ArrayList(*PyObject),
    allocator: std.mem.Allocator,

    pub fn init(allocator: std.mem.Allocator) VM {
        return .{
            .stack = .{},
            .allocator = allocator,
        };
    }

    pub fn deinit(self: *VM) void {
        self.stack.deinit(self.allocator);
    }

    /// Execute bytecode program
    pub fn execute(self: *VM, program: *const BytecodeProgram) !*PyObject {
        var ip: usize = 0;

        while (ip < program.instructions.len) {
            const inst = program.instructions[ip];

            switch (inst.op) {
                .LoadConst => {
                    const constant = program.constants[inst.arg];
                    const obj: *PyObject = switch (constant) {
                        .int => |i| try PyInt.create(self.allocator, i),
                        .float => |f| try PyFloat.create(self.allocator, f),
                        .string => return error.NotImplemented,
                        .bool => |b| try PyBool.create(self.allocator, b),
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

                else => return error.NotImplemented,
            }

            ip += 1;
        }

        return error.NoReturnValue;
    }

    fn binaryOp(self: *VM, op: OpCode) !void {
        if (self.stack.items.len < 2) return error.StackUnderflow;

        const right = self.stack.pop() orelse return error.StackUnderflow;
        const left = self.stack.pop() orelse return error.StackUnderflow;

        // Check if either operand is a float
        const left_is_float = runtime.PyFloat_Check(left);
        const right_is_float = runtime.PyFloat_Check(right);

        if (left_is_float or right_is_float) {
            // Float arithmetic
            const left_val: f64 = if (left_is_float) PyFloat.getValue(left) else @floatFromInt(PyInt.getValue(left));
            const right_val: f64 = if (right_is_float) PyFloat.getValue(right) else @floatFromInt(PyInt.getValue(right));

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
        } else {
            // Integer arithmetic
            const left_val = PyInt.getValue(left);
            const right_val = PyInt.getValue(right);

            const result_val: i64 = switch (op) {
                .Add => left_val + right_val,
                .Sub => left_val - right_val,
                .Mult => left_val * right_val,
                .Div => @divTrunc(left_val, right_val),
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

        // Get integer value (convert bool to int first)
        const int_val: i64 = if (runtime.PyBool_Check(val))
            (if (PyBool.getValue(val)) @as(i64, 1) else @as(i64, 0))
        else
            PyInt.getValue(val);

        // Bitwise NOT: ~x = -(x+1) in Python
        const result_val = ~int_val;

        const result = try PyInt.create(self.allocator, result_val);
        try self.stack.append(self.allocator, result);
    }
};
