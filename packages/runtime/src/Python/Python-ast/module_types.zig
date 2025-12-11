/// Module and top-level AST types
/// Mirrors cpython/Python/Python-ast.c (module-level constructs)

const Statement = @import("statement_types.zig").Statement;
const TypeIgnore = @import("supporting_types.zig").TypeIgnore;

/// Module types (top-level)
pub const ModKind = enum {
    Module,
    Interactive,
    Expression,
    FunctionType,
};

/// Module node
pub const Module = struct {
    kind: ModKind,
    body: []Statement,
    type_ignores: []TypeIgnore = &[_]TypeIgnore{},
};
