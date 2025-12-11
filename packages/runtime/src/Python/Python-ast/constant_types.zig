/// Constant value types
/// Mirrors cpython/Python/Python-ast.c (constant literals)

/// Constant value
pub const Constant = union(enum) {
    none: void,
    true_val: void,
    false_val: void,
    ellipsis: void,
    int_val: i64,
    float_val: f64,
    complex_val: struct { real: f64, imag: f64 },
    str_val: []const u8,
    bytes_val: []const u8,
    tuple_val: []Constant,
    frozenset_val: []Constant,
};
