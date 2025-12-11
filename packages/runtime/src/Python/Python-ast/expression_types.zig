/// Expression types for AST
/// Mirrors cpython/Python/Python-ast.c (expression nodes)

/// Expression types
pub const ExprKind = enum {
    BoolOp,
    NamedExpr,
    BinOp,
    UnaryOp,
    Lambda,
    IfExp,
    Dict,
    Set,
    ListComp,
    SetComp,
    DictComp,
    GeneratorExp,
    Await,
    Yield,
    YieldFrom,
    Compare,
    Call,
    FormattedValue,
    JoinedStr,
    Constant,
    Attribute,
    Subscript,
    Starred,
    Name,
    List,
    Tuple,
    Slice,
};

/// Expression node
pub const Expr = struct {
    kind: ExprKind,
    lineno: i32 = 0,
    col_offset: i32 = 0,
    end_lineno: ?i32 = null,
    end_col_offset: ?i32 = null,
    ctx: ExprContext = .Load,
};

/// Expression context
pub const ExprContext = enum {
    Load,
    Store,
    Del,
};
