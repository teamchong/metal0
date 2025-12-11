/// optimizer_bytecodes - Optimizer Bytecodes
/// Mirrors cpython/Python/optimizer_bytecodes.c
///
/// Defines optimized bytecode variants and micro-op translations
/// for the trace-based optimizer.

// Re-export from submodules
pub const bytecode_defs = @import("optimizer_bytecodes/bytecode_defs.zig");
pub const translation = @import("optimizer_bytecodes/translation.zig");
pub const properties = @import("optimizer_bytecodes/properties.zig");
pub const init_mod = @import("optimizer_bytecodes/init.zig");

// Re-export core types
pub const Bytecode = bytecode_defs.Bytecode;
pub const MicroOp = bytecode_defs.MicroOp;
pub const TypeId = bytecode_defs.TypeId;

// Re-export translation types
pub const Translation = translation.Translation;
pub const MicroOpEntry = translation.MicroOpEntry;
pub const ArgSource = translation.ArgSource;
pub const Specialization = translation.Specialization;
pub const SpecCondition = translation.SpecCondition;

// Re-export translation functions
pub const translateBytecode = translation.translateBytecode;
pub const specialize = translation.specialize;
pub const guardForType = translation.guardForType;

// Re-export properties types and functions
pub const MicroOpProps = properties.MicroOpProps;
pub const getMicroOpProps = properties.getMicroOpProps;

// Re-export initialization functions
pub const init = init_mod.init;
pub const reset = init_mod.reset;

// Re-export tests
comptime {
    _ = init_mod;
}
