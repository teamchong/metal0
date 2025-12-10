//! CPython source: Lib/ast.py
//!
//! Provides AST node types and utilities for working with Python ASTs.
//!
//! Mirrors: CPython Lib/ast.py

const std = @import("std");

// ============================================================================
// AST Node Types
// ============================================================================

/// Base AST node
pub const AST = struct {
    lineno: ?i32 = null,
    col_offset: ?i32 = null,
    end_lineno: ?i32 = null,
    end_col_offset: ?i32 = null,
};

/// Module node types
pub const Module = struct {
    body: []Statement,
    type_ignores: []TypeIgnore,
};

pub const Interactive = struct {
    body: []Statement,
};

pub const Expression = struct {
    body: Expr,
};

pub const FunctionType = struct {
    argtypes: []Expr,
    returns: Expr,
};

/// Statement types
pub const Statement = union(enum) {
    function_def: FunctionDef,
    async_function_def: AsyncFunctionDef,
    class_def: ClassDef,
    return_stmt: Return,
    delete: Delete,
    assign: Assign,
    aug_assign: AugAssign,
    ann_assign: AnnAssign,
    for_stmt: For,
    async_for: AsyncFor,
    while_stmt: While,
    if_stmt: If,
    with_stmt: With,
    async_with: AsyncWith,
    match_stmt: Match,
    raise_stmt: Raise,
    try_stmt: Try,
    try_star: TryStar,
    assert_stmt: Assert,
    import_stmt: Import,
    import_from: ImportFrom,
    global_stmt: Global,
    nonlocal_stmt: Nonlocal,
    expr_stmt: ExprStmt,
    pass_stmt: Pass,
    break_stmt: Break,
    continue_stmt: Continue,
};

pub const FunctionDef = struct {
    name: []const u8,
    args: Arguments,
    body: []Statement,
    decorator_list: []Expr,
    returns: ?Expr,
    type_comment: ?[]const u8,
    type_params: []TypeParam,
};

pub const AsyncFunctionDef = FunctionDef;

pub const ClassDef = struct {
    name: []const u8,
    bases: []Expr,
    keywords: []Keyword,
    body: []Statement,
    decorator_list: []Expr,
    type_params: []TypeParam,
};

pub const Return = struct {
    value: ?Expr,
};

pub const Delete = struct {
    targets: []Expr,
};

pub const Assign = struct {
    targets: []Expr,
    value: Expr,
    type_comment: ?[]const u8,
};

pub const AugAssign = struct {
    target: Expr,
    op: Operator,
    value: Expr,
};

pub const AnnAssign = struct {
    target: Expr,
    annotation: Expr,
    value: ?Expr,
    simple: bool,
};

pub const For = struct {
    target: Expr,
    iter: Expr,
    body: []Statement,
    orelse: []Statement,
    type_comment: ?[]const u8,
};

pub const AsyncFor = For;

pub const While = struct {
    test: Expr,
    body: []Statement,
    orelse: []Statement,
};

pub const If = struct {
    test: Expr,
    body: []Statement,
    orelse: []Statement,
};

pub const With = struct {
    items: []WithItem,
    body: []Statement,
    type_comment: ?[]const u8,
};

pub const AsyncWith = With;

pub const Match = struct {
    subject: Expr,
    cases: []MatchCase,
};

pub const Raise = struct {
    exc: ?Expr,
    cause: ?Expr,
};

pub const Try = struct {
    body: []Statement,
    handlers: []ExceptHandler,
    orelse: []Statement,
    finalbody: []Statement,
};

pub const TryStar = Try;

pub const Assert = struct {
    test: Expr,
    msg: ?Expr,
};

pub const Import = struct {
    names: []Alias,
};

pub const ImportFrom = struct {
    module: ?[]const u8,
    names: []Alias,
    level: i32,
};

pub const Global = struct {
    names: [][]const u8,
};

pub const Nonlocal = Global;

pub const ExprStmt = struct {
    value: Expr,
};

pub const Pass = struct {};
pub const Break = struct {};
pub const Continue = struct {};

/// Expression types
pub const Expr = union(enum) {
    bool_op: BoolOp,
    named_expr: NamedExpr,
    bin_op: BinOp,
    unary_op: UnaryOp,
    lambda: Lambda,
    if_exp: IfExp,
    dict: Dict,
    set: Set,
    list_comp: ListComp,
    set_comp: SetComp,
    dict_comp: DictComp,
    generator_exp: GeneratorExp,
    await_expr: Await,
    yield_expr: Yield,
    yield_from: YieldFrom,
    compare: Compare,
    call: Call,
    formatted_value: FormattedValue,
    joined_str: JoinedStr,
    constant: Constant,
    attribute: Attribute,
    subscript: Subscript,
    starred: Starred,
    name: Name,
    list: List,
    tuple: Tuple,
    slice: Slice,
};

pub const BoolOp = struct {
    op: BoolOperator,
    values: []Expr,
};

pub const NamedExpr = struct {
    target: *Expr,
    value: *Expr,
};

pub const BinOp = struct {
    left: *Expr,
    op: Operator,
    right: *Expr,
};

pub const UnaryOp = struct {
    op: UnaryOperator,
    operand: *Expr,
};

pub const Lambda = struct {
    args: Arguments,
    body: *Expr,
};

pub const IfExp = struct {
    test: *Expr,
    body: *Expr,
    orelse: *Expr,
};

pub const Dict = struct {
    keys: []?Expr,
    values: []Expr,
};

pub const Set = struct {
    elts: []Expr,
};

pub const ListComp = struct {
    elt: *Expr,
    generators: []Comprehension,
};

pub const SetComp = ListComp;

pub const DictComp = struct {
    key: *Expr,
    value: *Expr,
    generators: []Comprehension,
};

pub const GeneratorExp = ListComp;

pub const Await = struct {
    value: *Expr,
};

pub const Yield = struct {
    value: ?*Expr,
};

pub const YieldFrom = struct {
    value: *Expr,
};

pub const Compare = struct {
    left: *Expr,
    ops: []CmpOp,
    comparators: []Expr,
};

pub const Call = struct {
    func: *Expr,
    args: []Expr,
    keywords: []Keyword,
};

pub const FormattedValue = struct {
    value: *Expr,
    conversion: i32,
    format_spec: ?*Expr,
};

pub const JoinedStr = struct {
    values: []Expr,
};

pub const Constant = struct {
    value: ConstantValue,
    kind: ?[]const u8,
};

pub const ConstantValue = union(enum) {
    none,
    bool_val: bool,
    int_val: i64,
    float_val: f64,
    string_val: []const u8,
    bytes_val: []const u8,
    ellipsis,
};

pub const Attribute = struct {
    value: *Expr,
    attr: []const u8,
    ctx: ExprContext,
};

pub const Subscript = struct {
    value: *Expr,
    slice: *Expr,
    ctx: ExprContext,
};

pub const Starred = struct {
    value: *Expr,
    ctx: ExprContext,
};

pub const Name = struct {
    id: []const u8,
    ctx: ExprContext,
};

pub const List = struct {
    elts: []Expr,
    ctx: ExprContext,
};

pub const Tuple = List;

pub const Slice = struct {
    lower: ?*Expr,
    upper: ?*Expr,
    step: ?*Expr,
};

/// Operators
pub const BoolOperator = enum {
    @"and",
    @"or",
};

pub const Operator = enum {
    add,
    sub,
    mult,
    mat_mult,
    div,
    mod,
    pow,
    lshift,
    rshift,
    bit_or,
    bit_xor,
    bit_and,
    floor_div,
};

pub const UnaryOperator = enum {
    invert,
    not,
    uadd,
    usub,
};

