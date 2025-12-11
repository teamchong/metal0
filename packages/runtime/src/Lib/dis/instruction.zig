//! Instruction representation for bytecode disassembly.
//!
//! This module defines the Instruction struct representing a single
//! bytecode instruction with its metadata.

const opcode = @import("opcode.zig");

/// Represents a single bytecode instruction
pub const Instruction = struct {
    opcode: opcode.Opcode,
    opname: []const u8,
    arg: ?u32,
    argval: ?ArgumentValue,
    argrepr: ?[]const u8,
    offset: usize,
    starts_line: ?u32,
    is_jump_target: bool,

    pub const ArgumentValue = union(enum) {
        int: i64,
        string: []const u8,
        none,
    };
};
