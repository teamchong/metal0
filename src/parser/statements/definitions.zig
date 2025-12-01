/// Function and class definition parsing
const std = @import("std");
const ast = @import("ast");
const lexer = @import("../../lexer.zig");
const ParseError = @import("../../parser.zig").ParseError;
const Parser = @import("../../parser.zig").Parser;
const misc = @import("misc.zig");

/// Extract base class name from expression node (for class bases)
/// Returns newly allocated string, or null for complex expressions like function calls
fn extractBaseName(self: *Parser, node: ast.Node) ?[]const u8 {
    switch (node) {
        .name => |n| return self.allocator.dupe(u8, n.id) catch null,
        .attribute => {
            // Build dotted name: a.b.c
            var parts = std.ArrayList(u8){};
            defer parts.deinit(self.allocator);

            // Build the full name by collecting parts
            collectDottedParts(self, node, &parts) catch return null;
            if (parts.items.len == 0) return null;

            return self.allocator.dupe(u8, parts.items) catch null;
        },
        else => return null, // Function calls, subscripts, etc. - not supported as base names
    }
}

/// Recursively collect parts of a dotted name
fn collectDottedParts(self: *Parser, node: ast.Node, parts: *std.ArrayList(u8)) !void {
    switch (node) {
        .name => |n| {
            try parts.appendSlice(self.allocator, n.id);
        },
        .attribute => |attr| {
            try collectDottedParts(self, attr.value.*, parts);
            try parts.append(self.allocator, '.');
            try parts.appendSlice(self.allocator, attr.attr);
        },
        else => {}, // Ignore complex expressions
    }
}