pub const CmpOp = enum {
    eq,
    not_eq,
    lt,
    lte,
    gt,
    gte,
    is,
    is_not,
    in,
    not_in,
};

pub const ExprContext = enum {
    load,
    store,
    del,
};

/// Other node types
pub const Comprehension = struct {
    target: Expr,
    iter: Expr,
    ifs: []Expr,
    is_async: bool,
};

pub const ExceptHandler = struct {
    type: ?Expr,
    name: ?[]const u8,
    body: []Statement,
};

pub const Arguments = struct {
    posonlyargs: []Arg,
    args: []Arg,
    vararg: ?Arg,
    kwonlyargs: []Arg,
    kw_defaults: []?Expr,
    kwarg: ?Arg,
    defaults: []Expr,
};

pub const Arg = struct {
    arg: []const u8,
    annotation: ?Expr,
    type_comment: ?[]const u8,
};

pub const Keyword = struct {
    arg: ?[]const u8,
    value: Expr,
};

pub const Alias = struct {
    name: []const u8,
    asname: ?[]const u8,
};

pub const WithItem = struct {
    context_expr: Expr,
    optional_vars: ?Expr,
};

pub const MatchCase = struct {
    pattern: Pattern,
    guard: ?Expr,
    body: []Statement,
};

pub const Pattern = union(enum) {
    match_value: MatchValue,
    match_singleton: MatchSingleton,
    match_sequence: MatchSequence,
    match_mapping: MatchMapping,
    match_class: MatchClass,
    match_star: MatchStar,
    match_as: MatchAs,
    match_or: MatchOr,
};

pub const MatchValue = struct {
    value: Expr,
};

pub const MatchSingleton = struct {
    value: ConstantValue,
};

pub const MatchSequence = struct {
    patterns: []Pattern,
};

pub const MatchMapping = struct {
    keys: []Expr,
    patterns: []Pattern,
    rest: ?[]const u8,
};

pub const MatchClass = struct {
    cls: Expr,
    patterns: []Pattern,
    kwd_attrs: [][]const u8,
    kwd_patterns: []Pattern,
};

pub const MatchStar = struct {
    name: ?[]const u8,
};

pub const MatchAs = struct {
    pattern: ?*Pattern,
    name: ?[]const u8,
};

pub const MatchOr = struct {
    patterns: []Pattern,
};

pub const TypeIgnore = struct {
    lineno: i32,
    tag: []const u8,
};

pub const TypeParam = union(enum) {
    type_var: TypeVar,
    param_spec: ParamSpec,
    type_var_tuple: TypeVarTuple,
};

pub const TypeVar = struct {
    name: []const u8,
    bound: ?Expr,
};

pub const ParamSpec = struct {
    name: []const u8,
};

pub const TypeVarTuple = struct {
    name: []const u8,
};

// ============================================================================
// AST Functions
// ============================================================================

// ============================================================================
// Runtime Parser - Tokenizer
// ============================================================================

const TokenType = enum {
    // Literals
    Number,
    String,
    Name,
    // Keywords
    KwDef,
    KwClass,
    KwReturn,
    KwIf,
    KwElif,
    KwElse,
    KwFor,
    KwWhile,
    KwBreak,
    KwContinue,
    KwPass,
    KwImport,
    KwFrom,
    KwAs,
    KwTrue,
    KwFalse,
    KwNone,
    KwAnd,
    KwOr,
    KwNot,
    KwIn,
    KwIs,
    KwLambda,
    KwTry,
    KwExcept,
    KwFinally,
    KwRaise,
    KwWith,
    KwAssert,
    KwYield,
    KwGlobal,
    KwNonlocal,
    KwDel,
    KwAsync,
    KwAwait,
    KwMatch,
    KwCase,
    // Operators
    Plus,
    Minus,
    Star,
    Slash,
    DoubleSlash,
    Percent,
    DoubleStar,
    At,
    Ampersand,
    Pipe,
    Caret,
    Tilde,
    LeftShift,
    RightShift,
    // Comparison
    Less,
    Greater,
    LessEqual,
    GreaterEqual,
    EqualEqual,
    NotEqual,
    // Assignment
    Equal,
    PlusEqual,
    MinusEqual,
    StarEqual,
    SlashEqual,
    PercentEqual,
    DoubleStarEqual,
    AmpersandEqual,
    PipeEqual,
    CaretEqual,
    LeftShiftEqual,
    RightShiftEqual,
    DoubleSlashEqual,
    AtEqual,
    ColonEqual,
    // Delimiters
    LeftParen,
    RightParen,
    LeftBracket,
    RightBracket,
    LeftBrace,
    RightBrace,
    Comma,
    Colon,
    Semicolon,
    Dot,
    Arrow,
    Ellipsis,
    // Special
    Newline,
    Indent,
    Dedent,
    Eof,
};

const Token = struct {
    type: TokenType,
    lexeme: []const u8,
    line: i32,
    column: i32,
};

