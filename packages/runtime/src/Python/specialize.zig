/// specialize - Bytecode Specialization
/// Mirrors cpython/Python/specialize.c
///
/// Runtime bytecode specialization for adaptive interpreter optimization.
/// Specializes generic bytecode instructions to type-specific versions.

const std = @import("std");
const Allocator = std.mem.Allocator;

// ============================================================================
// Specialization Failure Codes
// ============================================================================

/// Common failure reasons
pub const SpecFailCommon = enum(u8) {
    other = 0,
    no_dict = 1,
    overridden = 2,
    out_of_versions = 3,
    out_of_range = 4,
    expected_error = 5,
    wrong_number_arguments = 6,
    code_complex_parameters = 7,
    code_not_optimized = 8,
};

/// Attribute specialization failures
pub const SpecFailAttr = enum(u8) {
    overriding_descriptor = 9,
    non_overriding_descriptor = 10,
    not_descriptor = 11,
    method = 12,
    mutable_class = 13,
    property = 14,
    non_object_slot = 15,
    read_only = 16,
    audited_slot = 17,
    not_managed_dict = 18,
    non_string = 19,
    module_attr_not_found = 20,
    shadowed = 21,
    builtin_class_method = 22,
    class_method_obj = 23,
    object_slot = 24,
    instance_attribute = 26,
    metaclass_attribute = 27,
    property_not_py_function = 28,
    not_in_keys = 29,
    not_in_dict = 30,
    class_attr_simple = 31,
    class_attr_descriptor = 32,
    builtin_class_method_obj = 33,
    metaclass_overridden = 34,
    split_dict = 35,
    descr_not_deferred = 36,
};

/// Binary operation specialization failures
pub const SpecFailBinaryOp = enum(u8) {
    add_different_types = 9,
    add_other = 10,
    and_different_types = 11,
    and_int = 12,
    and_other = 13,
    floor_divide = 14,
    lshift = 15,
    matrix_multiply = 16,
    multiply_different_types = 17,
    multiply_other = 18,
    or_op = 19,
    power = 20,
    remainder = 21,
    rshift = 22,
    subtract_different_types = 23,
    subtract_other = 24,
    true_divide_different_types = 25,
    true_divide_float = 26,
    true_divide_other = 27,
    xor_op = 28,
    or_int = 29,
    or_different_types = 30,
    xor_int = 31,
    xor_different_types = 32,
};

/// Subscript specialization failures
pub const SpecFailSubscr = enum(u8) {
    array_int = 9,
    array_slice = 10,
    list_slice = 11,
    buffer_int = 12,
    buffer_slice = 13,
    bytearray_int = 18,
    bytearray_slice = 19,
    py_simple = 20,
    py_other = 21,
    dict_subclass_no_override = 22,
    not_heap_type = 23,
};

/// Call specialization failures
pub const SpecFailCall = enum(u8) {
    method_self = 9,
    abstract_class = 10,
    python_class = 11,
    cfunc_varargs = 12,
    cfunc_noargs_with_args = 13,
    builtin_class = 14,
    str_arg = 15,
    class_no_vectorcall = 16,
    class_mutable = 17,
    kwargs = 18,
    method_descriptor = 19,
    bound_method = 20,
    init_not_python = 21,
    init_not_simple = 22,
    wrong_self_type = 23,
    bad_call_flags = 24,
    init_not_inline_values = 25,
};

// ============================================================================
// Type IDs for Specialization
// ============================================================================

/// Type identifiers used during specialization
pub const TypeId = enum(u8) {
    unknown = 0,
    none = 1,
    bool_type = 2,
    int_small = 3,
    int_compact = 4,
    int_big = 5,
    float_type = 6,
    str_type = 7,
    bytes_type = 8,
    list_type = 9,
    tuple_type = 10,
    dict_type = 11,
    set_type = 12,
    function = 13,
    method = 14,
    builtin = 15,
    module = 16,
    class_type = 17,
    object = 18,
};

