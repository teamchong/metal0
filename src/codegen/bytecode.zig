/// Bytecode Codegen - AST to Bytecode compilation
///
/// This module provides the compiler that translates metal0 AST nodes
/// to bytecode for the runtime VM.
const std = @import("std");

pub const ast_compiler = @import("bytecode/ast_compiler.zig");
pub const AstCompiler = ast_compiler.AstCompiler;

// Legacy types for backwards compatibility
const runtime = @import("runtime");
pub const bytecode = runtime.bytecode;
pub const CodeObject = bytecode.CodeObject;
pub const Opcode = bytecode.Opcode;
pub const PyValue = bytecode.PyValue;

/// Legacy BytecodeProgram type for backwards compatibility
/// Wraps the new CodeObject type
pub const BytecodeProgram = struct {
    code: *const CodeObject,
    allocator: std.mem.Allocator,

    pub fn deinit(self: *BytecodeProgram) void {
        self.allocator.free(self.code.bytecode);
        self.allocator.free(self.code.constants);
        self.allocator.free(self.code.varnames);
        self.allocator.free(self.code.freevars);
        self.allocator.free(self.code.cellvars);
        self.allocator.free(self.code.names);
        self.allocator.destroy(self.code);
    }

    /// Serialize bytecode to bytes for subprocess communication
    /// Format: [magic:4][version:2][bytecode_len:4][bytecode][constants_len:4][names_len:4][names...]
    pub fn serialize(self: BytecodeProgram, allocator: std.mem.Allocator) ![]u8 {
        var result: std.ArrayList(u8) = .{};
        errdefer result.deinit(allocator);

        // Magic: "MET0"
        try result.appendSlice(allocator, "MET0");
        // Version
        try result.appendSlice(allocator, &std.mem.toBytes(@as(u16, bytecode.BYTECODE_VERSION)));
        // Bytecode length + bytes
        try result.appendSlice(allocator, &std.mem.toBytes(@as(u32, @intCast(self.code.bytecode.len))));
        try result.appendSlice(allocator, self.code.bytecode);
        // Constants count + data
        try result.appendSlice(allocator, &std.mem.toBytes(@as(u32, @intCast(self.code.constants.len))));
        // Serialize each constant
        for (self.code.constants) |constant| {
            switch (constant) {
                .int => |i| {
                    try result.append(allocator, 0); // type tag: int
                    try result.appendSlice(allocator, &std.mem.toBytes(i));
                },
                .float => |f| {
                    try result.append(allocator, 2); // type tag: float
                    try result.appendSlice(allocator, &std.mem.toBytes(f));
                },
                .string => |s| {
                    try result.append(allocator, 1); // type tag: string
                    try result.appendSlice(allocator, &std.mem.toBytes(@as(u32, @intCast(s.len))));
                    try result.appendSlice(allocator, s);
                },
                .bool => |b| {
                    try result.append(allocator, 3); // type tag: bool
                    try result.append(allocator, if (b) 1 else 0);
                },
                .none => {
                    try result.append(allocator, 7); // type tag: none
                },
                .complex => |c| {
                    try result.append(allocator, 6); // type tag: complex
                    try result.appendSlice(allocator, &std.mem.toBytes(c.imag));
                },
                .bytes => |b| {
                    try result.append(allocator, 5); // type tag: bytes
                    try result.appendSlice(allocator, &std.mem.toBytes(@as(u32, @intCast(b.data.len))));
                    try result.appendSlice(allocator, b.data);
                },
                .bigint => |bi| {
                    try result.append(allocator, 4); // type tag: bigint
                    // Serialize BigInt as string representation
                    const str = bi.toString(allocator, 10) catch "0";
                    defer allocator.free(str);
                    try result.appendSlice(allocator, &std.mem.toBytes(@as(u32, @intCast(str.len))));
                    try result.appendSlice(allocator, str);
                },
                else => {
                    // Skip unsupported constant types
                    try result.append(allocator, 7); // treat as none
                },
            }
        }
        // Names count + names (length-prefixed strings)
        try result.appendSlice(allocator, &std.mem.toBytes(@as(u32, @intCast(self.code.names.len))));
        for (self.code.names) |name| {
            try result.appendSlice(allocator, &std.mem.toBytes(@as(u32, @intCast(name.len))));
            try result.appendSlice(allocator, name);
        }
        return result.toOwnedSlice(allocator);
    }
};

/// Compile source code to bytecode program
/// This is the main entry point for eval()/exec()
pub fn compileSource(allocator: std.mem.Allocator, source: []const u8) !BytecodeProgram {
    const lexer_mod = @import("../lexer.zig");
    const parser_mod = @import("../parser.zig");

    // Ensure source ends with newline
    const eval_source = if (source.len > 0 and source[source.len - 1] != '\n')
        try std.mem.concat(allocator, u8, &.{ source, "\n" })
    else
        try allocator.dupe(u8, source);
    defer allocator.free(eval_source);

    // Tokenize
    var lex = try lexer_mod.Lexer.init(allocator, eval_source);
    defer lex.deinit();

    const tokens = try lex.tokenize();
    defer lexer_mod.freeTokens(allocator, tokens);

    // Parse
    var p = parser_mod.Parser.init(allocator, tokens);
    defer p.deinit();
    const tree = try p.parse();
    defer tree.deinit(allocator);

    if (tree != .module) return error.ExpectedModule;

    // Compile to bytecode
    var compiler = AstCompiler.init(allocator);
    defer compiler.deinit();

    const code = try compiler.compileModule(tree.module.body);

    return .{
        .code = code,
        .allocator = allocator,
    };
}

/// Compile expression for eval()
pub fn compileExpr(allocator: std.mem.Allocator, source: []const u8) !BytecodeProgram {
    const lexer_mod = @import("../lexer.zig");
    const parser_mod = @import("../parser.zig");

    // Tokenize
    var lex = try lexer_mod.Lexer.init(allocator, source);
    defer lex.deinit();

    const tokens = try lex.tokenize();
    defer lexer_mod.freeTokens(allocator, tokens);

    // Parse as expression
    var p = parser_mod.Parser.init(allocator, tokens);
    defer p.deinit();
    const expr = try p.parseExpression();
    defer expr.deinit(allocator);

    // Compile to bytecode
    var compiler = AstCompiler.init(allocator);
    defer compiler.deinit();

    const code = try compiler.compileExpr(expr);

    return .{
        .code = code,
        .allocator = allocator,
    };
}

// Tests are in ast_compiler.zig and the runtime bytecode module
// compileSource/compileExpr require full project context (lexer, parser)
// so we don't test them directly here