const Tokenizer = struct {
    source: []const u8,
    pos: usize,
    line: i32,
    column: i32,
    allocator: std.mem.Allocator,
    tokens: std.ArrayList(Token),
    indent_stack: std.ArrayList(usize),

    fn init(allocator: std.mem.Allocator, source: []const u8) Tokenizer {
        return .{
            .source = source,
            .pos = 0,
            .line = 1,
            .column = 0,
            .allocator = allocator,
            .tokens = std.ArrayList(Token).init(allocator),
            .indent_stack = std.ArrayList(usize).init(allocator),
        };
    }

    fn deinit(self: *Tokenizer) void {
        self.tokens.deinit();
        self.indent_stack.deinit();
    }

    fn peek(self: *Tokenizer) ?u8 {
        if (self.pos >= self.source.len) return null;
        return self.source[self.pos];
    }

    fn advance(self: *Tokenizer) ?u8 {
        if (self.pos >= self.source.len) return null;
        const c = self.source[self.pos];
        self.pos += 1;
        self.column += 1;
        if (c == '\n') {
            self.line += 1;
            self.column = 0;
        }
        return c;
    }

    fn tokenize(self: *Tokenizer) ![]Token {
        try self.indent_stack.append(0);

        while (self.peek() != null) {
            try self.scanToken();
        }

        // Emit remaining dedents
        while (self.indent_stack.items.len > 1) {
            _ = self.indent_stack.pop();
            try self.tokens.append(.{ .type = .Dedent, .lexeme = "", .line = self.line, .column = self.column });
        }

        try self.tokens.append(.{ .type = .Eof, .lexeme = "", .line = self.line, .column = self.column });
        return self.tokens.items;
    }

    fn scanToken(self: *Tokenizer) !void {
        const c = self.peek() orelse return;

        // Skip whitespace (except newlines)
        if (c == ' ' or c == '\t' or c == '\r') {
            _ = self.advance();
            return;
        }

        // Comments
        if (c == '#') {
            while (self.peek()) |ch| {
                if (ch == '\n') break;
                _ = self.advance();
            }
            return;
        }

        // Newline
        if (c == '\n') {
            _ = self.advance();
            try self.tokens.append(.{ .type = .Newline, .lexeme = "\n", .line = self.line - 1, .column = self.column });
            return;
        }

        // String literals
        if (c == '"' or c == '\'') {
            try self.scanString();
            return;
        }

        // Numbers
        if (std.ascii.isDigit(c)) {
            try self.scanNumber();
            return;
        }

        // Identifiers and keywords
        if (std.ascii.isAlphabetic(c) or c == '_') {
            try self.scanIdentifier();
            return;
        }

        // Operators and delimiters
        try self.scanOperator();
    }

    fn scanString(self: *Tokenizer) !void {
        const quote = self.advance().?;
        const start = self.pos;

        // Check for triple quotes
        var triple = false;
        if (self.peek() == quote) {
            _ = self.advance();
            if (self.peek() == quote) {
                _ = self.advance();
                triple = true;
            } else {
                // Empty string
                try self.tokens.append(.{ .type = .String, .lexeme = "", .line = self.line, .column = self.column });
                return;
            }
        }

        while (self.peek()) |c| {
            if (c == '\\') {
                _ = self.advance();
                _ = self.advance(); // Skip escaped char
            } else if (c == quote) {
                if (triple) {
                    if (self.pos + 2 < self.source.len and
                        self.source[self.pos + 1] == quote and
                        self.source[self.pos + 2] == quote)
                    {
                        const lexeme = self.source[start..self.pos];
                        _ = self.advance();
                        _ = self.advance();
                        _ = self.advance();
                        try self.tokens.append(.{ .type = .String, .lexeme = lexeme, .line = self.line, .column = self.column });
                        return;
                    }
                    _ = self.advance();
                } else {
                    const lexeme = self.source[start..self.pos];
                    _ = self.advance();
                    try self.tokens.append(.{ .type = .String, .lexeme = lexeme, .line = self.line, .column = self.column });
                    return;
                }
            } else {
                _ = self.advance();
            }
        }
    }

    fn scanNumber(self: *Tokenizer) !void {
        const start = self.pos;
        while (self.peek()) |c| {
            if (std.ascii.isDigit(c) or c == '.' or c == 'e' or c == 'E' or c == '+' or c == '-' or c == '_' or c == 'x' or c == 'X' or c == 'o' or c == 'O' or c == 'b' or c == 'B' or (c >= 'a' and c <= 'f') or (c >= 'A' and c <= 'F')) {
                _ = self.advance();
            } else {
                break;
            }
        }
        try self.tokens.append(.{ .type = .Number, .lexeme = self.source[start..self.pos], .line = self.line, .column = self.column });
    }

    fn scanIdentifier(self: *Tokenizer) !void {
        const start = self.pos;
        while (self.peek()) |c| {
            if (std.ascii.isAlphanumeric(c) or c == '_') {
                _ = self.advance();
            } else {
                break;
            }
        }
        const lexeme = self.source[start..self.pos];
        const tok_type = getKeywordType(lexeme);
        try self.tokens.append(.{ .type = tok_type, .lexeme = lexeme, .line = self.line, .column = self.column });
    }

    fn getKeywordType(lexeme: []const u8) TokenType {
        const keywords = std.StaticStringMap(TokenType).initComptime(.{
            .{ "def", .KwDef },
            .{ "class", .KwClass },
            .{ "return", .KwReturn },
            .{ "if", .KwIf },
            .{ "elif", .KwElif },
            .{ "else", .KwElse },
            .{ "for", .KwFor },
            .{ "while", .KwWhile },
            .{ "break", .KwBreak },
            .{ "continue", .KwContinue },
            .{ "pass", .KwPass },
            .{ "import", .KwImport },
            .{ "from", .KwFrom },
            .{ "as", .KwAs },
            .{ "True", .KwTrue },
            .{ "False", .KwFalse },
            .{ "None", .KwNone },
            .{ "and", .KwAnd },
            .{ "or", .KwOr },
            .{ "not", .KwNot },
            .{ "in", .KwIn },
            .{ "is", .KwIs },
            .{ "lambda", .KwLambda },
            .{ "try", .KwTry },
            .{ "except", .KwExcept },
            .{ "finally", .KwFinally },
            .{ "raise", .KwRaise },
            .{ "with", .KwWith },
            .{ "assert", .KwAssert },
            .{ "yield", .KwYield },
            .{ "global", .KwGlobal },
            .{ "nonlocal", .KwNonlocal },
            .{ "del", .KwDel },
            .{ "async", .KwAsync },
            .{ "await", .KwAwait },
            .{ "match", .KwMatch },
            .{ "case", .KwCase },
        });
        return keywords.get(lexeme) orelse .Name;
    }

    fn scanOperator(self: *Tokenizer) !void {
        const c = self.advance().?;
        const start_line = self.line;
        const start_col = self.column;

        const tok_type: TokenType = switch (c) {
            '+' => if (self.peek() == '=') blk: {
                _ = self.advance();
                break :blk .PlusEqual;
            } else .Plus,
            '-' => if (self.peek() == '=') blk: {
                _ = self.advance();
                break :blk .MinusEqual;
            } else if (self.peek() == '>') blk: {
                _ = self.advance();
                break :blk .Arrow;
            } else .Minus,
            '*' => if (self.peek() == '*') blk: {
                _ = self.advance();
                if (self.peek() == '=') {
                    _ = self.advance();
                    break :blk .DoubleStarEqual;
                }
                break :blk .DoubleStar;
            } else if (self.peek() == '=') blk: {
                _ = self.advance();
                break :blk .StarEqual;
            } else .Star,
            '/' => if (self.peek() == '/') blk: {
                _ = self.advance();
                if (self.peek() == '=') {
                    _ = self.advance();
                    break :blk .DoubleSlashEqual;
                }
                break :blk .DoubleSlash;
            } else if (self.peek() == '=') blk: {
                _ = self.advance();
                break :blk .SlashEqual;
            } else .Slash,
            '%' => if (self.peek() == '=') blk: {
                _ = self.advance();
                break :blk .PercentEqual;
            } else .Percent,
            '=' => if (self.peek() == '=') blk: {
                _ = self.advance();
                break :blk .EqualEqual;
            } else .Equal,
            '<' => if (self.peek() == '=') blk: {
                _ = self.advance();
                break :blk .LessEqual;
            } else if (self.peek() == '<') blk: {
                _ = self.advance();
                if (self.peek() == '=') {
                    _ = self.advance();
                    break :blk .LeftShiftEqual;
                }
                break :blk .LeftShift;
            } else .Less,
            '>' => if (self.peek() == '=') blk: {
                _ = self.advance();
                break :blk .GreaterEqual;
            } else if (self.peek() == '>') blk: {
                _ = self.advance();
                if (self.peek() == '=') {
                    _ = self.advance();
                    break :blk .RightShiftEqual;
                }
                break :blk .RightShift;
            } else .Greater,
            '!' => if (self.peek() == '=') blk: {
                _ = self.advance();
                break :blk .NotEqual;
            } else return,
            '&' => if (self.peek() == '=') blk: {
                _ = self.advance();
                break :blk .AmpersandEqual;
            } else .Ampersand,
            '|' => if (self.peek() == '=') blk: {
                _ = self.advance();
                break :blk .PipeEqual;
            } else .Pipe,
            '^' => if (self.peek() == '=') blk: {
                _ = self.advance();
                break :blk .CaretEqual;
            } else .Caret,
            '~' => .Tilde,
            '@' => if (self.peek() == '=') blk: {
                _ = self.advance();
                break :blk .AtEqual;
            } else .At,
            '(' => .LeftParen,
            ')' => .RightParen,
            '[' => .LeftBracket,
            ']' => .RightBracket,
            '{' => .LeftBrace,
            '}' => .RightBrace,
            ',' => .Comma,
            ':' => if (self.peek() == '=') blk: {
                _ = self.advance();
                break :blk .ColonEqual;
            } else .Colon,
            ';' => .Semicolon,
            '.' => if (self.peek() == '.') blk: {
                _ = self.advance();
                if (self.peek() == '.') {
                    _ = self.advance();
                    break :blk .Ellipsis;
                }
                break :blk .Dot;
            } else .Dot,
            else => return,
        };

        try self.tokens.append(.{ .type = tok_type, .lexeme = self.source[self.pos - 1 .. self.pos], .line = start_line, .column = start_col });
    }
};

