/// Supporting types for AST nodes
/// Mirrors cpython/Python/Python-ast.c (helper structures)

const Expr = @import("expression_types.zig").Expr;
const Statement = @import("statement_types.zig").Statement;
const Pattern = @import("pattern_types.zig").Pattern;

/// Function arguments
pub const Arguments = struct {
    posonlyargs: []Arg = &[_]Arg{},
    args: []Arg = &[_]Arg{},
    vararg: ?*Arg = null,
    kwonlyargs: []Arg = &[_]Arg{},
    kw_defaults: []?*Expr = &[_]?*Expr{},
    kwarg: ?*Arg = null,
    defaults: []Expr = &[_]Expr{},
};

/// Function argument
pub const Arg = struct {
    arg: []const u8,
    annotation: ?*Expr = null,
    type_comment: ?[]const u8 = null,
    lineno: i32 = 0,
    col_offset: i32 = 0,
    end_lineno: ?i32 = null,
    end_col_offset: ?i32 = null,
};

/// Keyword argument
pub const Keyword = struct {
    arg: ?[]const u8 = null, // null for **kwargs
    value: *Expr,
    lineno: i32 = 0,
    col_offset: i32 = 0,
    end_lineno: ?i32 = null,
    end_col_offset: ?i32 = null,
};

/// Import alias
pub const Alias = struct {
    name: []const u8,
    asname: ?[]const u8 = null,
    lineno: i32 = 0,
    col_offset: i32 = 0,
    end_lineno: ?i32 = null,
    end_col_offset: ?i32 = null,
};

/// With item
pub const WithItem = struct {
    context_expr: *Expr,
    optional_vars: ?*Expr = null,
};

/// Match case
pub const MatchCase = struct {
    pattern: *Pattern,
    guard: ?*Expr = null,
    body: []Statement,
};

/// Exception handler
pub const ExceptHandler = struct {
    type_: ?*Expr = null,
    name: ?[]const u8 = null,
    body: []Statement,
    lineno: i32 = 0,
    col_offset: i32 = 0,
    end_lineno: ?i32 = null,
    end_col_offset: ?i32 = null,
};

/// Type ignore
pub const TypeIgnore = struct {
    lineno: i32,
    tag: []const u8,
};

/// Type parameter (PEP 695)
pub const TypeParam = struct {
    kind: TypeParamKind,
    name: []const u8,
    bound: ?*Expr = null,
    default_value: ?*Expr = null,
    lineno: i32 = 0,
    col_offset: i32 = 0,
    end_lineno: ?i32 = null,
    end_col_offset: ?i32 = null,
};

pub const TypeParamKind = enum {
    TypeVar,
    ParamSpec,
    TypeVarTuple,
};
