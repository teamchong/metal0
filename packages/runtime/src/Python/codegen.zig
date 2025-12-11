/// codegen - Code Generation
/// Mirrors cpython/Python/codegen.c
///
/// The code generator transforms AST nodes into bytecode instructions.
/// It handles scope analysis, variable resolution, and instruction emission.

// ============================================================================
// Re-exports
// ============================================================================

pub const types = @import("codegen/types.zig");
pub const constant = @import("codegen/constant.zig");
pub const compiler_unit = @import("codegen/compiler_unit.zig");
pub const code_object = @import("codegen/code_object.zig");
pub const opcode = @import("codegen/opcode.zig");
pub const code_generator = @import("codegen/code_generator.zig");

// Core types
pub const CompileFlags = types.CompileFlags;
pub const ScopeType = types.ScopeType;
pub const CodeFlags = types.CodeFlags;
pub const FutureFeatures = types.FutureFeatures;

// Constant
pub const Constant = constant.Constant;

// Compiler unit
pub const CompilerUnit = compiler_unit.CompilerUnit;

// Code object
pub const CodeObject = code_object.CodeObject;

// Opcodes
pub const Opcode = opcode.Opcode;
pub const opcodeStackEffect = opcode.opcodeStackEffect;

// Code generator
pub const CodeGenerator = code_generator.CodeGenerator;
pub const init = code_generator.init;
pub const reset = code_generator.reset;