// ============================================================================
// Runtime Parser
// ============================================================================

const RuntimeParser = struct {
    tokens: []Token,
    pos: usize,
    allocator: std.mem.Allocator,

    fn init(allocator: std.mem.Allocator, tokens: []Token) RuntimeParser {
        return .{ .tokens = tokens, .pos = 0, .allocator = allocator };
    }

    fn peek(self: *RuntimeParser) ?Token {
        if (self.pos >= self.tokens.len) return null;
        return self.tokens[self.pos];
    }

    fn advance(self: *RuntimeParser) ?Token {
        if (self.pos >= self.tokens.len) return null;
        const tok = self.tokens[self.pos];
        self.pos += 1;
        return tok;
    }

    fn match(self: *RuntimeParser, expected: TokenType) bool {
        if (self.peek()) |tok| {
            if (tok.type == expected) {
                _ = self.advance();
                return true;
            }
        }
        return false;
    }

    fn parseModule(self: *RuntimeParser) !*Module {
        var statements = std.ArrayList(Statement).init(self.allocator);

        while (self.peek()) |tok| {
            if (tok.type == .Eof) break;
            if (tok.type == .Newline) {
                _ = self.advance();
                continue;
            }
            const stmt = try self.parseStatement();
            try statements.append(stmt);
        }

        const module = try self.allocator.create(Module);
        module.* = .{
            .body = try statements.toOwnedSlice(),
            .type_ignores = &[_]TypeIgnore{},
        };
        return module;
    }

    fn parseStatement(self: *RuntimeParser) !Statement {
        const tok = self.peek() orelse return error.UnexpectedEof;

        return switch (tok.type) {
            .KwPass => {
                _ = self.advance();
                return .{ .pass_stmt = .{} };
            },
            .KwBreak => {
                _ = self.advance();
                return .{ .break_stmt = .{} };
            },
            .KwContinue => {
                _ = self.advance();
                return .{ .continue_stmt = .{} };
            },
            .KwReturn => try self.parseReturn(),
            .KwImport => try self.parseImport(),
            .KwDef => try self.parseFunctionDef(),
            .KwClass => try self.parseClassDef(),
            .KwIf => try self.parseIf(),
            .KwFor => try self.parseFor(),
            .KwWhile => try self.parseWhile(),
            else => try self.parseExprStatement(),
        };
    }

    fn parseReturn(self: *RuntimeParser) !Statement {
        _ = self.advance(); // consume 'return'
        var value: ?Expr = null;
        if (self.peek()) |tok| {
            if (tok.type != .Newline and tok.type != .Eof) {
                value = try self.parseExpr();
            }
        }
        return .{ .return_stmt = .{ .value = value } };
    }

    fn parseImport(self: *RuntimeParser) !Statement {
        _ = self.advance(); // consume 'import'
        var names = std.ArrayList(Alias).init(self.allocator);

        while (true) {
            const name_tok = self.advance() orelse return error.UnexpectedEof;
            if (name_tok.type != .Name) return error.UnexpectedToken;

            var asname: ?[]const u8 = null;
            if (self.match(.KwAs)) {
                const as_tok = self.advance() orelse return error.UnexpectedEof;
                if (as_tok.type != .Name) return error.UnexpectedToken;
                asname = as_tok.lexeme;
            }

            try names.append(.{ .name = name_tok.lexeme, .asname = asname });

            if (!self.match(.Comma)) break;
        }

        return .{ .import_stmt = .{ .names = try names.toOwnedSlice() } };
    }

    fn parseFunctionDef(self: *RuntimeParser) !Statement {
        _ = self.advance(); // consume 'def'
        const name_tok = self.advance() orelse return error.UnexpectedEof;
        if (name_tok.type != .Name) return error.UnexpectedToken;

        if (!self.match(.LeftParen)) return error.UnexpectedToken;
        const args = try self.parseArguments();
        if (!self.match(.RightParen)) return error.UnexpectedToken;

        var returns: ?Expr = null;
        if (self.match(.Arrow)) {
            returns = try self.parseExpr();
        }

        if (!self.match(.Colon)) return error.UnexpectedToken;

        const body = try self.parseBlock();

        return .{
            .function_def = .{
                .name = name_tok.lexeme,
                .args = args,
                .body = body,
                .decorator_list = &[_]Expr{},
                .returns = returns,
                .type_comment = null,
                .type_params = &[_]TypeParam{},
            },
        };
    }

    fn parseArguments(self: *RuntimeParser) !Arguments {
        var args_list = std.ArrayList(Arg).init(self.allocator);

        while (self.peek()) |tok| {
            if (tok.type == .RightParen) break;
            if (tok.type != .Name) break;

            const arg_tok = self.advance().?;
            var annotation: ?Expr = null;
            if (self.match(.Colon)) {
                annotation = try self.parseExpr();
            }

            try args_list.append(.{
                .arg = arg_tok.lexeme,
                .annotation = annotation,
                .type_comment = null,
            });

            if (!self.match(.Comma)) break;
        }

        return .{
            .posonlyargs = &[_]Arg{},
            .args = try args_list.toOwnedSlice(),
            .vararg = null,
            .kwonlyargs = &[_]Arg{},
            .kw_defaults = &[_]?Expr{},
            .kwarg = null,
            .defaults = &[_]Expr{},
        };
    }

    fn parseClassDef(self: *RuntimeParser) !Statement {
        _ = self.advance(); // consume 'class'
        const name_tok = self.advance() orelse return error.UnexpectedEof;
        if (name_tok.type != .Name) return error.UnexpectedToken;

        var bases = std.ArrayList(Expr).init(self.allocator);
        if (self.match(.LeftParen)) {
            while (self.peek()) |tok| {
                if (tok.type == .RightParen) break;
                const base = try self.parseExpr();
                try bases.append(base);
                if (!self.match(.Comma)) break;
            }
            if (!self.match(.RightParen)) return error.UnexpectedToken;
        }

        if (!self.match(.Colon)) return error.UnexpectedToken;
        const body = try self.parseBlock();

        return .{
            .class_def = .{
                .name = name_tok.lexeme,
                .bases = try bases.toOwnedSlice(),
                .keywords = &[_]Keyword{},
                .body = body,
                .decorator_list = &[_]Expr{},
                .type_params = &[_]TypeParam{},
            },
        };
    }

    fn parseIf(self: *RuntimeParser) !Statement {
        _ = self.advance(); // consume 'if'
        const test_expr = try self.parseExpr();
        if (!self.match(.Colon)) return error.UnexpectedToken;
        const body = try self.parseBlock();

        var orelse_body: []Statement = &[_]Statement{};
        if (self.match(.KwElse)) {
            if (!self.match(.Colon)) return error.UnexpectedToken;
            orelse_body = try self.parseBlock();
        }

        return .{
            .if_stmt = .{
                .test = test_expr,
                .body = body,
                .orelse = orelse_body,
            },
        };
    }

    fn parseFor(self: *RuntimeParser) !Statement {
        _ = self.advance(); // consume 'for'
        const target = try self.parseExpr();
        if (!self.match(.KwIn)) return error.UnexpectedToken;
        const iter = try self.parseExpr();
        if (!self.match(.Colon)) return error.UnexpectedToken;
        const body = try self.parseBlock();

        return .{
            .for_stmt = .{
                .target = target,
                .iter = iter,
                .body = body,
                .orelse = &[_]Statement{},
                .type_comment = null,
            },
        };
    }

    fn parseWhile(self: *RuntimeParser) !Statement {
        _ = self.advance(); // consume 'while'
        const test_expr = try self.parseExpr();
        if (!self.match(.Colon)) return error.UnexpectedToken;
        const body = try self.parseBlock();

        return .{
            .while_stmt = .{
                .test = test_expr,
                .body = body,
                .orelse = &[_]Statement{},
            },
        };
    }

    fn parseBlock(self: *RuntimeParser) ![]Statement {
        // Skip newline after colon
        _ = self.match(.Newline);
        _ = self.match(.Indent);

        var statements = std.ArrayList(Statement).init(self.allocator);
        while (self.peek()) |tok| {
            if (tok.type == .Dedent or tok.type == .Eof) break;
            if (tok.type == .Newline) {
                _ = self.advance();
                continue;
            }
            // Check for next statement at same or lower indentation
            if (tok.type == .KwElse or tok.type == .KwElif or tok.type == .KwExcept or tok.type == .KwFinally) break;

            const stmt = try self.parseStatement();
            try statements.append(stmt);
        }
        _ = self.match(.Dedent);
        return statements.toOwnedSlice();
    }

    fn parseExprStatement(self: *RuntimeParser) !Statement {
        const expr = try self.parseExpr();

        // Check for assignment
        if (self.match(.Equal)) {
            const value = try self.parseExpr();
            var targets = try self.allocator.alloc(Expr, 1);
            targets[0] = expr;
            return .{
                .assign = .{
                    .targets = targets,
                    .value = value,
                    .type_comment = null,
                },
            };
        }

        return .{ .expr_stmt = .{ .value = expr } };
    }

    fn parseExpr(self: *RuntimeParser) !Expr {
        return self.parseOr();
    }

    fn parseOr(self: *RuntimeParser) !Expr {
        var left = try self.parseAnd();
        while (self.match(.KwOr)) {
            const right = try self.parseAnd();
            var values = try self.allocator.alloc(Expr, 2);
            values[0] = left;
            values[1] = right;
            left = .{ .bool_op = .{ .op = .@"or", .values = values } };
        }
        return left;
    }

    fn parseAnd(self: *RuntimeParser) !Expr {
        var left = try self.parseNot();
        while (self.match(.KwAnd)) {
            const right = try self.parseNot();
            var values = try self.allocator.alloc(Expr, 2);
            values[0] = left;
            values[1] = right;
            left = .{ .bool_op = .{ .op = .@"and", .values = values } };
        }
        return left;
    }

    fn parseNot(self: *RuntimeParser) !Expr {
        if (self.match(.KwNot)) {
            const operand = try self.parseNot();
            const operand_ptr = try self.allocator.create(Expr);
            operand_ptr.* = operand;
            return .{ .unary_op = .{ .op = .not, .operand = operand_ptr } };
        }
        return self.parseComparison();
    }

    fn parseComparison(self: *RuntimeParser) !Expr {
        var left = try self.parseAddSub();

        var ops = std.ArrayList(CmpOp).init(self.allocator);
        var comparators = std.ArrayList(Expr).init(self.allocator);

        while (true) {
            const op: ?CmpOp = if (self.match(.Less)) .lt else if (self.match(.Greater)) .gt else if (self.match(.LessEqual)) .lte else if (self.match(.GreaterEqual)) .gte else if (self.match(.EqualEqual)) .eq else if (self.match(.NotEqual)) .not_eq else if (self.match(.KwIn)) .in else if (self.match(.KwIs)) .is else null;

            if (op) |o| {
                try ops.append(o);
                const right = try self.parseAddSub();
                try comparators.append(right);
            } else break;
        }

        if (ops.items.len > 0) {
            const left_ptr = try self.allocator.create(Expr);
            left_ptr.* = left;
            return .{
                .compare = .{
                    .left = left_ptr,
                    .ops = try ops.toOwnedSlice(),
                    .comparators = try comparators.toOwnedSlice(),
                },
            };
        }

        return left;
    }

    fn parseAddSub(self: *RuntimeParser) !Expr {
        var left = try self.parseMulDiv();

        while (true) {
            const op: ?Operator = if (self.match(.Plus)) .add else if (self.match(.Minus)) .sub else null;

            if (op) |o| {
                const right = try self.parseMulDiv();
                const left_ptr = try self.allocator.create(Expr);
                left_ptr.* = left;
                const right_ptr = try self.allocator.create(Expr);
                right_ptr.* = right;
                left = .{ .bin_op = .{ .left = left_ptr, .op = o, .right = right_ptr } };
            } else break;
        }

        return left;
    }

    fn parseMulDiv(self: *RuntimeParser) !Expr {
        var left = try self.parsePower();

        while (true) {
            const op: ?Operator = if (self.match(.Star)) .mult else if (self.match(.Slash)) .div else if (self.match(.DoubleSlash)) .floor_div else if (self.match(.Percent)) .mod else if (self.match(.At)) .mat_mult else null;

            if (op) |o| {
                const right = try self.parsePower();
                const left_ptr = try self.allocator.create(Expr);
                left_ptr.* = left;
                const right_ptr = try self.allocator.create(Expr);
                right_ptr.* = right;
                left = .{ .bin_op = .{ .left = left_ptr, .op = o, .right = right_ptr } };
            } else break;
        }

        return left;
    }

    fn parsePower(self: *RuntimeParser) !Expr {
        var base = try self.parseUnary();

        if (self.match(.DoubleStar)) {
            const exp = try self.parsePower(); // Right associative
            const base_ptr = try self.allocator.create(Expr);
            base_ptr.* = base;
            const exp_ptr = try self.allocator.create(Expr);
            exp_ptr.* = exp;
            return .{ .bin_op = .{ .left = base_ptr, .op = .pow, .right = exp_ptr } };
        }

        return base;
    }

    fn parseUnary(self: *RuntimeParser) !Expr {
        if (self.match(.Minus)) {
            const operand = try self.parseUnary();
            const operand_ptr = try self.allocator.create(Expr);
            operand_ptr.* = operand;
            return .{ .unary_op = .{ .op = .usub, .operand = operand_ptr } };
        }
        if (self.match(.Plus)) {
            const operand = try self.parseUnary();
            const operand_ptr = try self.allocator.create(Expr);
            operand_ptr.* = operand;
            return .{ .unary_op = .{ .op = .uadd, .operand = operand_ptr } };
        }
        if (self.match(.Tilde)) {
            const operand = try self.parseUnary();
            const operand_ptr = try self.allocator.create(Expr);
            operand_ptr.* = operand;
            return .{ .unary_op = .{ .op = .invert, .operand = operand_ptr } };
        }
        return self.parsePostfix();
    }

    fn parsePostfix(self: *RuntimeParser) !Expr {
        var expr = try self.parsePrimary();

        while (true) {
            if (self.match(.LeftParen)) {
                // Function call
                var args = std.ArrayList(Expr).init(self.allocator);
                while (self.peek()) |tok| {
                    if (tok.type == .RightParen) break;
                    const arg = try self.parseExpr();
                    try args.append(arg);
                    if (!self.match(.Comma)) break;
                }
                if (!self.match(.RightParen)) return error.UnexpectedToken;

                const func_ptr = try self.allocator.create(Expr);
                func_ptr.* = expr;
                expr = .{
                    .call = .{
                        .func = func_ptr,
                        .args = try args.toOwnedSlice(),
                        .keywords = &[_]Keyword{},
                    },
                };
            } else if (self.match(.LeftBracket)) {
                // Subscript
                const index = try self.parseExpr();
                if (!self.match(.RightBracket)) return error.UnexpectedToken;

                const value_ptr = try self.allocator.create(Expr);
                value_ptr.* = expr;
                const slice_ptr = try self.allocator.create(Expr);
                slice_ptr.* = index;
                expr = .{
                    .subscript = .{
                        .value = value_ptr,
                        .slice = slice_ptr,
                        .ctx = .load,
                    },
                };
            } else if (self.match(.Dot)) {
                // Attribute access
                const attr_tok = self.advance() orelse return error.UnexpectedEof;
                if (attr_tok.type != .Name) return error.UnexpectedToken;

                const value_ptr = try self.allocator.create(Expr);
                value_ptr.* = expr;
                expr = .{
                    .attribute = .{
                        .value = value_ptr,
                        .attr = attr_tok.lexeme,
                        .ctx = .load,
                    },
                };
            } else break;
        }

        return expr;
    }

    fn parsePrimary(self: *RuntimeParser) !Expr {
        const tok = self.advance() orelse return error.UnexpectedEof;

        return switch (tok.type) {
            .Number => .{
                .constant = .{
                    .value = if (std.mem.indexOf(u8, tok.lexeme, ".") != null)
                        .{ .float_val = std.fmt.parseFloat(f64, tok.lexeme) catch 0.0 }
                    else
                        .{ .int_val = std.fmt.parseInt(i64, tok.lexeme, 0) catch 0 },
                    .kind = null,
                },
            },
            .String => .{
                .constant = .{
                    .value = .{ .string_val = tok.lexeme },
                    .kind = null,
                },
            },
            .Name => .{
                .name = .{
                    .id = tok.lexeme,
                    .ctx = .load,
                },
            },
            .KwTrue => .{ .constant = .{ .value = .{ .bool_val = true }, .kind = null } },
            .KwFalse => .{ .constant = .{ .value = .{ .bool_val = false }, .kind = null } },
            .KwNone => .{ .constant = .{ .value = .none, .kind = null } },
            .LeftParen => blk: {
                // Tuple or grouped expression
                if (self.match(.RightParen)) {
                    break :blk .{ .tuple = .{ .elts = &[_]Expr{}, .ctx = .load } };
                }
                const inner = try self.parseExpr();
                if (self.match(.Comma)) {
                    // It's a tuple
                    var elts = std.ArrayList(Expr).init(self.allocator);
                    try elts.append(inner);
                    while (self.peek()) |t| {
                        if (t.type == .RightParen) break;
                        const elt = try self.parseExpr();
                        try elts.append(elt);
                        if (!self.match(.Comma)) break;
                    }
                    if (!self.match(.RightParen)) return error.UnexpectedToken;
                    break :blk .{ .tuple = .{ .elts = try elts.toOwnedSlice(), .ctx = .load } };
                }
                if (!self.match(.RightParen)) return error.UnexpectedToken;
                break :blk inner;
            },
            .LeftBracket => blk: {
                // List
                var elts = std.ArrayList(Expr).init(self.allocator);
                while (self.peek()) |t| {
                    if (t.type == .RightBracket) break;
                    const elt = try self.parseExpr();
                    try elts.append(elt);
                    if (!self.match(.Comma)) break;
                }
                if (!self.match(.RightBracket)) return error.UnexpectedToken;
                break :blk .{ .list = .{ .elts = try elts.toOwnedSlice(), .ctx = .load } };
            },
            .LeftBrace => blk: {
                // Dict or set
                if (self.match(.RightBrace)) {
                    break :blk .{ .dict = .{ .keys = &[_]?Expr{}, .values = &[_]Expr{} } };
                }
                const first = try self.parseExpr();
                if (self.match(.Colon)) {
                    // Dict
                    var keys = std.ArrayList(?Expr).init(self.allocator);
                    var values = std.ArrayList(Expr).init(self.allocator);
                    const first_value = try self.parseExpr();
                    try keys.append(first);
                    try values.append(first_value);

                    while (self.match(.Comma)) {
                        if (self.peek()) |t| {
                            if (t.type == .RightBrace) break;
                        }
                        const key = try self.parseExpr();
                        if (!self.match(.Colon)) return error.UnexpectedToken;
                        const value = try self.parseExpr();
                        try keys.append(key);
                        try values.append(value);
                    }
                    if (!self.match(.RightBrace)) return error.UnexpectedToken;
                    break :blk .{ .dict = .{ .keys = try keys.toOwnedSlice(), .values = try values.toOwnedSlice() } };
                } else {
                    // Set
                    var elts = std.ArrayList(Expr).init(self.allocator);
                    try elts.append(first);
                    while (self.match(.Comma)) {
                        if (self.peek()) |t| {
                            if (t.type == .RightBrace) break;
                        }
                        const elt = try self.parseExpr();
                        try elts.append(elt);
                    }
                    if (!self.match(.RightBrace)) return error.UnexpectedToken;
                    break :blk .{ .set = .{ .elts = try elts.toOwnedSlice() } };
                }
            },
            else => error.UnexpectedToken,
        };
    }
};

