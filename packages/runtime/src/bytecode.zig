/// Bytecode representation for cached eval/exec
/// Compact instruction set for dynamic execution
const std = @import("std");
const ast_executor = @import("ast_executor.zig");
const PyObject = @import("runtime.zig").PyObject;
const PyInt = @import("pyint.zig").PyInt;

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
    string: []const u8,
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
};

/// Bytecode compiler - converts AST to bytecode
pub const Compiler = struct {
    instructions: std.ArrayList(Instruction),
    constants: std.ArrayList(Constant),
    allocator: std.mem.Allocator,

    pub fn init(allocator: std.mem.Allocator) Compiler {
        return .{
            .instructions = std.ArrayList(Instruction){},
            .constants = std.ArrayList(Constant){},
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
            .stack = std.ArrayList(*PyObject){},
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
                    const obj = switch (constant) {
                        .int => |i| try PyInt.create(self.allocator, i),
                        .string => return error.NotImplemented,
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

        // For MVP: assume both are PyInt
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
};