/// Parse type annotation supporting PEP 585 generics (e.g., int, str, list[int], tuple[str, str], dict[str, int])
/// Also supports dotted types like typing.Any, t.Optional[str]
/// Also supports parenthesized types like (int | str), (tuple[...] | tuple[...])
fn parseTypeAnnotation(self: *Parser) ParseError!?[]const u8 {
    if (self.current >= self.tokens.len) return null;

    // Handle parenthesized type annotations: (type | type)
    if (self.tokens[self.current].type == .LParen) {
        self.current += 1; // consume '('

        var type_buf = std.ArrayList(u8){};
        defer type_buf.deinit(self.allocator);

        try type_buf.append(self.allocator, '(');

        var paren_depth: usize = 1;
        while (self.current < self.tokens.len and paren_depth > 0) {
            const tok = self.tokens[self.current];
            switch (tok.type) {
                .LParen => {
                    try type_buf.append(self.allocator, '(');
                    paren_depth += 1;
                },
                .RParen => {
                    try type_buf.append(self.allocator, ')');
                    paren_depth -= 1;
                },
                .LBracket => try type_buf.append(self.allocator, '['),
                .RBracket => try type_buf.append(self.allocator, ']'),
                .Comma => try type_buf.appendSlice(self.allocator, ", "),
                .Pipe => try type_buf.appendSlice(self.allocator, " | "),
                .Dot => try type_buf.append(self.allocator, '.'),
                .Colon => try type_buf.append(self.allocator, ':'),
                .Ellipsis => try type_buf.appendSlice(self.allocator, "..."),
                .Ident => try type_buf.appendSlice(self.allocator, tok.lexeme),
                .True => try type_buf.appendSlice(self.allocator, "True"),
                .False => try type_buf.appendSlice(self.allocator, "False"),
                .None => try type_buf.appendSlice(self.allocator, "None"),
                .String => try type_buf.appendSlice(self.allocator, tok.lexeme),
                .Number => try type_buf.appendSlice(self.allocator, tok.lexeme),
                else => break,
            }
            self.current += 1;
        }

        // After closing paren, check for attribute access: (1).__class__
        while (self.current < self.tokens.len and self.tokens[self.current].type == .Dot) {
            try type_buf.append(self.allocator, '.');
            self.current += 1; // consume '.'
            if (self.current < self.tokens.len and self.tokens[self.current].type == .Ident) {
                try type_buf.appendSlice(self.allocator, self.tokens[self.current].lexeme);
                self.current += 1;
            }
        }

        return try self.allocator.dupe(u8, type_buf.items);
    }

    // Handle unary +, -, ~, *, **, not in type annotations: +some, -some, ~a, *a, **a, not a
    const unary_tok = self.tokens[self.current].type;
    if (unary_tok == .Plus or unary_tok == .Minus or unary_tok == .Tilde or
        unary_tok == .Not or unary_tok == .Star or unary_tok == .DoubleStar)
    {
        var type_buf = std.ArrayList(u8){};
        defer type_buf.deinit(self.allocator);

        const prefix = switch (unary_tok) {
            .Plus => "+",
            .Minus => "-",
            .Tilde => "~",
            .Not => "not ",
            .Star => "*",
            .DoubleStar => "**",
            else => unreachable,
        };
        try type_buf.appendSlice(self.allocator, prefix);
        self.current += 1;

        // Parse the rest of the annotation
        const rest = try parseTypeAnnotation(self);
        if (rest) |r| {
            defer self.allocator.free(r);
            try type_buf.appendSlice(self.allocator, r);
        }
        return try self.allocator.dupe(u8, type_buf.items);
    }

    // Handle dict/set literals in type annotations: {obj: module}, {obj, module}, {a + b}
    if (self.tokens[self.current].type == .LBrace) {
        var type_buf = std.ArrayList(u8){};
        defer type_buf.deinit(self.allocator);

        try type_buf.append(self.allocator, '{');
        self.current += 1; // consume '{'

        var brace_depth: usize = 1;
        while (self.current < self.tokens.len and brace_depth > 0) {
            const tok = self.tokens[self.current];
            switch (tok.type) {
                .LBrace => {
                    try type_buf.append(self.allocator, '{');
                    brace_depth += 1;
                },
                .RBrace => {
                    try type_buf.append(self.allocator, '}');
                    brace_depth -= 1;
                },
                .LBracket => try type_buf.append(self.allocator, '['),
                .RBracket => try type_buf.append(self.allocator, ']'),
                .LParen => try type_buf.append(self.allocator, '('),
                .RParen => try type_buf.append(self.allocator, ')'),
                .Comma => try type_buf.appendSlice(self.allocator, ", "),
                .Colon => try type_buf.appendSlice(self.allocator, ": "),
                .Pipe => try type_buf.appendSlice(self.allocator, " | "),
                .Plus => try type_buf.appendSlice(self.allocator, " + "),
                .Minus => try type_buf.appendSlice(self.allocator, " - "),
                .Star => try type_buf.appendSlice(self.allocator, " * "),
                .Slash => try type_buf.appendSlice(self.allocator, " / "),
                .Ampersand => try type_buf.appendSlice(self.allocator, " & "),
                .Caret => try type_buf.appendSlice(self.allocator, " ^ "),
                .Tilde => try type_buf.append(self.allocator, '~'),
                .Dot => try type_buf.append(self.allocator, '.'),
                .Ident => try type_buf.appendSlice(self.allocator, tok.lexeme),
                .String => try type_buf.appendSlice(self.allocator, tok.lexeme),
                .Number => try type_buf.appendSlice(self.allocator, tok.lexeme),
                else => break,
            }
            self.current += 1;
        }

        return try self.allocator.dupe(u8, type_buf.items);
    }

    // Handle list literals in type annotations: [obj], [obj, module], [*a]
    if (self.tokens[self.current].type == .LBracket) {
        var type_buf = std.ArrayList(u8){};
        defer type_buf.deinit(self.allocator);

        try type_buf.append(self.allocator, '[');
        self.current += 1; // consume '['

        var bracket_depth: usize = 1;
        while (self.current < self.tokens.len and bracket_depth > 0) {
            const tok = self.tokens[self.current];
            switch (tok.type) {
                .LBracket => {
                    try type_buf.append(self.allocator, '[');
                    bracket_depth += 1;
                },
                .RBracket => {
                    try type_buf.append(self.allocator, ']');
                    bracket_depth -= 1;
                },
                .LBrace => try type_buf.append(self.allocator, '{'),
                .RBrace => try type_buf.append(self.allocator, '}'),
                .LParen => try type_buf.append(self.allocator, '('),
                .RParen => try type_buf.append(self.allocator, ')'),
                .Comma => try type_buf.appendSlice(self.allocator, ", "),
                .Colon => try type_buf.appendSlice(self.allocator, ": "),
                .Pipe => try type_buf.appendSlice(self.allocator, " | "),
                .Plus => try type_buf.appendSlice(self.allocator, " + "),
                .Minus => try type_buf.appendSlice(self.allocator, " - "),
                .Star => try type_buf.append(self.allocator, '*'),
                .DoubleStar => try type_buf.appendSlice(self.allocator, "**"),
                .Dot => try type_buf.append(self.allocator, '.'),
                .Ident => try type_buf.appendSlice(self.allocator, tok.lexeme),
                .String => try type_buf.appendSlice(self.allocator, tok.lexeme),
                .Number => try type_buf.appendSlice(self.allocator, tok.lexeme),
                else => break,
            }
            self.current += 1;
        }

        return try self.allocator.dupe(u8, type_buf.items);
    }

    // Handle string literals (including f-strings, t-strings, byte strings) in type annotations
    if (self.tokens[self.current].type == .String or self.tokens[self.current].type == .FString or
        self.tokens[self.current].type == .ByteString)
    {
        var type_buf = std.ArrayList(u8){};
        defer type_buf.deinit(self.allocator);

        try type_buf.appendSlice(self.allocator, self.tokens[self.current].lexeme);
        self.current += 1;

        return try self.allocator.dupe(u8, type_buf.items);
    }

    // Handle ellipsis in type annotations: g: ...
    if (self.tokens[self.current].type == .Ellipsis) {
        self.current += 1;
        return try self.allocator.dupe(u8, "...");
    }

    // Handle number and complex number literals in type annotations: 1 + a, 1j
    if (self.tokens[self.current].type == .Number or self.tokens[self.current].type == .ComplexNumber) {
        var type_buf = std.ArrayList(u8){};
        defer type_buf.deinit(self.allocator);

        try type_buf.appendSlice(self.allocator, self.tokens[self.current].lexeme);
        self.current += 1;

        // Check for binary operator after number
        if (self.current < self.tokens.len) {
            const op_str: ?[]const u8 = switch (self.tokens[self.current].type) {
                .Plus => " + ",
                .Minus => " - ",
                .Star => " * ",
                .Slash => " / ",
                .Percent => " % ",
                .DoubleStar => " ** ",
                .DoubleSlash => " // ",
                .Pipe => " | ",
                .Ampersand => " & ",
                .Caret => " ^ ",
                .LtLt => " << ",
                .GtGt => " >> ",
                .Lt => " < ",
                .Gt => " > ",
                .LtEq => " <= ",
                .GtEq => " >= ",
                .EqEq => " == ",
                .NotEq => " != ",
                .At => " @ ",
                else => null,
            };
            if (op_str) |op| {
                try type_buf.appendSlice(self.allocator, op);
                self.current += 1;
                const rest = try parseTypeAnnotation(self);
                if (rest) |r| {
                    defer self.allocator.free(r);
                    try type_buf.appendSlice(self.allocator, r);
                }
            }
        }
        return try self.allocator.dupe(u8, type_buf.items);
    }

    // Handle both identifiers and None/True/False as type names
    const tok_type = self.tokens[self.current].type;
    if (tok_type != .Ident and tok_type != .None and tok_type != .True and tok_type != .False) {
        return null;
    }

    // Build full type name including dots (e.g., "t.Any", "typing.Optional")
    var type_parts = std.ArrayList(u8){};
    defer type_parts.deinit(self.allocator);

    // For None, True, False - use the keyword name directly
    const lexeme = if (tok_type == .None) "None" else if (tok_type == .True) "True" else if (tok_type == .False) "False" else self.tokens[self.current].lexeme;
    try type_parts.appendSlice(self.allocator, lexeme);
    self.current += 1;

    // Handle dotted types: t.Any, typing.Optional, etc.
    while (self.current + 1 < self.tokens.len and
        self.tokens[self.current].type == .Dot and
        self.tokens[self.current + 1].type == .Ident)
    {
        try type_parts.append(self.allocator, '.');
        self.current += 1; // consume '.'
        try type_parts.appendSlice(self.allocator, self.tokens[self.current].lexeme);
        self.current += 1; // consume identifier
    }

    // Check for union type: int | str (PEP 604) or comparison: some < obj, or math: a + b
    // Must check before bracket handling
    if (self.current < self.tokens.len) {
        const next_tok = self.tokens[self.current].type;
        // Support all binary operators that might appear in type annotations
        const op_str: ?[]const u8 = switch (next_tok) {
            .Pipe => " | ",
            .Lt => " < ",
            .Gt => " > ",
            .LtEq => " <= ",
            .GtEq => " >= ",
            .Plus => " + ",
            .Minus => " - ",
            .Star => " * ",
            .Slash => " / ",
            .Percent => " % ",
            .Ampersand => " & ",
            .Caret => " ^ ",
            .Tilde => " ~ ",
            .LtLt => " << ",
            .GtGt => " >> ",
            .DoubleStar => " ** ",
            .DoubleSlash => " // ",
            .At => " @ ",
            .EqEq => " == ",
            .NotEq => " != ",
            .And => " and ",
            .Or => " or ",
            .Not => " not ",
            .In => " in ",
            .Is => " is ",
            else => null,
        };
        if (op_str) |op| {
            try type_parts.appendSlice(self.allocator, op);
            self.current += 1; // consume operator

            // Parse the next type
            const next_type = try parseTypeAnnotation(self);
            if (next_type) |nt| {
                defer self.allocator.free(nt);
                try type_parts.appendSlice(self.allocator, nt);
            }

            return try self.allocator.dupe(u8, type_parts.items);
        }
    }

    const base_type = try self.allocator.dupe(u8, type_parts.items);

    // Check for function call style annotations: Type(...) - used in forward references
    if (self.current < self.tokens.len and self.tokens[self.current].type == .LParen) {
        defer self.allocator.free(base_type);
        var type_buf = std.ArrayList(u8){};
        defer type_buf.deinit(self.allocator);

        try type_buf.appendSlice(self.allocator, base_type);
        try type_buf.append(self.allocator, '(');
        self.current += 1; // consume '('

        var paren_depth: usize = 1;
        while (self.current < self.tokens.len and paren_depth > 0) {
            const tok = self.tokens[self.current];
            switch (tok.type) {
                .LParen => {
                    try type_buf.append(self.allocator, '(');
                    paren_depth += 1;
                },
                .RParen => {
                    try type_buf.append(self.allocator, ')');
                    paren_depth -= 1;
                },
                .LBracket => try type_buf.append(self.allocator, '['),
                .RBracket => try type_buf.append(self.allocator, ']'),
                .Comma => try type_buf.appendSlice(self.allocator, ", "),
                .Ident => try type_buf.appendSlice(self.allocator, tok.lexeme),
                .String => try type_buf.appendSlice(self.allocator, tok.lexeme),
                .Number => try type_buf.appendSlice(self.allocator, tok.lexeme),
                .Dot => try type_buf.append(self.allocator, '.'),
                .Pipe => try type_buf.appendSlice(self.allocator, " | "),
                .Star => try type_buf.append(self.allocator, '*'),
                .DoubleStar => try type_buf.appendSlice(self.allocator, "**"),
                .Eq => try type_buf.append(self.allocator, '='),
                .True => try type_buf.appendSlice(self.allocator, "True"),
                .False => try type_buf.appendSlice(self.allocator, "False"),
                .None => try type_buf.appendSlice(self.allocator, "None"),
                else => break,
            }
            self.current += 1;
        }

        // Check for union type after call: Type(...) | OtherType
        if (self.current < self.tokens.len and self.tokens[self.current].type == .Pipe) {
            try type_buf.appendSlice(self.allocator, " | ");
            self.current += 1;
            const next_type = try parseTypeAnnotation(self);
            if (next_type) |nt| {
                defer self.allocator.free(nt);
                try type_buf.appendSlice(self.allocator, nt);
            }
        }

        return try self.allocator.dupe(u8, type_buf.items);
    }

    // Check for generic type parameters: Type[...]
    if (self.current < self.tokens.len and self.tokens[self.current].type == .LBracket) {
        defer self.allocator.free(base_type); // Free base_type since we'll return a new string
        var type_buf = std.ArrayList(u8){};
        defer type_buf.deinit(self.allocator);

        try type_buf.appendSlice(self.allocator, base_type);
        try type_buf.append(self.allocator, '[');
        self.current += 1; // consume '['

        var bracket_depth: usize = 1;
        var need_separator = false;

        while (self.current < self.tokens.len and bracket_depth > 0) {
            const tok = self.tokens[self.current];
            switch (tok.type) {
                .LBracket => {
                    if (need_separator) try type_buf.appendSlice(self.allocator, ", ");
                    try type_buf.append(self.allocator, '[');
                    bracket_depth += 1;
                    need_separator = false;
                },
                .RBracket => {
                    try type_buf.append(self.allocator, ']');
                    bracket_depth -= 1;
                    need_separator = true;
                },
                .Comma => {
                    try type_buf.appendSlice(self.allocator, ", ");
                    need_separator = false;
                },
                .Ident => {
                    if (need_separator) try type_buf.appendSlice(self.allocator, ", ");
                    try type_buf.appendSlice(self.allocator, tok.lexeme);
                    need_separator = true;
                },
                .True => {
                    if (need_separator) try type_buf.appendSlice(self.allocator, ", ");
                    try type_buf.appendSlice(self.allocator, "True");
                    need_separator = true;
                },
                .False => {
                    if (need_separator) try type_buf.appendSlice(self.allocator, ", ");
                    try type_buf.appendSlice(self.allocator, "False");
                    need_separator = true;
                },
                .None => {
                    if (need_separator) try type_buf.appendSlice(self.allocator, ", ");
                    try type_buf.appendSlice(self.allocator, "None");
                    need_separator = true;
                },
                .String, .FString, .ByteString => {
                    // String literal in type annotation (e.g., Literal["hello"], t"{x}", b"bytes")
                    if (need_separator) try type_buf.appendSlice(self.allocator, ", ");
                    try type_buf.appendSlice(self.allocator, tok.lexeme);
                    need_separator = true;
                },
                .Number, .ComplexNumber => {
                    // Number literal in type annotation (e.g., Literal[1], 4j)
                    if (need_separator) try type_buf.appendSlice(self.allocator, ", ");
                    try type_buf.appendSlice(self.allocator, tok.lexeme);
                    need_separator = true;
                },
                .LBrace => {
                    // Set/dict literal in type annotation: a[{int}, 3]
                    if (need_separator) try type_buf.appendSlice(self.allocator, ", ");
                    try type_buf.append(self.allocator, '{');
                    need_separator = false;
                },
                .RBrace => {
                    try type_buf.append(self.allocator, '}');
                    need_separator = true;
                },
                .LParen => {
                    // Tuple in type annotation: a[(int, str), 5]
                    if (need_separator) try type_buf.appendSlice(self.allocator, ", ");
                    try type_buf.append(self.allocator, '(');
                    need_separator = false;
                },
                .RParen => {
                    try type_buf.append(self.allocator, ')');
                    need_separator = true;
                },
                .Dot => {
                    // Dotted type inside brackets: typing.Optional[t.Any]
                    try type_buf.append(self.allocator, '.');
                    need_separator = false;
                },
                .Pipe => {
                    // Union type: int | str (PEP 604)
                    try type_buf.appendSlice(self.allocator, " | ");
                    need_separator = false;
                },
                .Colon => {
                    // Type with default or key-value: dict[str, int] or Callable[..., int]
                    try type_buf.append(self.allocator, ':');
                    need_separator = false;
                },
                .Ellipsis => {
                    // Ellipsis in Callable[..., ReturnType]
                    try type_buf.appendSlice(self.allocator, "...");
                    need_separator = true;
                },
                .Star => {
                    // PEP 646 TypeVarTuple unpacking: tuple[*Y]
                    try type_buf.append(self.allocator, '*');
                    need_separator = false;
                },
                .DoubleStar => {
                    // PEP 695 ParamSpec unpacking: Generic[**P]
                    try type_buf.appendSlice(self.allocator, "**");
                    need_separator = false;
                },
                else => break, // unexpected token, stop parsing
            }
            self.current += 1;
        }

        // Check for union type AFTER generic brackets: Type[...] | OtherType
        if (self.current < self.tokens.len and self.tokens[self.current].type == .Pipe) {
            try type_buf.appendSlice(self.allocator, " | ");
            self.current += 1; // consume '|'

            // Parse the next type in the union
            const next_type = try parseTypeAnnotation(self);
            if (next_type) |nt| {
                defer self.allocator.free(nt);
                try type_buf.appendSlice(self.allocator, nt);
            }
        }

        return try self.allocator.dupe(u8, type_buf.items);
    }

    return base_type;
}

