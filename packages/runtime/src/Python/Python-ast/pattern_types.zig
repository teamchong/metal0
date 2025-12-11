/// Pattern types for match statements
/// Mirrors cpython/Python/Python-ast.c (pattern matching)

/// Pattern types
pub const PatternKind = enum {
    MatchValue,
    MatchSingleton,
    MatchSequence,
    MatchMapping,
    MatchClass,
    MatchStar,
    MatchAs,
    MatchOr,
};

/// Pattern node
pub const Pattern = struct {
    kind: PatternKind,
    lineno: i32 = 0,
    col_offset: i32 = 0,
    end_lineno: ?i32 = null,
    end_col_offset: ?i32 = null,
};
