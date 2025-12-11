/// _opcode_metadata - Python Bytecode Opcode Metadata
/// Mirrors cpython/Lib/_opcode_metadata.py
///
/// Metadata about Python bytecode opcodes including stack effects,
/// instruction formats, and specialization information.
/// Used by the dis module and other bytecode analysis tools.

pub const types = @import("_opcode_metadata/types.zig");
pub const opcodes_mod = @import("_opcode_metadata/opcodes.zig");
pub const operations = @import("_opcode_metadata/operations.zig");
pub const lookup = @import("_opcode_metadata/lookup.zig");
pub const state = @import("_opcode_metadata/state.zig");

// Re-export commonly used types and functions
pub const OpcodeCategory = types.OpcodeCategory;
pub const OpcodeFlags = types.OpcodeFlags;
pub const StackEffect = types.StackEffect;
pub const OpcodeDef = types.OpcodeDef;

pub const opcodes = opcodes_mod.opcodes;

pub const CompareOp = operations.CompareOp;
pub const BinaryOp = operations.BinaryOp;

pub const getOpcode = lookup.getOpcode;
pub const getOpcodeByName = lookup.getOpcodeByName;

pub const init = state.init;
pub const reset = state.reset;

test {
    _ = types;
    _ = opcodes_mod;
    _ = operations;
    _ = lookup;
    _ = state;
}