/// Infer type ID from runtime value
pub fn inferTypeId(value: ?*anyopaque) TypeId {
    if (value == null) return .none;
    // In a real implementation, would check Python type header
    return .unknown;
}

// ============================================================================
// Backoff Counters
// ============================================================================

/// Backoff counter for adaptive optimization
pub const BackoffCounter = packed struct {
    value: u16,
    backoff: u8,
    _reserved: u8 = 0,

    /// Create initial warmup counter
    pub fn warmup() BackoffCounter {
        return .{
            .value = 50, // Default warmup threshold
            .backoff = 1,
        };
    }

    /// Create initial jump backoff counter
    pub fn jumpBackoff() BackoffCounter {
        return .{
            .value = 16,
            .backoff = 1,
        };
    }

    /// Create unreachable counter (disabled)
    pub fn unreachable() BackoffCounter {
        return .{
            .value = 0,
            .backoff = 255,
        };
    }

    /// Decrement counter, returns true if threshold reached
    pub fn decrement(self: *BackoffCounter) bool {
        if (self.value == 0) return true;
        self.value -= 1;
        return self.value == 0;
    }

    /// Reset with backoff
    pub fn reset(self: *BackoffCounter) void {
        self.value = @as(u16, 1) << @min(self.backoff, 15);
        if (self.backoff < 255) {
            self.backoff += 1;
        }
    }

    /// Check if counter is disabled
    pub fn isDisabled(self: BackoffCounter) bool {
        return self.backoff == 255;
    }
};

// ============================================================================
// Specialization Cache
// ============================================================================

/// Cache entry for specialized instructions
pub const CacheEntry = struct {
    /// Cached type version
    type_version: u32 = 0,
    /// Cached keys version (for dicts)
    keys_version: u32 = 0,
    /// Cached index/hint
    index: u16 = 0,
    /// Specialized opcode
    specialized_op: u8 = 0,
    /// Flags
    flags: CacheFlags = .{},
};

/// Cache entry flags
pub const CacheFlags = packed struct {
    /// Entry is valid
    valid: bool = false,
    /// Entry uses inline cache
    inline_cache: bool = false,
    /// Entry uses split keys
    split_keys: bool = false,
    /// Entry is for method
    is_method: bool = false,
    _reserved: u4 = 0,
};

// ============================================================================
// Instruction Specialization
// ============================================================================

