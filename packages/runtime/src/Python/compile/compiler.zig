/// Bytecode compiler - converts AST to bytecode
const std = @import("std");
const ast_executor = @import("../ast_executor.zig");
const constants = @import("constants.zig");
const program = @import("program.zig");
const OpCode = constants.OpCode;
const Instruction = constants.Instruction;
const Constant = constants.Constant;
const BytecodeProgram = program.BytecodeProgram;

/// Bytecode compiler
pub const Compiler = struct {
    instructions: std.ArrayList(Instruction),
    consts: std.ArrayList(Constant),
    allocator: std.mem.Allocator,

    pub fn init(allocator: std.mem.Allocator) Compiler {
        return .{
            .instructions = .{},
            .consts = .{},
            .allocator = allocator,
        };
    }

    pub fn deinit(self: *Compiler) void {
        self.instructions.deinit(self.allocator);
        self.consts.deinit(self.allocator);
    }

    /// Compile AST node to bytecode
    pub fn compile(self: *Compiler, node: *const ast_executor.Node) !BytecodeProgram {
        try self.compileNode(node);
        try self.instructions.append(self.allocator, .{ .op = .Return });

        return .{
            .instructions = try self.instructions.toOwnedSlice(self.allocator),
            .constants = try self.consts.toOwnedSlice(self.allocator),
            .allocator = self.allocator,
        };
    }

    fn compileNode(self: *Compiler, node: *const ast_executor.Node) !void {
        switch (node.*) {
            .constant => |c| {
                const const_idx = @as(u32, @intCast(self.consts.items.len));
                try self.consts.append(self.allocator, switch (c.value) {
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

            else => return error.UnsupportedASTNode, // Node type not yet supported in bytecode compiler
        }
    }
};
