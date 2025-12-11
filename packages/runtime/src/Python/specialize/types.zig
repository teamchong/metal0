/// types - Specialization Type Definitions
/// Failure codes, type IDs, and core structures for bytecode specialization.

const std = @import("std");

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

// ============================================================================
// PyObject Type Inference
// ============================================================================

/// PyObject header structure for type checking
/// Mirrors the ob_type field in PyObject
pub const PyObjectHeader = extern struct {
    ob_refcnt: isize,
    ob_type: ?*anyopaque, // PyTypeObject pointer
};

/// Known type object pointers (set during initialization)
var PyLong_Type_ptr: ?*anyopaque = null;
var PyFloat_Type_ptr: ?*anyopaque = null;
var PyUnicode_Type_ptr: ?*anyopaque = null;
var PyList_Type_ptr: ?*anyopaque = null;
var PyDict_Type_ptr: ?*anyopaque = null;
var PyTuple_Type_ptr: ?*anyopaque = null;
var PyBool_Type_ptr: ?*anyopaque = null;
var PyNone_Type_ptr: ?*anyopaque = null;

/// Initialize type pointers (called during runtime setup)
pub fn initTypePointers(
    long_type: ?*anyopaque,
    float_type: ?*anyopaque,
    unicode_type: ?*anyopaque,
    list_type: ?*anyopaque,
    dict_type: ?*anyopaque,
    tuple_type: ?*anyopaque,
    bool_type: ?*anyopaque,
    none_type: ?*anyopaque,
) void {
    PyLong_Type_ptr = long_type;
    PyFloat_Type_ptr = float_type;
    PyUnicode_Type_ptr = unicode_type;
    PyList_Type_ptr = list_type;
    PyDict_Type_ptr = dict_type;
    PyTuple_Type_ptr = tuple_type;
    PyBool_Type_ptr = bool_type;
    PyNone_Type_ptr = none_type;
}

/// Infer type ID from runtime value by checking ob_type
pub fn inferTypeId(value: ?*anyopaque) TypeId {
    if (value == null) return .none;

    // Read the object header to get type pointer
    const header: *const PyObjectHeader = @ptrCast(@alignCast(value));
    const type_ptr = header.ob_type;

    // Check against known type pointers
    if (type_ptr == PyNone_Type_ptr) return .none;
    if (type_ptr == PyBool_Type_ptr) return .bool_type;
    if (type_ptr == PyLong_Type_ptr) return .int_small;
    if (type_ptr == PyFloat_Type_ptr) return .float_type;
    if (type_ptr == PyUnicode_Type_ptr) return .str_type;
    if (type_ptr == PyList_Type_ptr) return .list_type;
    if (type_ptr == PyDict_Type_ptr) return .dict_type;
    if (type_ptr == PyTuple_Type_ptr) return .tuple_type;

    // Unknown type - could extend with more type checks
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
    pub fn @"unreachable"() BackoffCounter {
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
// Cache Structures
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

test "unreachable counter" {
    const counter = BackoffCounter.@"unreachable"();
    try std.testing.expect(counter.isDisabled());
    try std.testing.expectEqual(@as(u8, 255), counter.backoff);
}
