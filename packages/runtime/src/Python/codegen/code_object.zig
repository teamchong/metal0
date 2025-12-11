/// code_object - Compiled Code Object
/// Mirrors cpython/Python/codegen.c code object
///
/// Represents a compiled Python code object (function, module, etc).

const std = @import("std");
const types = @import("types.zig");
const constant = @import("constant.zig");

pub const CodeFlags = types.CodeFlags;
pub const Constant = constant.Constant;

// ============================================================================
// Code Object
// ============================================================================

/// Compiled code object
pub const CodeObject = struct {
    /// Function name
    name: []const u8,
    /// Filename
    filename: []const u8,
    /// First line number
    firstlineno: i32 = 1,
    /// Bytecode
    bytecode: []const u8 = &[_]u8{},
    /// Constants
    consts: []const Constant = &[_]Constant{},
    /// Names used
    names: []const []const u8 = &[_][]const u8{},
    /// Local variable names
    varnames: []const []const u8 = &[_][]const u8{},
    /// Free variable names
    freevars: []const []const u8 = &[_][]const u8{},
    /// Cell variable names
    cellvars: []const []const u8 = &[_][]const u8{},
    /// Number of arguments
    argcount: u32 = 0,
    /// Number of positional-only arguments
    posonlyargcount: u32 = 0,
    /// Number of keyword-only arguments
    kwonlyargcount: u32 = 0,
    /// Number of local variables
    nlocals: u32 = 0,
    /// Required stack size
    stacksize: u32 = 0,
    /// Code flags
    flags: CodeFlags = .{},
};
