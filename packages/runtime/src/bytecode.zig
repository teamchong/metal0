/// Bytecode VM - Dynamic Python execution for metal0
///
/// This module provides a stable bytecode VM for executing dynamic Python features:
/// - eval() / exec()
/// - Dynamic import (__import__)
/// - Dynamic attribute access (getattr/setattr)
/// - Monkey patching
/// - Metaclasses
///
/// Design principles:
/// 1. Stable bytecode format (NOT CPython opcodes - those change between versions)
/// 2. VM dispatches to existing runtime functions (no reimplementation)
/// 3. Shares freeze infrastructure with edgebox for hot path optimization
///
/// Usage:
/// ```zig
/// const bytecode = @import("bytecode");
///
/// // Create VM
/// var globals = bytecode.PyValue.Dict.init(allocator);
/// var vm = bytecode.VM.init(allocator, &globals);
/// defer vm.deinit();
///
/// // Execute code
/// const result = try vm.execute(&code_object);
/// ```
const std = @import("std");

/// Opcodes - Stable bytecode instruction set
pub const opcodes = @import("bytecode/opcodes.zig");
pub const Opcode = opcodes.Opcode;
pub const OpcodeCategory = opcodes.OpcodeCategory;
pub const FreezeClass = opcodes.FreezeClass;
pub const Instruction = opcodes.Instruction;
pub const BYTECODE_VERSION = opcodes.BYTECODE_VERSION;
pub const BYTECODE_MAGIC = opcodes.BYTECODE_MAGIC;
pub const encodeVarInt = opcodes.encodeVarInt;
pub const decodeVarInt = opcodes.decodeVarInt;

/// Frame - Call stack frame and code objects
pub const frame = @import("bytecode/frame.zig");
pub const Frame = frame.Frame;
pub const CodeObject = frame.CodeObject;
pub const CodeFlags = frame.CodeFlags;
pub const ExcHandler = frame.ExcHandler;
pub const ExcEntry = frame.ExcEntry;
pub const PyValue = frame.PyValue;

/// VM - Bytecode executor
pub const vm = @import("bytecode/vm.zig");
pub const VM = vm.VM;
pub const VMError = vm.VMError;

/// Compiler - AST to bytecode
pub const compiler = @import("bytecode/compiler.zig");
pub const Compiler = compiler.Compiler;
pub const CompileError = compiler.CompileError;
pub const BinOpType = compiler.BinOpType;
pub const UnaryOpType = compiler.UnaryOpType;
pub const CompareOpType = compiler.CompareOpType;

test {
    // Run all submodule tests
    std.testing.refAllDecls(@This());
}