pub fn parseFunctionDef(self: *Parser) ParseError!ast.Node {
    // Parse decorators first (if any)
    var decorators = std.ArrayList(ast.Node){};
    defer decorators.deinit(self.allocator);

    // Note: Decorators should be parsed by the caller before calling this function
    // This function only handles the actual function definition
    // Check for 'async' keyword
    const is_async = self.match(.Async);
    return parseFunctionDefInternal(self, is_async);
}

/// Internal function def parser - called with is_async already determined
pub fn parseFunctionDefInternal(self: *Parser, is_async: bool) ParseError!ast.Node {
    // Track if this is a nested function
    const is_nested = self.function_depth > 0;

    _ = try self.expect(.Def);
    const name_tok = try self.expect(.Ident);

    // Parse optional PEP 695 type parameters: def func[T, U](...):
    if (self.match(.LBracket)) {
        // Skip type parameters - we don't use them in codegen yet
        var bracket_depth: usize = 1;
        while (bracket_depth > 0) {
            if (self.match(.LBracket)) {
                bracket_depth += 1;
            } else if (self.match(.RBracket)) {
                bracket_depth -= 1;
            } else {
                _ = self.advance();
            }
        }
    }

    _ = try self.expect(.LParen);

    var args = std.ArrayList(ast.Arg){};
    var return_type_alloc: ?[]const u8 = null;
    errdefer {
        // Clean up args and their allocations on error
        for (args.items) |arg| {
            if (arg.type_annotation) |ta| {
                self.allocator.free(ta);
            }
            if (arg.default) |def| {
                def.deinit(self.allocator);
                self.allocator.destroy(def);
            }
        }
        args.deinit(self.allocator);
        // Clean up return type if allocated
        if (return_type_alloc) |rt| {
            self.allocator.free(rt);
        }
    }
    var vararg_name: ?[]const u8 = null;
    var kwarg_name: ?[]const u8 = null;

    while (!self.match(.RParen)) {
        // Check for positional-only parameter marker (/)
        // Python 3.8+ uses / to mark end of positional-only parameters
        // e.g., def foo(a, /, b): means a is positional-only
        if (self.match(.Slash)) {
            // Just skip it - it's a marker, not a parameter
            _ = self.match(.Comma); // optional comma after /
            continue;
        }

        // Check for **kwargs (must check before *args since ** starts with *)
        if (self.match(.DoubleStar)) {
            const arg_name = try self.expect(.Ident);
            kwarg_name = arg_name.lexeme;

            // Skip type annotation if present (e.g., **kwargs: t.Any)
            if (self.match(.Colon)) {
                if (try parseTypeAnnotation(self)) |ta| {
                    self.allocator.free(ta);
                }
            }

            // **kwargs must be last parameter
            if (!self.match(.Comma)) {
                _ = try self.expect(.RParen);
                break;
            }
            continue;
        }

        // Check for *args or keyword-only marker (bare *)
        if (self.match(.Star)) {
            // Check if this is bare * (keyword-only marker) or *args
            if (self.current < self.tokens.len and self.tokens[self.current].type == .Ident) {
                // *args: has identifier after *
                const arg_name = try self.expect(.Ident);
                vararg_name = arg_name.lexeme;

                // Skip type annotation if present (e.g., *args: t.Any)
                if (self.match(.Colon)) {
                    if (try parseTypeAnnotation(self)) |ta| {
                        self.allocator.free(ta);
                    }
                }
            }
            // else: bare * is keyword-only marker, just skip it

            // *args or * can be followed by more parameters or **kwargs
            if (!self.match(.Comma)) {
                _ = try self.expect(.RParen);
                break;
            }
            continue;
        }

        const arg_name = try self.expect(.Ident);

        // Parse type annotation if present (e.g., : int, : str, : list[int])
        var type_annotation: ?[]const u8 = null;
        if (self.match(.Colon)) {
            type_annotation = try parseTypeAnnotation(self);
        }

        // Parse default value if present (e.g., = 0.1)
        var default_expr: ?ast.Node = null;
        if (self.match(.Eq)) {
            default_expr = try self.parseExpression();
        }
        errdefer if (default_expr) |*d| d.deinit(self.allocator);

        try args.append(self.allocator, .{
            .name = arg_name.lexeme,
            .type_annotation = type_annotation,
            .default = try self.allocNodeOpt(default_expr),
        });

        if (!self.match(.Comma)) {
            _ = try self.expect(.RParen);
            break;
        }
    }

    // Capture return type annotation if present (e.g., -> int, -> str, -> tuple[str, str])
    if (self.tokens[self.current].type == .Arrow or
        (self.tokens[self.current].type == .Minus and
            self.current + 1 < self.tokens.len and
            self.tokens[self.current + 1].type == .Gt))
    {
        // Skip -> or - >
        if (self.match(.Arrow)) {
            // Single arrow token
        } else {
            _ = self.match(.Minus);
            _ = self.match(.Gt);
        }
        // Parse the return type annotation (supports generics like tuple[str, str])
        return_type_alloc = try parseTypeAnnotation(self);
    }

    _ = try self.expect(.Colon);

    // Check if this is a one-liner function (def foo(): pass or def foo(): ...)
    var body: []ast.Node = undefined;
    if (self.peek()) |next_tok| {
        const is_oneliner = next_tok.type == .Pass or
            next_tok.type == .Ellipsis or
            next_tok.type == .Return or
            next_tok.type == .Break or
            next_tok.type == .Continue or
            next_tok.type == .Raise or
            next_tok.type == .Yield or // async def _ag(): yield
            next_tok.type == .Ident or // for assignments and expressions like self.x = v
            next_tok.type == .String; // def f(): """docstring"""

        if (is_oneliner) {
            // Parse single statement without Indent/Dedent
            self.function_depth += 1;
            const stmt = try self.parseStatement();
            self.function_depth -= 1;

            // Create body with single statement
            const body_slice = try self.allocator.alloc(ast.Node, 1);
            body_slice[0] = stmt;
            body = body_slice;
        } else {
            // Normal multi-line function
            _ = try self.expect(.Newline);
            _ = try self.expect(.Indent);

            self.function_depth += 1;
            body = try misc.parseBlock(self);
            self.function_depth -= 1;

            _ = try self.expect(.Dedent);
        }
    } else {
        return ParseError.UnexpectedEof;
    }

    // Success - transfer ownership (errdefer won't run)
    const final_args = try args.toOwnedSlice(self.allocator);
    args = std.ArrayList(ast.Arg){}; // Reset so errdefer doesn't double-free
    const final_return_type = return_type_alloc;
    return_type_alloc = null; // Clear so errdefer doesn't double-free

    return ast.Node{
        .function_def = .{
            .name = name_tok.lexeme,
            .args = final_args,
            .body = body,
            .is_async = is_async,
            .decorators = &[_]ast.Node{}, // Empty decorators for now
            .return_type = final_return_type,
            .is_nested = is_nested,
            .vararg = vararg_name,
            .kwarg = kwarg_name,
        },
    };
}

