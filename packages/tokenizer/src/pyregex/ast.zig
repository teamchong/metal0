/// Abstract Syntax Tree for regular expressions
/// Represents parsed regex patterns before NFA compilation
const std = @import("std");

/// AST node type
pub const Expr = union(enum) {
    // Literals
    char: u8,           // Literal character: 'a'
    any: void,          // Dot: '.'

    // Character classes
    digit: void,        // \d
    not_digit: void,    // \D
    word: void,         // \w
    not_word: void,     // \W
    whitespace: void,   // \s
    not_whitespace: void, // \S

    // Custom character class: [abc] or [a-z] or [^a-z]
    class: CharClass,

    // Anchors
    start: void,        // ^
    end: void,          // $
    word_boundary: void, // \b
    not_word_boundary: void, // \B

    // Quantifiers (wraps sub-expression)
    star: *Expr,        // e*  (0 or more)
    plus: *Expr,        // e+  (1 or more)
    question: *Expr,    // e?  (0 or 1)
    repeat: Repeat,     // e{n,m}

    // Composition
    concat: Concat,     // e1 e2 e3 (sequence)
    alt: Alt,           // e1 | e2 | e3 (alternation)

    // Groups
    group: *Expr,       // (e) capturing group

    /// Character class [abc] or [^abc] or [a-z]
    pub const CharClass = struct {
        negated: bool,
        ranges: []Range,

        pub const Range = struct {
            start: u8,
            end: u8, // inclusive
        };
    };

    /// Repeat quantifier {n} or {n,m}
    pub const Repeat = struct {
        expr: *Expr,
        min: usize,
        max: ?usize, // null means unbounded
    };

    /// Concatenation: ab or abc or e1 e2 e3
    pub const Concat = struct {
        exprs: []Expr,
    };

    /// Alternation: a|b|c or e1 | e2 | e3
    pub const Alt = struct {
        exprs: []Expr,
    };

    pub fn deinit(self: *Expr, allocator: std.mem.Allocator) void {
        switch (self.*) {
            .star, .plus, .question, .group => |sub| {
                sub.deinit(allocator);
                allocator.destroy(sub);
            },
            .repeat => |r| {
                r.expr.deinit(allocator);
                allocator.destroy(r.expr);
            },
            .concat => |c| {
                for (c.exprs) |*e| {
                    e.deinit(allocator);
                }
                allocator.free(c.exprs);
            },
            .alt => |a| {
                for (a.exprs) |*e| {
                    e.deinit(allocator);
                }
                allocator.free(a.exprs);
            },
            .class => |c| {
                allocator.free(c.ranges);
            },
            else => {},
        }
    }
};

/// Full AST (owns all expressions)
pub const AST = struct {
    root: Expr,
    allocator: std.mem.Allocator,

    pub fn init(allocator: std.mem.Allocator, root: Expr) AST {
        return .{
            .root = root,
            .allocator = allocator,
        };
    }

    pub fn deinit(self: *AST) void {
        self.root.deinit(self.allocator);
    }
};
