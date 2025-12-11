//! CPython source: Lib/dis.py
//!
//! Provides functions to disassemble Python bytecode.
//!
//! Mirrors: CPython Lib/dis.py
//!
//! This module has been split into a modular directory structure:
//! - dis/opcode.zig - Opcode definitions and methods
//! - dis/instruction.zig - Instruction struct
//! - dis/bytecode.zig - Bytecode analysis class
//! - dis/disassembler.zig - Core disassembly functions
//! - dis/analysis.zig - Bytecode analysis utilities
//! - dis/constants.zig - Constants

// Re-export opcode definitions
pub const opcode = @import("dis/opcode.zig");
pub const Opcode = opcode.Opcode;
pub const CmpOp = opcode.CmpOp;

// Re-export instruction
pub const instruction = @import("dis/instruction.zig");
pub const Instruction = instruction.Instruction;

// Re-export bytecode
pub const bytecode = @import("dis/bytecode.zig");
pub const Bytecode = bytecode.Bytecode;

// Re-export disassembler functions
pub const disassembler = @import("dis/disassembler.zig");
pub const dis = disassembler.dis;
pub const disassemble = disassembler.disassemble;
pub const disassembleBytes = disassembler.disassembleBytes;
pub const getInstructions = disassembler.getInstructions;
pub const showCode = disassembler.showCode;
pub const codeInfo = disassembler.codeInfo;

// Re-export analysis functions
pub const analysis = @import("dis/analysis.zig");
pub const findlabels = analysis.findlabels;
pub const findlinestarts = analysis.findlinestarts;
pub const stackEffect = analysis.stackEffect;

// Re-export constants
pub const constants = @import("dis/constants.zig");
pub const HAVE_ARGUMENT = constants.HAVE_ARGUMENT;
pub const EXTENDED_ARG_SHIFT = constants.EXTENDED_ARG_SHIFT;

// Re-export tests
test {
    @import("std").testing.refAllDecls(@This());
}