/// Specialized opcode variants
pub const SpecializedOp = enum(u8) {
    // Load attr specializations
    LOAD_ATTR_INSTANCE_VALUE = 100,
    LOAD_ATTR_MODULE = 101,
    LOAD_ATTR_WITH_HINT = 102,
    LOAD_ATTR_SLOT = 103,
    LOAD_ATTR_CLASS = 104,
    LOAD_ATTR_PROPERTY = 105,
    LOAD_ATTR_GETATTRIBUTE_OVERRIDDEN = 106,
    LOAD_ATTR_METHOD_WITH_VALUES = 107,
    LOAD_ATTR_METHOD_NO_DICT = 108,
    LOAD_ATTR_METHOD_LAZY_DICT = 109,
    LOAD_ATTR_NONDESCRIPTOR_WITH_VALUES = 110,
    LOAD_ATTR_NONDESCRIPTOR_NO_DICT = 111,

    // Store attr specializations
    STORE_ATTR_INSTANCE_VALUE = 120,
    STORE_ATTR_WITH_HINT = 121,
    STORE_ATTR_SLOT = 122,

    // Binary op specializations
    BINARY_OP_ADD_INT = 130,
    BINARY_OP_ADD_FLOAT = 131,
    BINARY_OP_ADD_UNICODE = 132,
    BINARY_OP_SUBTRACT_INT = 133,
    BINARY_OP_SUBTRACT_FLOAT = 134,
    BINARY_OP_MULTIPLY_INT = 135,
    BINARY_OP_MULTIPLY_FLOAT = 136,
    BINARY_OP_INPLACE_ADD_UNICODE = 137,

    // Compare specializations
    COMPARE_OP_INT = 140,
    COMPARE_OP_FLOAT = 141,
    COMPARE_OP_STR = 142,

    // Subscript specializations
    BINARY_SUBSCR_LIST_INT = 150,
    BINARY_SUBSCR_TUPLE_INT = 151,
    BINARY_SUBSCR_DICT = 152,
    BINARY_SUBSCR_STR_INT = 153,
    STORE_SUBSCR_LIST_INT = 154,
    STORE_SUBSCR_DICT = 155,

    // Call specializations
    CALL_PY_EXACT_ARGS = 160,
    CALL_PY_WITH_DEFAULTS = 161,
    CALL_PY_GENERAL = 162,
    CALL_BUILTIN_CLASS = 163,
    CALL_BUILTIN_O = 164,
    CALL_BUILTIN_FAST = 165,
    CALL_BUILTIN_FAST_WITH_KEYWORDS = 166,
    CALL_LEN = 167,
    CALL_ISINSTANCE = 168,
    CALL_METHOD_DESCRIPTOR_O = 169,
    CALL_METHOD_DESCRIPTOR_FAST = 170,
    CALL_METHOD_DESCRIPTOR_NOARGS = 171,
    CALL_ALLOC_AND_ENTER_INIT = 172,
    CALL_BOUND_METHOD_EXACT_ARGS = 173,

    // Unpack specializations
    UNPACK_SEQUENCE_TWO_TUPLE = 180,
    UNPACK_SEQUENCE_TUPLE = 181,
    UNPACK_SEQUENCE_LIST = 182,

    // For iter specializations
    FOR_ITER_LIST = 190,
    FOR_ITER_TUPLE = 191,
    FOR_ITER_RANGE = 192,
    FOR_ITER_GEN = 193,

    // To bool specializations
    TO_BOOL_BOOL = 200,
    TO_BOOL_INT = 201,
    TO_BOOL_STR = 202,
    TO_BOOL_NONE = 203,
    TO_BOOL_LIST = 204,
    TO_BOOL_ALWAYS_TRUE = 205,

    // Contains specializations
    CONTAINS_OP_SET = 210,
    CONTAINS_OP_DICT = 211,

    // Load global specializations
    LOAD_GLOBAL_MODULE = 220,
    LOAD_GLOBAL_BUILTIN = 221,

    // Send specializations
    SEND_GEN = 230,

    // Generic (not specialized)
    GENERIC = 255,
};

/// Specialization context
pub const SpecializationContext = struct {
    /// Instruction pointer
    ip: u32,
    /// Original opcode
    opcode: u8,
    /// Operand
    oparg: u32,
    /// Cache pointer
    cache: ?*CacheEntry,
    /// Left operand type (for binary ops)
    lhs_type: TypeId = .unknown,
    /// Right operand type (for binary ops)
    rhs_type: TypeId = .unknown,
    /// Object type (for attr access)
    obj_type: TypeId = .unknown,
};

// ============================================================================
// Specialization Functions
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

/// Specialize LOAD_GLOBAL instruction
pub fn specializeLoadGlobal(is_builtin: bool) SpecializedOp {
    return if (is_builtin) .LOAD_GLOBAL_BUILTIN else .LOAD_GLOBAL_MODULE;
}

// ============================================================================
// Code Quickening
// ============================================================================

/// Code unit (opcode + arg)
pub const CodeUnit = packed struct {
    op: u8,
    arg: u8,
};