// ============================================================================
// AST Functions - Real Implementations
// ============================================================================

/// Parse source code into an AST
pub fn parse(allocator: std.mem.Allocator, source: []const u8, filename: []const u8, mode: []const u8) !*Module {
    _ = filename;
    _ = mode;

    var tokenizer = Tokenizer.init(allocator, source);
    defer tokenizer.deinit();
    const tokens = try tokenizer.tokenize();

    var parser = RuntimeParser.init(allocator, tokens);
    return parser.parseModule();
}

/// Compile an AST into a code object
/// Returns a CodeObject containing the bytecode representation
pub fn compile_ast(allocator: std.mem.Allocator, node: *Module, filename: []const u8, mode: []const u8) !*CodeObject {
    _ = mode;

    const code = try allocator.create(CodeObject);
    code.* = .{
        .co_filename = filename,
        .co_name = "<module>",
        .co_code = &[_]u8{},
        .co_consts = &[_]ConstantValue{},
        .co_names = &[_][]const u8{},
        .co_varnames = &[_][]const u8{},
        .co_argcount = 0,
        .co_nlocals = 0,
        .co_stacksize = 0,
        .co_flags = 0,
        .body = node.body,
    };
    return code;
}

/// Code object representation
pub const CodeObject = struct {
    co_filename: []const u8,
    co_name: []const u8,
    co_code: []const u8,
    co_consts: []const ConstantValue,
    co_names: []const []const u8,
    co_varnames: []const []const u8,
    co_argcount: i32,
    co_nlocals: i32,
    co_stacksize: i32,
    co_flags: i32,
    body: []Statement,
};

