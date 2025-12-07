//! Python 'codeop' module - Compile Python code
//!
//! Utilities to compile possibly incomplete Python source code.
//!
//! Mirrors: CPython Lib/codeop.py

const std = @import("std");

// ============================================================================
// Constants
// ============================================================================

/// Flag for single interactive statement
pub const PyCF_DONT_IMPLY_DEDENT: u32 = 0x200;

/// Flag for only accept AST
pub const PyCF_ONLY_AST: u32 = 0x400;

/// Flag for allowing top level await
pub const PyCF_ALLOW_TOP_LEVEL_AWAIT: u32 = 0x800;

// ============================================================================
// Compile Result
// ============================================================================

/// Result of compilation attempt
pub const CompileResult = union(enum) {
    /// Successfully compiled code
    code: CodeObject,
    /// Incomplete input, need more
    incomplete,
    /// Syntax error
    syntax_error: SyntaxError,
};

/// Compiled code object
pub const CodeObject = struct {
    source: []const u8,
    filename: []const u8,
    mode: CompileMode,
    flags: u32,

    pub fn init(source: []const u8, filename: []const u8, mode: CompileMode, flags: u32) CodeObject {
        return .{
            .source = source,
            .filename = filename,
            .mode = mode,
            .flags = flags,
        };
    }
};

/// Compilation mode
pub const CompileMode = enum {
    exec, // Module (default)
    eval, // Single expression
    single, // Interactive statement

    pub fn fromString(s: []const u8) ?CompileMode {
        if (std.mem.eql(u8, s, "exec")) return .exec;
        if (std.mem.eql(u8, s, "eval")) return .eval;
        if (std.mem.eql(u8, s, "single")) return .single;
        return null;
    }
};

/// Syntax error information
pub const SyntaxError = struct {
    msg: []const u8,
    filename: []const u8,
    lineno: usize,
    offset: usize,
    text: []const u8,

    pub fn init(msg: []const u8, filename: []const u8, lineno: usize, offset: usize, text: []const u8) SyntaxError {
        return .{
            .msg = msg,
            .filename = filename,
            .lineno = lineno,
            .offset = offset,
            .text = text,
        };
    }
};

// ============================================================================
// Compiler
// ============================================================================

/// Compile Python source code
pub const Compiler = struct {
    const Self = @This();

    flags: u32,

    pub fn init() Self {
        return .{ .flags = PyCF_DONT_IMPLY_DEDENT };
    }

    /// Compile source code
    pub fn compile(self: *Self, source: []const u8, filename: []const u8, symbol: []const u8) CompileResult {
        const mode = CompileMode.fromString(symbol) orelse .single;
        return self.compileWithMode(source, filename, mode);
    }

    /// Compile with explicit mode
    pub fn compileWithMode(self: *Self, source: []const u8, filename: []const u8, mode: CompileMode) CompileResult {
        // Check for incomplete input
        if (isIncomplete(source, mode)) {
            return .incomplete;
        }

        // Check for syntax errors (simplified)
        if (hasSyntaxError(source)) |err| {
            return .{ .syntax_error = err };
        }

        // Successfully compiled
        return .{ .code = CodeObject.init(source, filename, mode, self.flags) };
    }
};

// ============================================================================
// CommandCompiler
// ============================================================================

/// Compiler for interactive commands
pub const CommandCompiler = struct {
    const Self = @This();

    compiler: Compiler,

    pub fn init() Self {
        return .{ .compiler = Compiler.init() };
    }

    /// Compile an interactive command
    /// Returns null if the command is incomplete
    pub fn call(self: *Self, source: []const u8, filename: ?[]const u8, symbol: ?[]const u8) ?CodeObject {
        const fname = filename orelse "<input>";
        const sym = symbol orelse "single";

        const result = self.compiler.compile(source, fname, sym);

        return switch (result) {
            .code => |c| c,
            .incomplete => null,
            .syntax_error => null, // In real impl, would raise exception
        };
    }
};

// ============================================================================
// Helper Functions
// ============================================================================