/// Quicken bytecode - initialize warmup counters
pub fn quickenCode(instructions: []CodeUnit, enable_counters: bool) void {
    const jump_counter = if (enable_counters) BackoffCounter.jumpBackoff() else BackoffCounter.unreachable();
    const adaptive_counter = if (enable_counters) BackoffCounter.warmup() else BackoffCounter.unreachable();

    var i: usize = 0;
    var oparg: u32 = 0;

    while (i < instructions.len -| 1) : (i += 1) {
        const opcode = instructions[i].op;
        const caches = getOpcodeCaches(opcode);
        oparg = (oparg << 8) | instructions[i].arg;

        if (caches > 0) {
            // Initialize cache based on opcode
            const counter: BackoffCounter = switch (opcode) {
                // JUMP_BACKWARD
                140 => jump_counter,
                // POP_JUMP_IF_* variants
                114, 115, 128, 129 => blk: {
                    // Set alternating pattern for branch prediction
                    const cache_ptr = @as(*u16, @ptrCast(&instructions[i + 1]));
                    cache_ptr.* = 0x5555;
                    break :blk adaptive_counter;
                },
                else => adaptive_counter,
            };

            // Store counter in next instruction slot
            const counter_ptr = @as(*BackoffCounter, @ptrCast(&instructions[i + 1]));
            counter_ptr.* = counter;

            i += caches;
        }

        // Reset oparg after non-EXTENDED_ARG
        if (opcode != 144) { // EXTENDED_ARG
            oparg = 0;
        }
    }
}

/// Get number of cache entries for opcode
fn getOpcodeCaches(opcode: u8) u8 {
    return switch (opcode) {
        // LOAD_ATTR
        106 => 9,
        // STORE_ATTR
        95 => 4,
        // LOAD_GLOBAL
        116 => 4,
        // BINARY_OP
        122 => 1,
        // COMPARE_OP
        107 => 1,
        // BINARY_SUBSCR
        25 => 1,
        // STORE_SUBSCR
        60 => 1,
        // CALL
        171 => 3,
        // FOR_ITER
        68 => 1,
        // JUMP_BACKWARD
        140 => 1,
        // POP_JUMP_IF variants
        114, 115, 128, 129 => 1,
        else => 0,
    };
}

// ============================================================================
// Specialization Statistics
// ============================================================================

/// Statistics for specialization tracking
pub const SpecializationStats = struct {
    /// Number of successful specializations
    successes: u64 = 0,
    /// Number of deoptimizations
    deoptimizations: u64 = 0,
    /// Failure counts by reason
    failures: [32]u64 = [_]u64{0} ** 32,

    /// Record successful specialization
    pub fn recordSuccess(self: *SpecializationStats) void {
        self.successes += 1;
    }

    /// Record deoptimization
    pub fn recordDeopt(self: *SpecializationStats) void {
        self.deoptimizations += 1;
    }

    /// Record failure
    pub fn recordFailure(self: *SpecializationStats, reason: u8) void {
        if (reason < 32) {
            self.failures[reason] += 1;
        }
    }

    /// Get success rate
    pub fn getSuccessRate(self: *const SpecializationStats) f64 {
        const total = self.successes + self.deoptimizations;
        if (total == 0) return 0.0;
        return @as(f64, @floatFromInt(self.successes)) / @as(f64, @floatFromInt(total));
    }

    /// Reset statistics
    pub fn reset(self: *SpecializationStats) void {
        self.successes = 0;
        self.deoptimizations = 0;
        self.failures = [_]u64{0} ** 32;
    }
};

// ============================================================================
// Specializer State
// ============================================================================

/// Main specializer
pub const Specializer = struct {
    const Self = @This();

    /// Memory allocator
    allocator: Allocator,
    /// Statistics
    stats: SpecializationStats = .{},
    /// Enable specialization
    enabled: bool = true,
    /// Minimum execution count before specializing
    threshold: u32 = 50,

    /// Create new specializer
    pub fn init(allocator: Allocator) Self {
        return Self{
            .allocator = allocator,
        };
    }

    /// Specialize an instruction
    pub fn specialize(self: *Self, ctx: *SpecializationContext) SpecializedOp {
        if (!self.enabled) return .GENERIC;

        const result: SpecializedOp = switch (ctx.opcode) {
            106 => specializeLoadAttr(ctx), // LOAD_ATTR
            95 => specializeStoreAttr(ctx), // STORE_ATTR
            122 => specializeBinaryOp(ctx), // BINARY_OP
            107 => specializeCompareOp(ctx), // COMPARE_OP
            25 => specializeBinarySubscr(ctx), // BINARY_SUBSCR
            60 => specializeStoreSubscr(ctx), // STORE_SUBSCR
            92 => specializeUnpackSequence(ctx), // UNPACK_SEQUENCE
            else => .GENERIC,
        };

        if (result != .GENERIC) {
            self.stats.recordSuccess();
        }

        return result;
    }

    /// Record deoptimization
    pub fn deoptimize(self: *Self, _: *SpecializationContext) void {
        self.stats.recordDeopt();
    }

    /// Get statistics
    pub fn getStats(self: *const Self) SpecializationStats {
        return self.stats;
    }

    /// Reset statistics
    pub fn resetStats(self: *Self) void {
        self.stats.reset();
    }
};

