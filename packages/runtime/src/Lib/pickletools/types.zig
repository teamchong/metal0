//! Type definitions for pickletools analysis.
//!
//! Defines data structures used for representing disassembled opcodes.
//! Mirrors: CPython Lib/pickletools.py - OpcodeInfo and Argument types

const opcode_module = @import("opcode.zig");

pub const Opcode = opcode_module.Opcode;

/// Disassembled instruction
pub const OpcodeInfo = struct {
    opcode: Opcode,
    arg: ?Argument,
    pos: usize,
    proto: u8,

    pub const Argument = union(enum) {
        int: i64,
        uint: u64,
        float: f64,
        string: []const u8,
        bytes: []const u8,
        none,
    };
};