/// Check if source is incomplete
fn isIncomplete(source: []const u8, mode: CompileMode) bool {
    const trimmed = std.mem.trimRight(u8, source, " \t\r\n");
    if (trimmed.len == 0) return false;

    // Check for trailing colon (block start)
    if (trimmed[trimmed.len - 1] == ':') {
        return true;
    }

    // Check for unclosed brackets
    var paren_depth: i32 = 0;
    var bracket_depth: i32 = 0;
    var brace_depth: i32 = 0;
    var in_string = false;
    var string_char: u8 = 0;

    var i: usize = 0;
    while (i < source.len) : (i += 1) {
        const c = source[i];

        if (in_string) {
            if (c == '\\' and i + 1 < source.len) {
                i += 1; // Skip escaped char
            } else if (c == string_char) {
                in_string = false;
            }
        } else {
            if (c == '"' or c == '\'') {
                // Check for triple quotes
                if (i + 2 < source.len and source[i + 1] == c and source[i + 2] == c) {
                    // Find matching triple quote
                    i += 3;
                    while (i + 2 < source.len) {
                        if (source[i] == c and source[i + 1] == c and source[i + 2] == c) {
                            i += 2;
                            break;
                        }
                        i += 1;
                    }
                } else {
                    in_string = true;
                    string_char = c;
                }
            } else if (c == '(') {
                paren_depth += 1;
            } else if (c == ')') {
                paren_depth -= 1;
            } else if (c == '[') {
                bracket_depth += 1;
            } else if (c == ']') {
                bracket_depth -= 1;
            } else if (c == '{') {
                brace_depth += 1;
            } else if (c == '}') {
                brace_depth -= 1;
            }
        }
    }

    // Unclosed string
    if (in_string) return true;

    // Unclosed brackets
    if (paren_depth > 0 or bracket_depth > 0 or brace_depth > 0) return true;

    // In single mode, check for continuation
    if (mode == .single) {
        // Check if ends with backslash
        if (trimmed[trimmed.len - 1] == '\\') {
            return true;
        }
    }

    return false;
}

/// Check for basic syntax errors
fn hasSyntaxError(source: []const u8) ?SyntaxError {
    // Very simplified syntax checking
    var paren_depth: i32 = 0;
    var bracket_depth: i32 = 0;
    var brace_depth: i32 = 0;
    var lineno: usize = 1;

    for (source, 0..) |c, i| {
        if (c == '\n') lineno += 1;

        if (c == '(') paren_depth += 1;
        if (c == ')') paren_depth -= 1;
        if (c == '[') bracket_depth += 1;
        if (c == ']') bracket_depth -= 1;
        if (c == '{') brace_depth += 1;
        if (c == '}') brace_depth -= 1;

        if (paren_depth < 0) {
            return SyntaxError.init("unmatched ')'", "<input>", lineno, i, source);
        }
        if (bracket_depth < 0) {
            return SyntaxError.init("unmatched ']'", "<input>", lineno, i, source);
        }
        if (brace_depth < 0) {
            return SyntaxError.init("unmatched '}'", "<input>", lineno, i, source);
        }
    }

    if (paren_depth != 0 or bracket_depth != 0 or brace_depth != 0) {
        // This is incomplete, not an error
        return null;
    }

    return null;
}

// ============================================================================
// Module Functions
// ============================================================================

/// Compile source code, returning null if incomplete
pub fn compile_command(source: []const u8, filename: ?[]const u8, symbol: ?[]const u8) ?CodeObject {
    var compiler = CommandCompiler.init();
    return compiler.call(source, filename, symbol);
}

// ============================================================================
// Tests
// ============================================================================

test "Compiler init" {
    const compiler = Compiler.init();
    try std.testing.expectEqual(PyCF_DONT_IMPLY_DEDENT, compiler.flags);
}

test "CompileMode fromString" {
    try std.testing.expectEqual(CompileMode.exec, CompileMode.fromString("exec").?);
    try std.testing.expectEqual(CompileMode.eval, CompileMode.fromString("eval").?);
    try std.testing.expectEqual(CompileMode.single, CompileMode.fromString("single").?);
    try std.testing.expect(CompileMode.fromString("invalid") == null);
}

test "compile_command complete" {
    const result = compile_command("x = 1", null, null);
    try std.testing.expect(result != null);
    try std.testing.expectEqualStrings("x = 1", result.?.source);
}

test "compile_command incomplete block" {
    const result = compile_command("if True:", null, null);
    try std.testing.expect(result == null);
}

test "compile_command incomplete parens" {
    const result = compile_command("print(", null, null);
    try std.testing.expect(result == null);
}

test "compile_command incomplete string" {
    const result = compile_command("x = 'hello", null, null);
    try std.testing.expect(result == null);
}

test "isIncomplete trailing colon" {
    try std.testing.expect(isIncomplete("if True:", .single));
    try std.testing.expect(isIncomplete("def foo():", .single));
    try std.testing.expect(!isIncomplete("x = 1", .single));
}

test "isIncomplete unclosed brackets" {
    try std.testing.expect(isIncomplete("x = [1, 2", .single));
    try std.testing.expect(isIncomplete("f(1, 2", .single));
    try std.testing.expect(isIncomplete("d = {1:", .single));
}

test "CommandCompiler" {
    var compiler = CommandCompiler.init();

    const result1 = compiler.call("x = 1", null, null);
    try std.testing.expect(result1 != null);

    const result2 = compiler.call("if True:", null, null);
    try std.testing.expect(result2 == null);
}
