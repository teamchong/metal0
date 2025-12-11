/// functions - Specialization Functions
/// Type-specific specialization logic for each instruction category.

const std = @import("std");
const types = @import("types.zig");
const opcodes = @import("opcodes.zig");

pub const TypeId = types.TypeId;
pub const SpecializedOp = opcodes.SpecializedOp;
pub const SpecializationContext = opcodes.SpecializationContext;

// ============================================================================
// Attribute Specialization
// ============================================================================

/// Specialize LOAD_ATTR instruction
pub fn specializeLoadAttr(ctx: *SpecializationContext) SpecializedOp {
    switch (ctx.obj_type) {
        .module => return .LOAD_ATTR_MODULE,
        .dict_type => return .LOAD_ATTR_WITH_HINT,
        .object => {
            // Check for method vs attribute
            if (ctx.cache) |cache| {
                if (cache.flags.is_method) {
                    return .LOAD_ATTR_METHOD_WITH_VALUES;
                }
            }
            return .LOAD_ATTR_INSTANCE_VALUE;
        },
        .class_type => return .LOAD_ATTR_CLASS,
        else => return .GENERIC,
    }
}

/// Specialize STORE_ATTR instruction
pub fn specializeStoreAttr(ctx: *SpecializationContext) SpecializedOp {
    switch (ctx.obj_type) {
        .object => return .STORE_ATTR_INSTANCE_VALUE,
        .dict_type => return .STORE_ATTR_WITH_HINT,
        else => return .GENERIC,
    }
}

// ============================================================================
// Binary Operation Specialization
// ============================================================================

/// Specialize BINARY_OP instruction
pub fn specializeBinaryOp(ctx: *SpecializationContext) SpecializedOp {
    // Check for same-type optimizations
    if (ctx.lhs_type == ctx.rhs_type) {
        switch (ctx.lhs_type) {
            .int_small, .int_compact => {
                return switch (ctx.oparg) {
                    0 => .BINARY_OP_ADD_INT,
                    10 => .BINARY_OP_SUBTRACT_INT,
                    5 => .BINARY_OP_MULTIPLY_INT,
                    else => .GENERIC,
                };
            },
            .float_type => {
                return switch (ctx.oparg) {
                    0 => .BINARY_OP_ADD_FLOAT,
                    10 => .BINARY_OP_SUBTRACT_FLOAT,
                    5 => .BINARY_OP_MULTIPLY_FLOAT,
                    else => .GENERIC,
                };
            },
            .str_type => {
                return switch (ctx.oparg) {
                    0 => .BINARY_OP_ADD_UNICODE,
                    else => .GENERIC,
                };
            },
            else => return .GENERIC,
        }
    }
    return .GENERIC;
}

/// Specialize COMPARE_OP instruction
pub fn specializeCompareOp(ctx: *SpecializationContext) SpecializedOp {
    if (ctx.lhs_type == ctx.rhs_type) {
        return switch (ctx.lhs_type) {
            .int_small, .int_compact, .int_big => .COMPARE_OP_INT,
            .float_type => .COMPARE_OP_FLOAT,
            .str_type => .COMPARE_OP_STR,
            else => .GENERIC,
        };
    }
    return .GENERIC;
}

// ============================================================================
// Subscript Specialization
// ============================================================================

/// Specialize BINARY_SUBSCR instruction
pub fn specializeBinarySubscr(ctx: *SpecializationContext) SpecializedOp {
    // Check index type is integer
    if (ctx.rhs_type != .int_small and ctx.rhs_type != .int_compact) {
        // Could be dict or generic
        if (ctx.lhs_type == .dict_type) {
            return .BINARY_SUBSCR_DICT;
        }
        return .GENERIC;
    }

    return switch (ctx.lhs_type) {
        .list_type => .BINARY_SUBSCR_LIST_INT,
        .tuple_type => .BINARY_SUBSCR_TUPLE_INT,
        .str_type => .BINARY_SUBSCR_STR_INT,
        .dict_type => .BINARY_SUBSCR_DICT,
        else => .GENERIC,
    };
}

/// Specialize STORE_SUBSCR instruction
pub fn specializeStoreSubscr(ctx: *SpecializationContext) SpecializedOp {
    if (ctx.lhs_type == .dict_type) {
        return .STORE_SUBSCR_DICT;
    }

    // Check index type is integer for list
    if (ctx.rhs_type == .int_small or ctx.rhs_type == .int_compact) {
        if (ctx.lhs_type == .list_type) {
            return .STORE_SUBSCR_LIST_INT;
        }
    }

    return .GENERIC;
}

// ============================================================================
// Call Specialization
// ============================================================================