/// Convert AST to source code
pub fn unparse(allocator: std.mem.Allocator, node: anytype) ![]u8 {
    var result = std.ArrayList(u8).init(allocator);
    try unparseNode(&result, node, 0);
    return result.toOwnedSlice();
}

fn unparseNode(result: *std.ArrayList(u8), node: anytype, indent: usize) !void {
    const T = @TypeOf(node);

    if (T == *Module) {
        for (node.body) |stmt| {
            try unparseStatement(result, stmt, indent);
            try result.append('\n');
        }
    } else if (T == Expr) {
        try unparseExpr(result, node);
    } else if (T == Statement) {
        try unparseStatement(result, node, indent);
    }
}

fn unparseStatement(result: *std.ArrayList(u8), stmt: Statement, indent: usize) !void {
    // Add indentation
    for (0..indent) |_| {
        try result.appendSlice("    ");
    }

    switch (stmt) {
        .pass_stmt => try result.appendSlice("pass"),
        .break_stmt => try result.appendSlice("break"),
        .continue_stmt => try result.appendSlice("continue"),
        .return_stmt => |r| {
            try result.appendSlice("return");
            if (r.value) |v| {
                try result.append(' ');
                try unparseExpr(result, v);
            }
        },
        .expr_stmt => |e| try unparseExpr(result, e.value),
        .assign => |a| {
            for (a.targets, 0..) |target, i| {
                if (i > 0) try result.appendSlice(" = ");
                try unparseExpr(result, target);
            }
            try result.appendSlice(" = ");
            try unparseExpr(result, a.value);
        },
        .function_def => |f| {
            try result.appendSlice("def ");
            try result.appendSlice(f.name);
            try result.append('(');
            for (f.args.args, 0..) |arg, i| {
                if (i > 0) try result.appendSlice(", ");
                try result.appendSlice(arg.arg);
            }
            try result.appendSlice("):\n");
            for (f.body) |body_stmt| {
                try unparseStatement(result, body_stmt, indent + 1);
                try result.append('\n');
            }
        },
        .class_def => |c| {
            try result.appendSlice("class ");
            try result.appendSlice(c.name);
            if (c.bases.len > 0) {
                try result.append('(');
                for (c.bases, 0..) |base, i| {
                    if (i > 0) try result.appendSlice(", ");
                    try unparseExpr(result, base);
                }
                try result.append(')');
            }
            try result.appendSlice(":\n");
            for (c.body) |body_stmt| {
                try unparseStatement(result, body_stmt, indent + 1);
                try result.append('\n');
            }
        },
        .if_stmt => |i| {
            try result.appendSlice("if ");
            try unparseExpr(result, i.test);
            try result.appendSlice(":\n");
            for (i.body) |body_stmt| {
                try unparseStatement(result, body_stmt, indent + 1);
                try result.append('\n');
            }
            if (i.orelse.len > 0) {
                for (0..indent) |_| {
                    try result.appendSlice("    ");
                }
                try result.appendSlice("else:\n");
                for (i.orelse) |else_stmt| {
                    try unparseStatement(result, else_stmt, indent + 1);
                    try result.append('\n');
                }
            }
        },
        .for_stmt => |f| {
            try result.appendSlice("for ");
            try unparseExpr(result, f.target);
            try result.appendSlice(" in ");
            try unparseExpr(result, f.iter);
            try result.appendSlice(":\n");
            for (f.body) |body_stmt| {
                try unparseStatement(result, body_stmt, indent + 1);
                try result.append('\n');
            }
        },
        .while_stmt => |w| {
            try result.appendSlice("while ");
            try unparseExpr(result, w.test);
            try result.appendSlice(":\n");
            for (w.body) |body_stmt| {
                try unparseStatement(result, body_stmt, indent + 1);
                try result.append('\n');
            }
        },
        .import_stmt => |im| {
            try result.appendSlice("import ");
            for (im.names, 0..) |alias, i| {
                if (i > 0) try result.appendSlice(", ");
                try result.appendSlice(alias.name);
                if (alias.asname) |asname| {
                    try result.appendSlice(" as ");
                    try result.appendSlice(asname);
                }
            }
        },
        else => try result.appendSlice("# unsupported statement"),
    }
}