// ============================================================================
// Module Initialization
// ============================================================================

var initialized: bool = false;
var global_specializer: ?*Specializer = null;

/// Initialize the specialize module
pub fn init() void {
    if (initialized) return;
    initialized = true;
}

/// Get global specializer instance
pub fn getSpecializer() ?*Specializer {
    return global_specializer;
}

/// Set global specializer instance
pub fn setSpecializer(s: *Specializer) void {
    global_specializer = s;
}

/// Reset module state
pub fn reset() void {
    global_specializer = null;
    initialized = false;
}

// ============================================================================
// Tests
// ============================================================================

test "backoff counter" {
    var counter = BackoffCounter.warmup();
    try std.testing.expectEqual(@as(u16, 50), counter.value);

    // Decrement until threshold
    while (!counter.decrement()) {}
    try std.testing.expectEqual(@as(u16, 0), counter.value);

    // Reset with backoff
    counter.reset();
    try std.testing.expect(counter.value > 0);
    try std.testing.expectEqual(@as(u8, 2), counter.backoff);
}

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

test "specializer integration" {
    const allocator = std.testing.allocator;

    var specializer = Specializer.init(allocator);

    var ctx = SpecializationContext{
        .ip = 0,
        .opcode = 122, // BINARY_OP
        .oparg = 0, // Add
        .cache = null,
        .lhs_type = .float_type,
        .rhs_type = .float_type,
    };

    const result = specializer.specialize(&ctx);
    try std.testing.expectEqual(SpecializedOp.BINARY_OP_ADD_FLOAT, result);
    try std.testing.expectEqual(@as(u64, 1), specializer.stats.successes);
}

test "quicken code" {
    var instructions = [_]CodeUnit{
        .{ .op = 106, .arg = 0 }, // LOAD_ATTR
        .{ .op = 0, .arg = 0 }, // cache slot 1
        .{ .op = 0, .arg = 0 }, // cache slot 2
        .{ .op = 0, .arg = 0 }, // cache slot 3
        .{ .op = 0, .arg = 0 }, // cache slot 4
        .{ .op = 0, .arg = 0 }, // cache slot 5
        .{ .op = 0, .arg = 0 }, // cache slot 6
        .{ .op = 0, .arg = 0 }, // cache slot 7
        .{ .op = 0, .arg = 0 }, // cache slot 8
        .{ .op = 0, .arg = 0 }, // cache slot 9
        .{ .op = 1, .arg = 0 }, // POP_TOP (end marker)
    };

    quickenCode(&instructions, true);

    // First cache slot should have counter initialized
    const counter_ptr = @as(*BackoffCounter, @ptrCast(&instructions[1]));
    try std.testing.expect(counter_ptr.value > 0);
}

test "unreachable counter" {
    const counter = BackoffCounter.unreachable();
    try std.testing.expect(counter.isDisabled());
    try std.testing.expectEqual(@as(u8, 255), counter.backoff);
}

test "statistics tracking" {
    var stats = SpecializationStats{};

    stats.recordSuccess();
    stats.recordSuccess();
    stats.recordDeopt();

    try std.testing.expectEqual(@as(u64, 2), stats.successes);
    try std.testing.expectEqual(@as(u64, 1), stats.deoptimizations);

    const rate = stats.getSuccessRate();
    try std.testing.expect(rate > 0.6 and rate < 0.7);
}
