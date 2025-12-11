/// AST Unparse Types
/// Core types for AST unparsing

const std = @import("std");

// ============================================================================
// Priority Levels for Operator Precedence
// ============================================================================

/// Operator precedence levels for proper parenthesization
pub const Precedence = enum(u8) {
    PR_TUPLE = 0,
    PR_TEST = 1, // 'if'-'else', 'lambda'
    PR_OR = 2, // 'or'
    PR_AND = 3, // 'and'
    PR_NOT = 4, // 'not'
    PR_CMP = 5, // comparisons
    PR_EXPR = 6, // same as PR_BOR
    PR_BXOR = 7, // '^'
    PR_BAND = 8, // '&'
    PR_SHIFT = 9, // '<<', '>>'
    PR_ARITH = 10, // '+', '-'
    PR_TERM = 11, // '*', '@', '/', '%', '//'
    PR_FACTOR = 12, // unary '+', '-', '~'
    PR_POWER = 13, // '**'
    PR_AWAIT = 14, // 'await'
    PR_ATOM = 15,

    // Alias for bit-or (same value as EXPR)
    pub const PR_BOR = Precedence.PR_EXPR;
};

// ============================================================================
// AST Node Types (minimal for unparsing)
// ============================================================================

/// Expression kinds
pub const ExprKind = enum {
    // Literals
    constant,
    name,

    // Operations
    bool_op,
    bin_op,
    unary_op,
    compare,

    // Containers
    list,
    tuple,
    dict,
    set,

    // Comprehensions
    list_comp,
    set_comp,
    dict_comp,
    generator,

    // Subscripts and attributes
    attribute,
    subscript,
    slice,

    // Calls
    call,

    // Conditionals
    if_exp,
    lambda,

    // Special
    starred,
    named_expr, // := walrus operator
    await,
    yield,
    yield_from,

    // f-strings
    formatted_value,
    joined_str,
};

/// Keyword argument
pub const Keyword = struct {
    name: ?[]const u8, // null for **kwargs
    value: []const u8,
};

/// Constant value types
pub const ConstantValue = union(enum) {
    none: void,
    true_val: void,
    false_val: void,
    ellipsis: void,
    int_val: i64,
    float_val: f64,
    str_val: []const u8,
    bytes_val: []const u8,
};