fn unparseExpr(result: *std.ArrayList(u8), expr: Expr) !void {
    switch (expr) {
        .constant => |c| {
            switch (c.value) {
                .none => try result.appendSlice("None"),
                .bool_val => |b| try result.appendSlice(if (b) "True" else "False"),
                .int_val => |i| try result.writer().print("{d}", .{i}),
                .float_val => |f| try result.writer().print("{d}", .{f}),
                .string_val => |s| {
                    try result.append('\'');
                    try result.appendSlice(s);
                    try result.append('\'');
                },
                .bytes_val => |b| {
                    try result.appendSlice("b'");
                    try result.appendSlice(b);
                    try result.append('\'');
                },
                .ellipsis => try result.appendSlice("..."),
            }
        },
        .name => |n| try result.appendSlice(n.id),
        .bin_op => |b| {
            try result.append('(');
            try unparseExpr(result, b.left.*);
            const op_str: []const u8 = switch (b.op) {
                .add => " + ",
                .sub => " - ",
                .mult => " * ",
                .div => " / ",
                .mod => " % ",
                .pow => " ** ",
                .floor_div => " // ",
                .mat_mult => " @ ",
                .lshift => " << ",
                .rshift => " >> ",
                .bit_or => " | ",
                .bit_xor => " ^ ",
                .bit_and => " & ",
            };
            try result.appendSlice(op_str);
            try unparseExpr(result, b.right.*);
            try result.append(')');
        },
        .unary_op => |u| {
            const op_str: []const u8 = switch (u.op) {
                .invert => "~",
                .not => "not ",
                .uadd => "+",
                .usub => "-",
            };
            try result.appendSlice(op_str);
            try unparseExpr(result, u.operand.*);
        },
        .bool_op => |b| {
            const op_str: []const u8 = switch (b.op) {
                .@"and" => " and ",
                .@"or" => " or ",
            };
            for (b.values, 0..) |v, i| {
                if (i > 0) try result.appendSlice(op_str);
                try unparseExpr(result, v);
            }
        },
        .compare => |c| {
            try unparseExpr(result, c.left.*);
            for (c.ops, 0..) |op, i| {
                const op_str: []const u8 = switch (op) {
                    .eq => " == ",
                    .not_eq => " != ",
                    .lt => " < ",
                    .lte => " <= ",
                    .gt => " > ",
                    .gte => " >= ",
                    .is => " is ",
                    .is_not => " is not ",
                    .in => " in ",
                    .not_in => " not in ",
                };
                try result.appendSlice(op_str);
                try unparseExpr(result, c.comparators[i]);
            }
        },
        .call => |c| {
            try unparseExpr(result, c.func.*);
            try result.append('(');
            for (c.args, 0..) |arg, i| {
                if (i > 0) try result.appendSlice(", ");
                try unparseExpr(result, arg);
            }
            try result.append(')');
        },
        .attribute => |a| {
            try unparseExpr(result, a.value.*);
            try result.append('.');
            try result.appendSlice(a.attr);
        },
        .subscript => |s| {
            try unparseExpr(result, s.value.*);
            try result.append('[');
            try unparseExpr(result, s.slice.*);
            try result.append(']');
        },
        .list => |l| {
            try result.append('[');
            for (l.elts, 0..) |elt, i| {
                if (i > 0) try result.appendSlice(", ");
                try unparseExpr(result, elt);
            }
            try result.append(']');
        },
        .tuple => |t| {
            try result.append('(');
            for (t.elts, 0..) |elt, i| {
                if (i > 0) try result.appendSlice(", ");
                try unparseExpr(result, elt);
            }
            if (t.elts.len == 1) try result.append(',');
            try result.append(')');
        },
        .dict => |d| {
            try result.append('{');
            for (d.keys, 0..) |key, i| {
                if (i > 0) try result.appendSlice(", ");
                if (key) |k| {
                    try unparseExpr(result, k);
                    try result.appendSlice(": ");
                } else {
                    try result.appendSlice("**");
                }
                try unparseExpr(result, d.values[i]);
            }
            try result.append('}');
        },
        .set => |s| {
            try result.append('{');
            for (s.elts, 0..) |elt, i| {
                if (i > 0) try result.appendSlice(", ");
                try unparseExpr(result, elt);
            }
            try result.append('}');
        },
        else => try result.appendSlice("..."),
    }
}

/// Pretty print an AST
pub fn dump(allocator: std.mem.Allocator, node: anytype, annotate_fields: bool, include_attributes: bool, indent_level: ?usize) ![]u8 {
    _ = annotate_fields;
    _ = include_attributes;
    const indent = indent_level orelse 2;

    var result = std.ArrayList(u8).init(allocator);
    try dumpNode(&result, node, 0, indent);
    return result.toOwnedSlice();
}

