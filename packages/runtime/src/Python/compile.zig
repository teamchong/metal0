/// Bytecode representation for cached eval/exec
/// Compact instruction set for dynamic execution
///
/// This module provides:
/// - OpCode and Instruction types for bytecode operations
/// - Constant pool for literals (int, float, string, bool, bigint, complex)
/// - BytecodeProgram with serialize/deserialize for IPC
/// - Compiler for AST → bytecode transformation
/// - VM for bytecode execution
/// - Helper functions for creating PyObjects from constants

// Re-export all public APIs from submodules
pub const constants = @import("compile/constants.zig");
pub const program = @import("compile/program.zig");
pub const compiler = @import("compile/compiler.zig");
pub const vm = @import("compile/vm.zig");
pub const helpers = @import("compile/helpers.zig");

// Re-export commonly used types
pub const OpCode = constants.OpCode;
pub const Instruction = constants.Instruction;
pub const Constant = constants.Constant;
pub const BytecodeProgram = program.BytecodeProgram;
pub const Compiler = compiler.Compiler;
pub const VM = vm.VM;
pub const PyBigInt = helpers.PyBigInt;
pub const createPyBytes = helpers.createPyBytes;
