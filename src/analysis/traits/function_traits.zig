/// Function traits analysis - re-exports all submodules
/// Entry point for function analysis infrastructure
const std = @import("std");
const hashmap_helper = @import("utils.hashmap_helper");

// Core types
pub const types = @import("function_traits/types.zig");
pub const FunctionTraits = types.FunctionTraits;
pub const FunctionRef = types.FunctionRef;
pub const ClassTraits = types.ClassTraits;
pub const DunderOverrides = types.DunderOverrides;
pub const AsyncComplexity = types.AsyncComplexity;
pub const ListAlias = types.ListAlias;
pub const BuiltinSubclassInstance = types.BuiltinSubclassInstance;
pub const TypeHint = types.TypeHint;

// Runtime type categories and comptime patterns (internal use)
pub const runtime_types = @import("function_traits/runtime_types.zig");

// Primitive method dispatch
pub const method_dispatch = @import("function_traits/method_dispatch.zig");
pub const FloatMethods = method_dispatch.FloatMethods;
pub const IntMethods = method_dispatch.IntMethods;
pub const DictMethods = method_dispatch.DictMethods;
pub const ListMethods = method_dispatch.ListMethods;
pub const ContextManagerMethods = method_dispatch.ContextManagerMethods;
pub const isPrimitiveMethod = method_dispatch.isPrimitiveMethod;
pub const isDictMethod = method_dispatch.isDictMethod;
pub const isListMethod = method_dispatch.isListMethod;
pub const getFloatMethod = method_dispatch.getFloatMethod;
pub const getIntMethod = method_dispatch.getIntMethod;
pub const getDictMethod = method_dispatch.getDictMethod;
pub const getListMethod = method_dispatch.getListMethod;
pub const isContextManagerMethod = method_dispatch.isContextManagerMethod;
pub const getContextManagerType = method_dispatch.getContextManagerType;

// Closure return type analysis
pub const closure_analysis = @import("function_traits/closure_analysis.zig");
pub const ClosureReturnType = closure_analysis.ClosureReturnType;
pub const analyzeClosureReturnType = closure_analysis.analyzeClosureReturnType;
pub const closureReturnTypeToZig = closure_analysis.closureReturnTypeToZig;

// Variable mutation analysis
pub const mutation_analysis = @import("function_traits/mutation_analysis.zig");
pub const MutatedVarSet = mutation_analysis.MutatedVarSet;
pub const analyzeMutatedVars = mutation_analysis.analyzeMutatedVars;
pub const isVarMutatedInBody = mutation_analysis.isVarMutatedInBody;
pub const UsedVarsSet = mutation_analysis.UsedVarsSet;
pub const analyzeUsedVars = mutation_analysis.analyzeUsedVars;
pub const isVarActuallyUsed = mutation_analysis.isVarActuallyUsed;

// Precise error types (internal use)
pub const error_types = @import("function_traits/error_types.zig");
pub const ErrorSet = error_types.ErrorSet;

// SIMD and parallelization analysis
pub const simd_analysis = @import("function_traits/simd_analysis.zig");
pub const SimdInfo = simd_analysis.SimdInfo;
pub const SimdElementType = simd_analysis.SimdElementType;
pub const SimdOp = simd_analysis.SimdOp;
pub const ParallelInfo = simd_analysis.ParallelInfo;
pub const analyzeListCompForSimd = simd_analysis.analyzeListCompForSimd;
pub const analyzeListCompForParallel = simd_analysis.analyzeListCompForParallel;

// Call graph and function analysis
pub const call_graph = @import("function_traits/call_graph.zig");
pub const CallGraph = call_graph.CallGraph;
pub const AnalyzerContext = call_graph.AnalyzerContext;
pub const buildCallGraph = call_graph.buildCallGraph;

// Heterogeneous list analysis (internal use)
pub const heterogeneous_analysis = @import("function_traits/heterogeneous_analysis.zig");

// Allocator analysis
pub const allocator_analysis = @import("function_traits/allocator_analysis.zig");
pub const analyzeNeedsAllocator = allocator_analysis.analyzeNeedsAllocator;
pub const analyzeUsesAllocatorParam = allocator_analysis.analyzeUsesAllocatorParam;

// Class analysis
pub const class_analysis = @import("function_traits/class_analysis.zig");
pub const analyzeClassTraits = class_analysis.analyzeClassTraits;
pub const analyzeAllClassTraits = class_analysis.analyzeAllClassTraits;
pub const BoundMethodRef = class_analysis.BoundMethodRef;
pub const BoundMethodRefs = class_analysis.BoundMethodRefs;
pub const findBoundMethodRefs = class_analysis.findBoundMethodRefs;
pub const getClassMethods = class_analysis.getClassMethods;

// ============================================================================
// Query API - Use these in codegen
// ============================================================================

/// Check if function should use state machine async (has I/O await)
pub fn shouldUseStateMachineAsync(graph: *const CallGraph, name: []const u8) bool {
    if (graph.functions.get(name)) |traits| {
        return traits.has_await and traits.has_io;
    }
    return false;
}

