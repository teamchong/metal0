/// Bytecode codegen - compiles PyAOT AST to runtime bytecode format
/// Used for --emit-bytecode flag to support runtime eval()
const std = @import("std");
const ast = @import("ast");

/// Bytecode opcodes (must match packages/runtime/src/bytecode.zig)
pub const OpCode = enum(u8) {
    LoadConst,
    Pop,
    Add,
    Sub,
    Mult,
    Div,
    FloorDiv,
    Mod,
    Pow,
    Eq,
    NotEq,
    Lt,
    Gt,
    LtE,
    GtE,
    Return,
    Call,
};

pub const Instruction = struct {
    op: OpCode,
    arg: u32 = 0,
};

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

    /// Serialize to binary format for subprocess IPC
    pub fn serialize(self: *const BytecodeProgram, allocator: std.mem.Allocator) ![]u8 {
        var buffer = std.ArrayList(u8){};
        errdefer buffer.deinit(allocator);

        // Magic: "PYBC" (4 bytes)
        try buffer.appendSlice(allocator, "PYBC");

        // Version: 1 (4 bytes, little endian)
        try buffer.appendSlice(allocator, &std.mem.toBytes(@as(u32, 1)));

        // Number of constants (4 bytes)
        try buffer.appendSlice(allocator, &std.mem.toBytes(@as(u32, @intCast(self.constants.len))));

        // Constants
        for (self.constants) |constant| {
            switch (constant) {
                .int => |i| {
                    try buffer.append(allocator, 0); // type tag: int
                    try buffer.appendSlice(allocator, &std.mem.toBytes(i));
                },
                .string => |s| {
                    try buffer.append(allocator, 1); // type tag: string
                    try buffer.appendSlice(allocator, &std.mem.toBytes(@as(u32, @intCast(s.len))));
                    try buffer.appendSlice(allocator, s);
                },
            }
        }

        // Number of instructions (4 bytes)
        try buffer.appendSlice(allocator, &std.mem.toBytes(@as(u32, @intCast(self.instructions.len))));

        // Instructions (5 bytes each: 1 opcode + 4 arg)
        for (self.instructions) |inst| {
            try buffer.append(allocator, @intFromEnum(inst.op));
            try buffer.appendSlice(allocator, &std.mem.toBytes(inst.arg));
        }

        return buffer.toOwnedSlice(allocator);
    }
};

/// Bytecode compiler - converts PyAOT AST to bytecode
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

    /// Compile module to bytecode (eval typically has single expression)
    pub fn compile(self: *Compiler, module: ast.Node.Module) !BytecodeProgram {
        // For eval: compile all statements, last one is the return value
        for (module.body) |stmt| {
            try self.compileNode(stmt);
        }
        try self.instructions.append(self.allocator, .{ .op = .Return });

        return .{
            .instructions = try self.instructions.toOwnedSlice(self.allocator),
            .constants = try self.constants.toOwnedSlice(self.allocator),
            .allocator = self.allocator,
        };
    }

    fn compileNode(self: *Compiler, node: ast.Node) !void {
        switch (node) {
            .expr_stmt => |expr| {
                try self.compileNode(expr.value.*);
            },
            .constant => |c| {
                const const_idx: u32 = @intCast(self.constants.items.len);
                const constant: Constant = switch (c.value) {
                    .int => |i| .{ .int = i },
                    .string => |s| .{ .string = s },
                    else => return error.UnsupportedConstant,
                };
                try self.constants.append(self.allocator, constant);
                try self.instructions.append(self.allocator, .{ .op = .LoadConst, .arg = const_idx });
            },
            .binop => |b| {
                try self.compileNode(b.left.*);
                try self.compileNode(b.right.*);

                const op: OpCode = switch (b.op) {
                    .Add => .Add,
                    .Sub => .Sub,
                    .Mult => .Mult,
                    .Div => .Div,
                    .FloorDiv => .FloorDiv,
                    .Mod => .Mod,
                    .Pow => .Pow,
                    else => return error.UnsupportedOperator,
                };
                try self.instructions.append(self.allocator, .{ .op = op });
            },
            .compare => |c| {
                try self.compileNode(c.left.*);
                if (c.comparators.len != 1) return error.MultipleComparators;
                try self.compileNode(c.comparators[0]);

                const op: OpCode = switch (c.ops[0]) {
                    .Eq => .Eq,
                    .NotEq => .NotEq,
                    .Lt => .Lt,
                    .Gt => .Gt,
                    .LtEq => .LtE,
                    .GtEq => .GtE,
                    else => return error.UnsupportedComparator,
                };
                try self.instructions.append(self.allocator, .{ .op = op });
            },
            else => return error.UnsupportedNode,
        }
    }
};

/// Compile Python source to bytecode
/// For eval-style expressions, appends newline if needed (parser expects statement termination)
pub fn compileSource(allocator: std.mem.Allocator, source: []const u8) !BytecodeProgram {
    const lexer_mod = @import("../lexer.zig");
    const parser_mod = @import("../parser.zig");

    // For eval expressions, ensure source ends with newline (parser expects statement termination)
    const eval_source = if (source.len > 0 and source[source.len - 1] != '\n')
        try std.mem.concat(allocator, u8, &.{ source, "\n" })
    else
        try allocator.dupe(u8, source);
    defer allocator.free(eval_source);

    var lex = try lexer_mod.Lexer.init(allocator, eval_source);
    defer lex.deinit();

    const tokens = try lex.tokenize();
    defer lexer_mod.freeTokens(allocator, tokens);

    var p = parser_mod.Parser.init(allocator, tokens);
    defer p.deinit();
    const tree = try p.parse();
    defer tree.deinit(allocator);

    if (tree != .module) return error.ExpectedModule;

    var compiler = Compiler.init(allocator);
    defer compiler.deinit();

    return try compiler.compile(tree.module);
}
