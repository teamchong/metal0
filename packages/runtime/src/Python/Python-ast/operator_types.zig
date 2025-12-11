/// Operator types for AST
/// Mirrors cpython/Python/Python-ast.c (operator enums)

/// Binary operators
pub const Operator = enum {
    Add,
    Sub,
    Mult,
    MatMult,
    Div,
    Mod,
    Pow,
    LShift,
    RShift,
    BitOr,
    BitXor,
    BitAnd,
    FloorDiv,
};

/// Unary operators
pub const UnaryOp = enum {
    Invert,
    Not,
    UAdd,
    USub,
};

/// Boolean operators
pub const BoolOp = enum {
    And,
    Or,
};

/// Comparison operators
pub const CmpOp = enum {
    Eq,
    NotEq,
    Lt,
    LtE,
    Gt,
    GtE,
    Is,
    IsNot,
    In,
    NotIn,
};