pub fn parseClassDef(self: *Parser) ParseError!ast.Node {
    _ = try self.expect(.Class);
    const name_tok = try self.expect(.Ident);

    // Parse optional PEP 695 type parameters: class Name[T, U, V]:
    if (self.match(.LBracket)) {
        // Skip type parameters - we don't use them in codegen yet
        var bracket_depth: usize = 1;
        while (bracket_depth > 0) {
            if (self.match(.LBracket)) {
                bracket_depth += 1;
            } else if (self.match(.RBracket)) {
                bracket_depth -= 1;
            } else {
                _ = self.advance();
            }
        }
    }

    // Parse optional base classes: class Dog(Animal):
    // Supports: simple names (Animal), dotted names (abc.ABC), keyword args (metaclass=ABCMeta),
    // and function calls (with_metaclass(ABCMeta)) - function calls are parsed but not stored
    var bases = std.ArrayList([]const u8){};
    var body_alloc: ?[]ast.Node = null;
    var metaclass: ?[]const u8 = null;
    errdefer {
        // Clean up bases (they're duped strings)
        for (bases.items) |base| {
            self.allocator.free(base);
        }
        bases.deinit(self.allocator);
        // Clean up body if allocated
        if (body_alloc) |b| {
            for (b) |*stmt| {
                stmt.deinit(self.allocator);
            }
            self.allocator.free(b);
        }
    }

    if (self.match(.LParen)) {
        while (!self.match(.RParen)) {
            // Check for **kwargs unpacking (e.g., class A(**d): pass)
            if (self.match(.DoubleStar)) {
                _ = try self.parseExpression(); // Parse the expression after **
                // Continue to next item or end
                if (!self.match(.Comma)) {
                    _ = try self.expect(.RParen);
                    break;
                }
                continue;
            }

            // Check for *args unpacking (e.g., class A(*bases): pass)
            if (self.match(.Star)) {
                _ = try self.parseExpression(); // Parse the expression after *
                // Continue to next item or end
                if (!self.match(.Comma)) {
                    _ = try self.expect(.RParen);
                    break;
                }
                continue;
            }

            // Check for keyword argument (e.g., metaclass=ABCMeta)
            // We need to peek ahead to see if this is name=value pattern
            if (self.current < self.tokens.len and self.tokens[self.current].type == .Ident) {
                if (self.current + 1 < self.tokens.len and self.tokens[self.current + 1].type == .Eq) {
                    // Capture keyword argument: name = expression
                    const kw_name = (try self.expect(.Ident)).lexeme;
                    _ = try self.expect(.Eq); // =
                    const kw_value = try self.parseExpression();
                    // If this is metaclass=X, capture the value
                    if (std.mem.eql(u8, kw_name, "metaclass")) {
                        if (kw_value == .name) {
                            metaclass = kw_value.name.id;
                        } else if (kw_value == .attribute) {
                            // For abc.ABCMeta, extract just ABCMeta
                            metaclass = kw_value.attribute.attr;
                        }
                    }
                    // Continue to next item or end
                    if (!self.match(.Comma)) {
                        _ = try self.expect(.RParen);
                        break;
                    }
                    continue;
                }
            }

            // Parse base class as a full expression
            // This handles: simple names, dotted names, and function calls
            const expr = try self.parseExpression();

            // Extract name from expression if it's a simple name or attribute access
            const base_name = extractBaseName(self, expr);
            if (base_name) |name| {
                try bases.append(self.allocator, name);
            }
            // If it's a function call or other complex expression, we skip adding it to bases
            // (codegen won't use it, but at least parsing succeeds)

            if (!self.match(.Comma)) {
                _ = try self.expect(.RParen);
                break;
            }
        }
    }

    _ = try self.expect(.Colon);

    // Check if this is a one-liner class (class C: pass or class C: ... or class C: """docstring""")
    if (self.peek()) |next_tok| {
        const is_oneliner = next_tok.type == .Pass or
            next_tok.type == .Ellipsis or
            next_tok.type == .Ident or // for simple statements
            next_tok.type == .String; // for docstrings: class C: """doc"""

        if (is_oneliner) {
            const stmt = try self.parseStatement();
            const body_slice = try self.allocator.alloc(ast.Node, 1);
            body_slice[0] = stmt;
            body_alloc = body_slice;
        } else {
            _ = try self.expect(.Newline);
            _ = try self.expect(.Indent);
            body_alloc = try misc.parseBlock(self);
            _ = try self.expect(.Dedent);
        }
    } else {
        return ParseError.UnexpectedEof;
    }

    // Success - transfer ownership
    const final_bases = try bases.toOwnedSlice(self.allocator);
    bases = std.ArrayList([]const u8){}; // Reset so errdefer doesn't double-free
    const final_body = body_alloc.?;
    body_alloc = null; // Clear so errdefer doesn't double-free

    return ast.Node{
        .class_def = .{
            .name = name_tok.lexeme,
            .bases = final_bases,
            .body = final_body,
            .metaclass = metaclass,
        },
    };
}