/// Specialize CALL instruction
pub fn specializeCall(ctx: *SpecializationContext, callable_type: TypeId) SpecializedOp {
    _ = ctx;
    return switch (callable_type) {
        .function => .CALL_PY_EXACT_ARGS,
        .builtin => .CALL_BUILTIN_FAST,
        .method => .CALL_METHOD_DESCRIPTOR_FAST,
        .class_type => .CALL_BUILTIN_CLASS,
        else => .GENERIC,
    };
}

// ============================================================================
// Sequence Specialization
// ============================================================================

/// Specialize UNPACK_SEQUENCE instruction
pub fn specializeUnpackSequence(ctx: *SpecializationContext) SpecializedOp {
    return switch (ctx.obj_type) {
        .tuple_type => {
            if (ctx.oparg == 2) {
                return .UNPACK_SEQUENCE_TWO_TUPLE;
            }
            return .UNPACK_SEQUENCE_TUPLE;
        },
        .list_type => .UNPACK_SEQUENCE_LIST,
        else => .GENERIC,
    };
}

/// Specialize FOR_ITER instruction
pub fn specializeForIter(ctx: *SpecializationContext, iter_type: TypeId) SpecializedOp {
    _ = ctx;
    return switch (iter_type) {
        .list_type => .FOR_ITER_LIST,
        .tuple_type => .FOR_ITER_TUPLE,
        else => .GENERIC,
    };
}

// ============================================================================
// Boolean Specialization
// ============================================================================

/// Specialize TO_BOOL instruction
pub fn specializeToBool(ctx: *SpecializationContext) SpecializedOp {
    return switch (ctx.obj_type) {
        .bool_type => .TO_BOOL_BOOL,
        .int_small, .int_compact, .int_big => .TO_BOOL_INT,
        .str_type => .TO_BOOL_STR,
        .none => .TO_BOOL_NONE,
        .list_type => .TO_BOOL_LIST,
        else => .GENERIC,
    };
}

/// Specialize CONTAINS_OP instruction
pub fn specializeContainsOp(ctx: *SpecializationContext) SpecializedOp {
    return switch (ctx.obj_type) {
        .set_type => .CONTAINS_OP_SET,
        .dict_type => .CONTAINS_OP_DICT,
        else => .GENERIC,
    };
}

// ============================================================================
// Global Specialization
// ============================================================================

/// Specialize LOAD_GLOBAL instruction
pub fn specializeLoadGlobal(is_builtin: bool) SpecializedOp {
    return if (is_builtin) .LOAD_GLOBAL_BUILTIN else .LOAD_GLOBAL_MODULE;
}

// ============================================================================
// Tests
// ============================================================================

test "binary op specialization" {
    var ctx = SpecializationContext{
        .ip = 0,
        .opcode = 122, // BINARY_OP
        .oparg = 0, // Add
        .cache = null,
        .lhs_type = .int_small,
        .rhs_type = .int_small,
    };

    const result = specializeBinaryOp(&ctx);
    try std.testing.expectEqual(SpecializedOp.BINARY_OP_ADD_INT, result);
}

test "compare op specialization" {
    var ctx = SpecializationContext{
        .ip = 0,
        .opcode = 107, // COMPARE_OP
        .oparg = 0,
        .cache = null,
        .lhs_type = .float_type,
        .rhs_type = .float_type,
    };

    const result = specializeCompareOp(&ctx);
    try std.testing.expectEqual(SpecializedOp.COMPARE_OP_FLOAT, result);
}

test "subscr specialization" {
    var ctx = SpecializationContext{
        .ip = 0,
        .opcode = 25, // BINARY_SUBSCR
        .oparg = 0,
        .cache = null,
        .lhs_type = .list_type,
        .rhs_type = .int_small,
    };

    const result = specializeBinarySubscr(&ctx);
    try std.testing.expectEqual(SpecializedOp.BINARY_SUBSCR_LIST_INT, result);
}

test "to_bool specialization" {
    var ctx = SpecializationContext{
        .ip = 0,
        .opcode = 0,
        .oparg = 0,
        .cache = null,
        .obj_type = .bool_type,
    };

    var result = specializeToBool(&ctx);
    try std.testing.expectEqual(SpecializedOp.TO_BOOL_BOOL, result);

    ctx.obj_type = .str_type;
    result = specializeToBool(&ctx);
    try std.testing.expectEqual(SpecializedOp.TO_BOOL_STR, result);
}

test "load attr specialization" {
    var ctx = SpecializationContext{
        .ip = 0,
        .opcode = 106, // LOAD_ATTR
        .oparg = 0,
        .cache = null,
        .obj_type = .module,
    };

    const result = specializeLoadAttr(&ctx);
    try std.testing.expectEqual(SpecializedOp.LOAD_ATTR_MODULE, result);
}