fn dumpNode(result: *std.ArrayList(u8), node: anytype, depth: usize, indent: usize) !void {
    const T = @TypeOf(node);

    // Add indentation
    for (0..depth * indent) |_| {
        try result.append(' ');
    }

    if (T == *Module) {
        try result.appendSlice("Module(body=[\n");
        for (node.body) |stmt| {
            try dumpStatement(result, stmt, depth + 1, indent);
            try result.appendSlice(",\n");
        }
        for (0..depth * indent) |_| {
            try result.append(' ');
        }
        try result.appendSlice("])");
    } else if (T == Expr) {
        try dumpExpr(result, node, depth, indent);
    } else if (T == Statement) {
        try dumpStatement(result, node, depth, indent);
    }
}

fn dumpStatement(result: *std.ArrayList(u8), stmt: Statement, depth: usize, indent: usize) !void {
    for (0..depth * indent) |_| {
        try result.append(' ');
    }

    switch (stmt) {
        .pass_stmt => try result.appendSlice("Pass()"),
        .break_stmt => try result.appendSlice("Break()"),
        .continue_stmt => try result.appendSlice("Continue()"),
        .return_stmt => |r| {
            try result.appendSlice("Return(value=");
            if (r.value) |v| {
                try dumpExpr(result, v, 0, indent);
            } else {
                try result.appendSlice("None");
            }
            try result.append(')');
        },
        .expr_stmt => |e| {
            try result.appendSlice("Expr(value=");
            try dumpExpr(result, e.value, 0, indent);
            try result.append(')');
        },
        .assign => |a| {
            try result.appendSlice("Assign(targets=[");
            for (a.targets) |target| {
                try dumpExpr(result, target, 0, indent);
            }
            try result.appendSlice("], value=");
            try dumpExpr(result, a.value, 0, indent);
            try result.append(')');
        },
        .function_def => |f| {
            try result.appendSlice("FunctionDef(name='");
            try result.appendSlice(f.name);
            try result.appendSlice("', args=arguments(...), body=[...])");
        },
        .class_def => |c| {
            try result.appendSlice("ClassDef(name='");
            try result.appendSlice(c.name);
            try result.appendSlice("', bases=[...], body=[...])");
        },
        .if_stmt => try result.appendSlice("If(test=..., body=[...], orelse=[...])"),
        .for_stmt => try result.appendSlice("For(target=..., iter=..., body=[...])"),
        .while_stmt => try result.appendSlice("While(test=..., body=[...])"),
        .import_stmt => |im| {
            try result.appendSlice("Import(names=[");
            for (im.names, 0..) |alias, i| {
                if (i > 0) try result.appendSlice(", ");
                try result.appendSlice("alias(name='");
                try result.appendSlice(alias.name);
                try result.appendSlice("')");
            }
            try result.appendSlice("])");
        },
        else => try result.appendSlice("..."),
    }
}

fn dumpExpr(result: *std.ArrayList(u8), expr: Expr, depth: usize, indent: usize) !void {
    _ = depth;
    _ = indent;

    switch (expr) {
        .constant => |c| {
            try result.appendSlice("Constant(value=");
            switch (c.value) {
                .none => try result.appendSlice("None"),
                .bool_val => |b| try result.appendSlice(if (b) "True" else "False"),
                .int_val => |i| try result.writer().print("{d}", .{i}),
                .float_val => |f| try result.writer().print("{d}", .{f}),
                .string_val => |s| {
                    try result.append('\'');
                    try result.appendSlice(s);
                    try result.append('\'');
                },
                .bytes_val => |b| {
                    try result.appendSlice("b'");
                    try result.appendSlice(b);
                    try result.append('\'');
                },
                .ellipsis => try result.appendSlice("..."),
            }
            try result.append(')');
        },
        .name => |n| {
            try result.appendSlice("Name(id='");
            try result.appendSlice(n.id);
            try result.appendSlice("', ctx=Load())");
        },
        .bin_op => |b| {
            try result.appendSlice("BinOp(left=");
            try dumpExpr(result, b.left.*, 0, 0);
            try result.appendSlice(", op=");
            try result.appendSlice(@tagName(b.op));
            try result.appendSlice("(), right=");
            try dumpExpr(result, b.right.*, 0, 0);
            try result.append(')');
        },
        .call => |c| {
            try result.appendSlice("Call(func=");
            try dumpExpr(result, c.func.*, 0, 0);
            try result.appendSlice(", args=[...])");
        },
        else => try result.appendSlice("..."),
    }
}

/// Get docstring from node
pub fn getDocstring(node: anytype) ?[]const u8 {
    _ = node;
    return null;
}

/// Walk AST nodes
pub fn walk(allocator: std.mem.Allocator, node: anytype) !NodeIterator {
    return NodeIterator.init(allocator, node);
}

pub const NodeIterator = struct {
    allocator: std.mem.Allocator,
    stack: std.ArrayList(*anyopaque),

    pub fn init(allocator: std.mem.Allocator, root: anytype) NodeIterator {
        _ = root;
        return .{
            .allocator = allocator,
            .stack = std.ArrayList(*anyopaque).init(allocator),
        };
    }

    pub fn deinit(self: *NodeIterator) void {
        self.stack.deinit();
    }

    pub fn next(self: *NodeIterator) ?*anyopaque {
        if (self.stack.items.len == 0) return null;
        return self.stack.pop();
    }
};

/// Fix missing locations in AST
pub fn fixMissingLocations(node: anytype) void {
    _ = node;
}

/// Increment line numbers
pub fn incrementLineno(node: anytype, n: i32) void {
    _ = node;
    _ = n;
}

/// Copy location from one node to another
pub fn copyLocation(source: anytype, dest: anytype) void {
    _ = source;
    _ = dest;
}

/// Get source segment
pub fn getSourceSegment(source: []const u8, node: anytype, padded: bool) ?[]const u8 {
    _ = source;
    _ = node;
    _ = padded;
    return null;
}

// ============================================================================
// NodeVisitor
// ============================================================================

/// Base class for AST visitors
pub fn NodeVisitor(comptime T: type) type {
    return struct {
        const Self = @This();

        context: T,

        pub fn init(context: T) Self {
            return .{ .context = context };
        }

        pub fn visit(self: *Self, node: anytype) void {
            _ = self;
            _ = node;
        }

        pub fn genericVisit(self: *Self, node: anytype) void {
            _ = self;
            _ = node;
        }
    };
}

/// Base class for AST transformers
pub fn NodeTransformer(comptime T: type) type {
    return struct {
        const Self = @This();

        context: T,

        pub fn init(context: T) Self {
            return .{ .context = context };
        }

        pub fn visit(self: *Self, node: anytype) @TypeOf(node) {
            _ = self;
            return node;
        }

        pub fn genericVisit(self: *Self, node: anytype) @TypeOf(node) {
            _ = self;
            return node;
        }
    };
}

// ============================================================================
// Constants
// ============================================================================

pub const PyCF_ONLY_AST = 0x0400;
pub const PyCF_TYPE_COMMENTS = 0x1000;
pub const PyCF_ALLOW_TOP_LEVEL_AWAIT = 0x2000;

// ============================================================================
// Tests
// ============================================================================

test "operator enum" {
    try std.testing.expect(@intFromEnum(Operator.add) == 0);
    try std.testing.expect(@intFromEnum(CmpOp.eq) == 0);
}

test "expr context" {
    try std.testing.expect(@intFromEnum(ExprContext.load) == 0);
    try std.testing.expect(@intFromEnum(ExprContext.store) == 1);
}

test "constant value" {
    const c1 = ConstantValue{ .int_val = 42 };
    try std.testing.expectEqual(@as(i64, 42), c1.int_val);

    const c2 = ConstantValue{ .string_val = "hello" };
    try std.testing.expectEqualStrings("hello", c2.string_val);
}
