/// Binary and Compare operations for ceval
/// Mirrors part of cpython/Python/ceval.c

/// Binary operation codes
pub const BinaryOp = enum(u8) {
    add = 0,
    sub = 1,
    mult = 2,
    matmult = 3,
    div = 4,
    mod = 5,
    pow = 6,
    lshift = 7,
    rshift = 8,
    or_ = 9,
    xor = 10,
    and_ = 11,
    floordiv = 12,
    truediv = 13,
    inplace_add = 14,
    inplace_sub = 15,
    inplace_mult = 16,
    inplace_matmult = 17,
    inplace_div = 18,
    inplace_mod = 19,
    inplace_pow = 20,
    inplace_lshift = 21,
    inplace_rshift = 22,
    inplace_or = 23,
    inplace_xor = 24,
    inplace_and = 25,
    inplace_floordiv = 26,
    inplace_truediv = 27,
};

/// Compare operation codes
pub const CompareOp = enum(u8) {
    lt = 0,
    le = 1,
    eq = 2,
    ne = 3,
    gt = 4,
    ge = 5,
};

/// Conversion function types for format strings
pub const ConversionFunc = enum(u8) {
    none = 0,
    str = 's',
    repr = 'r',
    ascii = 'a',
};
