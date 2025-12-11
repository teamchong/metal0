/// specialize - Bytecode Specialization
/// Mirrors cpython/Python/specialize.c
///
/// Runtime bytecode specialization for adaptive interpreter optimization.
/// Specializes generic bytecode instructions to type-specific versions.

const std = @import("std");
const Allocator = std.mem.Allocator;

// Re-export submodules
pub const types = @import("specialize/types.zig");
pub const opcodes = @import("specialize/opcodes.zig");
pub const functions = @import("specialize/functions.zig");
pub const quicken = @import("specialize/quicken.zig");
pub const state = @import("specialize/state.zig");

// Re-export commonly used types from types.zig
pub const SpecFailCommon = types.SpecFailCommon;
pub const SpecFailAttr = types.SpecFailAttr;
pub const SpecFailBinaryOp = types.SpecFailBinaryOp;
pub const SpecFailSubscr = types.SpecFailSubscr;
pub const SpecFailCall = types.SpecFailCall;
pub const TypeId = types.TypeId;
pub const PyObjectHeader = types.PyObjectHeader;
pub const initTypePointers = types.initTypePointers;
pub const inferTypeId = types.inferTypeId;
pub const BackoffCounter = types.BackoffCounter;
pub const CacheEntry = types.CacheEntry;
pub const CacheFlags = types.CacheFlags;

// Re-export from opcodes.zig
pub const SpecializedOp = opcodes.SpecializedOp;
pub const SpecializationContext = opcodes.SpecializationContext;
pub const CodeUnit = opcodes.CodeUnit;
pub const getOpcodeCaches = opcodes.getOpcodeCaches;

// Re-export from functions.zig
pub const specializeLoadAttr = functions.specializeLoadAttr;
pub const specializeStoreAttr = functions.specializeStoreAttr;
pub const specializeBinaryOp = functions.specializeBinaryOp;
pub const specializeCompareOp = functions.specializeCompareOp;
pub const specializeBinarySubscr = functions.specializeBinarySubscr;
pub const specializeStoreSubscr = functions.specializeStoreSubscr;
pub const specializeCall = functions.specializeCall;
pub const specializeUnpackSequence = functions.specializeUnpackSequence;
pub const specializeForIter = functions.specializeForIter;
pub const specializeToBool = functions.specializeToBool;
pub const specializeContainsOp = functions.specializeContainsOp;
pub const specializeLoadGlobal = functions.specializeLoadGlobal;

// Re-export from quicken.zig
pub const quickenCode = quicken.quickenCode;

// Re-export from state.zig
pub const SpecializationStats = state.SpecializationStats;
pub const Specializer = state.Specializer;
pub const init = state.init;
pub const getSpecializer = state.getSpecializer;
pub const setSpecializer = state.setSpecializer;
pub const reset = state.resetModule;

// ============================================================================
// Tests
// ============================================================================

test {
    _ = types;
    _ = opcodes;
    _ = functions;
    _ = quicken;
    _ = state;
}
