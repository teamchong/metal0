/// Docstring Extraction
/// Extracts docstrings from statement lists

const constant_folding = @import("constant_folding.zig");

/// Extract docstring from statement list
pub fn extractDocstring(stmts: []const Statement) ?[]const u8 {
    if (stmts.len == 0) return null;

    // First statement must be an expression statement with a string literal
    const first = stmts[0];
    if (first.kind != .expr) return null;

    if (first.expr_value) |expr| {
        if (expr.kind == .constant) {
            if (expr.const_value) |cv| {
                switch (cv) {
                    .str_val => |s| return s,
                    else => return null,
                }
            }
        }
    }
    return null;
}

/// Statement placeholder (minimal for docstring extraction)
pub const Statement = struct {
    kind: StmtKind,
    expr_value: ?*const Expression = null,
};

pub const StmtKind = enum {
    expr,
    assign,
    other,
};

pub const Expression = struct {
    kind: ExprKind,
    const_value: ?constant_folding.ConstValue = null,
};

pub const ExprKind = enum {
    constant,
    name,
    call,
    other,
};