/// Check if ANY async function in module has I/O
pub fn anyAsyncHasIO(graph: *const CallGraph) bool {
    var it = graph.functions.iterator();
    while (it.next()) |entry| {
        const traits = entry.value_ptr.*;
        if (traits.has_await and traits.has_io) return true;
    }
    return false;
}

/// Check if parameter should be `var` (mutated) vs `const`
pub fn isParamMutated(graph: *const CallGraph, func_name: []const u8, param_idx: usize) bool {
    if (graph.functions.get(func_name)) |traits| {
        if (param_idx < traits.mutates_params.len) {
            return traits.mutates_params[param_idx];
        }
    }
    return false;
}

/// Check if function needs error union return type
pub fn needsErrorUnion(graph: *const CallGraph, name: []const u8) bool {
    if (graph.functions.get(name)) |traits| {
        return traits.can_error;
    }
    return false;
}

/// Get precise error types for a function
pub fn getErrorSet(graph: *const CallGraph, name: []const u8) ErrorSet {
    if (graph.functions.get(name)) |traits| {
        return traits.error_types;
    }
    return .{};
}

/// Check if function needs allocator parameter
pub fn needsAllocator(graph: *const CallGraph, name: []const u8) bool {
    if (graph.functions.get(name)) |traits| {
        return traits.needs_allocator;
    }
    return false;
}

/// Check if function actually uses allocator param
pub fn usesAllocatorParam(graph: *const CallGraph, name: []const u8) bool {
    if (graph.functions.get(name)) |traits| {
        return traits.uses_allocator_param;
    }
    return false;
}

/// Check if function is pure
pub fn isPure(graph: *const CallGraph, name: []const u8) bool {
    if (graph.functions.get(name)) |traits| {
        return traits.is_pure;
    }
    return false;
}

/// Check if function can use tail call optimization
pub fn canUseTCO(graph: *const CallGraph, name: []const u8) bool {
    if (graph.functions.get(name)) |traits| {
        return traits.is_tail_recursive;
    }
    return false;
}

/// Check if function is a generator
pub fn isGenerator(graph: *const CallGraph, name: []const u8) bool {
    if (graph.functions.get(name)) |traits| {
        return traits.is_generator;
    }
    return false;
}

/// Get captured variables for closure generation
pub fn getCapturedVars(graph: *const CallGraph, name: []const u8) []const []const u8 {
    if (graph.functions.get(name)) |traits| {
        return traits.captured_vars;
    }
    return &.{};
}

/// Check if function is dead code (not reachable)
pub fn isDeadCode(graph: *const CallGraph, name: []const u8) bool {
    if (graph.functions.get(name)) |traits| {
        return !traits.is_called;
    }
    return true;
}

/// Get async complexity for optimization decisions
pub fn getAsyncComplexity(graph: *const CallGraph, name: []const u8) AsyncComplexity {
    if (graph.functions.get(name)) |traits| {
        return traits.async_complexity;
    }
    return .trivial;
}

// ============================================================================
// Escape Analysis Query API
// ============================================================================

/// Check if a parameter escapes its function
pub fn paramEscapes(graph: *const CallGraph, func_name: []const u8, param_idx: usize) bool {
    if (graph.functions.get(func_name)) |traits| {
        if (param_idx < traits.escaping_params.len) {
            return traits.escaping_params[param_idx];
        }
    }
    return true;
}

/// Check if a local variable can be stack allocated
pub fn canStackAllocate(graph: *const CallGraph, func_name: []const u8, var_name: []const u8) bool {
    if (graph.functions.get(func_name)) |traits| {
        for (traits.escaping_locals) |local| {
            if (std.mem.eql(u8, local, var_name)) return false;
        }
        return true;
    }
    return false;
}

/// Get which parameter the return value aliases
pub fn getReturnAliasParam(graph: *const CallGraph, func_name: []const u8) ?usize {
    if (graph.functions.get(func_name)) |traits| {
        return traits.return_aliases_param;
    }
    return null;
}

/// Get all non-escaping locals in a function
pub fn getNonEscapingLocals(graph: *const CallGraph, func_name: []const u8) []const []const u8 {
    if (graph.functions.get(func_name)) |traits| {
        if (traits.all_locals.len == 0) return &.{};
        if (traits.escaping_locals.len == 0) return traits.all_locals;

        var escaping_set = hashmap_helper.StringHashMap(void).init(graph.allocator);
        defer escaping_set.deinit();

        for (traits.escaping_locals) |local| {
            escaping_set.put(local, {}) catch continue;
        }

        var result: std.ArrayList([]const u8) = .{};
        for (traits.all_locals) |local| {
            if (!escaping_set.contains(local)) {
                result.append(graph.allocator, local) catch continue;
            }
        }

        return result.toOwnedSlice(graph.allocator) catch &.{};
    }
    return &.{};
}

// ============================================================================
// Tests
// ============================================================================

test "build call graph from simple function" {
    const allocator = std.testing.allocator;
    _ = allocator;
}
