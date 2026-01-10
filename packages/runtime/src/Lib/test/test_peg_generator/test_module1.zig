//! test.test_peg_generator.test_grammar - Grammar definition and parsing tests
//!
//! This module tests the grammar definition structures used by the PEG parser generator.
//! It includes tests for rule definitions, alternatives, sequences, and grammar validation.

const std = @import("std");

/// Represents a single grammar rule
pub const Rule = struct {
    name: []const u8,
    alternatives: []const Alternative,
    is_left_recursive: bool = false,
    memo_key: ?usize = null,

    pub fn init(name: []const u8, alternatives: []const Alternative) Rule {
        return .{
            .name = name,
            .alternatives = alternatives,
        };
    }

    pub fn isTerminal(self: Rule) bool {
        if (self.alternatives.len != 1) return false;
        const alt = self.alternatives[0];
        if (alt.items.len != 1) return false;
        return alt.items[0] == .literal or alt.items[0] == .char_class;
    }

    pub fn hasAction(self: Rule) bool {
        for (self.alternatives) |alt| {
            if (alt.action != null) return true;
        }
        return false;
    }
};

/// Represents an alternative in a rule (separated by |)
pub const Alternative = struct {
    items: []const Item,
    action: ?[]const u8 = null,
    lookahead: Lookahead = .none,

    pub const Lookahead = enum {
        none,
        positive, // &
        negative, // !
    };

    pub fn init(items: []const Item) Alternative {
        return .{ .items = items };
    }

    pub fn withAction(items: []const Item, action: []const u8) Alternative {
        return .{ .items = items, .action = action };
    }

    pub fn isEmpty(self: Alternative) bool {
        return self.items.len == 0;
    }
};

/// Represents a single item in a sequence
pub const Item = union(enum) {
    rule_ref: []const u8,
    literal: []const u8,
    char_class: CharClass,
    optional: *const Item,
    zero_or_more: *const Item,
    one_or_more: *const Item,
    group: []const Alternative,

    pub fn isOptional(self: Item) bool {
        return self == .optional;
    }

    pub fn isRepeating(self: Item) bool {
        return self == .zero_or_more or self == .one_or_more;
    }
};

/// Character class for matching ranges like [a-z]
pub const CharClass = struct {
    ranges: []const Range,
    negated: bool = false,

    pub const Range = struct {
        start: u8,
        end: u8,

        pub fn contains(self: Range, c: u8) bool {
            return c >= self.start and c <= self.end;
        }
    };

    pub fn matches(self: CharClass, c: u8) bool {
        var matched = false;
        for (self.ranges) |range| {
            if (range.contains(c)) {
                matched = true;
                break;
            }
        }
        return if (self.negated) !matched else matched;
    }

    pub fn digit() CharClass {
        return .{ .ranges = &[_]Range{.{ .start = '0', .end = '9' }} };
    }

    pub fn alpha() CharClass {
        return .{ .ranges = &[_]Range{
            .{ .start = 'a', .end = 'z' },
            .{ .start = 'A', .end = 'Z' },
        } };
    }

    pub fn alphaNumeric() CharClass {
        return .{ .ranges = &[_]Range{
            .{ .start = 'a', .end = 'z' },
            .{ .start = 'A', .end = 'Z' },
            .{ .start = '0', .end = '9' },
        } };
    }
};

/// Complete grammar definition
pub const Grammar = struct {
    rules: []const Rule,
    start_rule: []const u8,
    allocator: std.mem.Allocator,

    pub fn init(allocator: std.mem.Allocator, rules: []const Rule, start_rule: []const u8) Grammar {
        return .{
            .rules = rules,
            .start_rule = start_rule,
            .allocator = allocator,
        };
    }

    pub fn findRule(self: Grammar, name: []const u8) ?Rule {
        for (self.rules) |rule| {
            if (std.mem.eql(u8, rule.name, name)) {
                return rule;
            }
        }
        return null;
    }

    pub fn validate(self: Grammar) !void {
        // Check start rule exists
        if (self.findRule(self.start_rule) == null) {
            return error.StartRuleNotFound;
        }

        // Check all rule references are valid
        for (self.rules) |rule| {
            for (rule.alternatives) |alt| {
                for (alt.items) |item| {
                    try self.validateItem(item);
                }
            }
        }
    }

    fn validateItem(self: Grammar, item: Item) !void {
        switch (item) {
            .rule_ref => |name| {
                if (self.findRule(name) == null) {
                    return error.UndefinedRule;
                }
            },
            .optional, .zero_or_more, .one_or_more => |inner| {
                try self.validateItem(inner.*);
            },
            .group => |alts| {
                for (alts) |alt| {
                    for (alt.items) |inner| {
                        try self.validateItem(inner);
                    }
                }
            },
            else => {},
        }
    }

    pub fn computeFirstSet(self: Grammar, rule_name: []const u8) !std.ArrayList([]const u8) {
        var first_set = std.ArrayList([]const u8).init(self.allocator);
        const rule = self.findRule(rule_name) orelse return error.UndefinedRule;

        for (rule.alternatives) |alt| {
            if (alt.items.len > 0) {
                switch (alt.items[0]) {
                    .literal => |lit| try first_set.append(lit),
                    .rule_ref => |ref| {
                        var inner = try self.computeFirstSet(ref);
                        defer inner.deinit();
                        try first_set.appendSlice(inner.items);
                    },
                    else => {},
                }
            }
        }
        return first_set;
    }

    pub fn detectLeftRecursion(self: Grammar) bool {
        for (self.rules) |rule| {
            if (self.isLeftRecursive(rule.name, rule.name)) {
                return true;
            }
        }
        return false;
    }

    fn isLeftRecursive(self: Grammar, start: []const u8, current: []const u8) bool {
        const rule = self.findRule(current) orelse return false;
        for (rule.alternatives) |alt| {
            if (alt.items.len > 0) {
                switch (alt.items[0]) {
                    .rule_ref => |ref| {
                        if (std.mem.eql(u8, ref, start)) return true;
                        if (self.isLeftRecursive(start, ref)) return true;
                    },
                    else => {},
                }
            }
        }
        return false;
    }
};

/// Grammar builder for fluent construction
pub const GrammarBuilder = struct {
    rules: std.ArrayList(Rule),
    allocator: std.mem.Allocator,

    pub fn init(allocator: std.mem.Allocator) GrammarBuilder {
        return .{
            .rules = std.ArrayList(Rule).init(allocator),
            .allocator = allocator,
        };
    }

    pub fn deinit(self: *GrammarBuilder) void {
        self.rules.deinit();
    }

    pub fn addRule(self: *GrammarBuilder, name: []const u8, alternatives: []const Alternative) !*GrammarBuilder {
        try self.rules.append(Rule.init(name, alternatives));
        return self;
    }

    pub fn build(self: *GrammarBuilder, start_rule: []const u8) Grammar {
        return Grammar.init(self.allocator, self.rules.items, start_rule);
    }
};

// Tests
test "grammar_rule_basic" {
    const alt = Alternative.init(&[_]Item{.{ .literal = "test" }});
    const rule = Rule.init("test_rule", &[_]Alternative{alt});
    try std.testing.expectEqualStrings("test_rule", rule.name);
    try std.testing.expect(!rule.is_left_recursive);
}

test "grammar_rule_terminal" {
    const alt = Alternative.init(&[_]Item{.{ .literal = "keyword" }});
    const rule = Rule.init("KEYWORD", &[_]Alternative{alt});
    try std.testing.expect(rule.isTerminal());
}

test "grammar_alternative_with_action" {
    const alt = Alternative.withAction(
        &[_]Item{ .{ .rule_ref = "expr" }, .{ .literal = "+" }, .{ .rule_ref = "term" } },
        "return left + right",
    );
    try std.testing.expect(alt.action != null);
    try std.testing.expectEqualStrings("return left + right", alt.action.?);
}

test "grammar_char_class_digit" {
    const digit_class = CharClass.digit();
    try std.testing.expect(digit_class.matches('5'));
    try std.testing.expect(!digit_class.matches('a'));
}

test "grammar_char_class_alpha" {
    const alpha_class = CharClass.alpha();
    try std.testing.expect(alpha_class.matches('a'));
    try std.testing.expect(alpha_class.matches('Z'));
    try std.testing.expect(!alpha_class.matches('5'));
}

test "grammar_char_class_negated" {
    const not_digit = CharClass{
        .ranges = &[_]CharClass.Range{.{ .start = '0', .end = '9' }},
        .negated = true,
    };
    try std.testing.expect(!not_digit.matches('5'));
    try std.testing.expect(not_digit.matches('a'));
}

test "grammar_find_rule" {
    const rule1 = Rule.init("expr", &[_]Alternative{Alternative.init(&[_]Item{.{ .literal = "x" }})});
    const rule2 = Rule.init("term", &[_]Alternative{Alternative.init(&[_]Item{.{ .literal = "y" }})});
    const grammar = Grammar{
        .rules = &[_]Rule{ rule1, rule2 },
        .start_rule = "expr",
        .allocator = std.testing.allocator,
    };

    const found = grammar.findRule("term");
    try std.testing.expect(found != null);
    try std.testing.expectEqualStrings("term", found.?.name);

    try std.testing.expect(grammar.findRule("nonexistent") == null);
}

test "grammar_validate_success" {
    const expr_alt = Alternative.init(&[_]Item{.{ .literal = "number" }});
    const rule = Rule.init("expr", &[_]Alternative{expr_alt});
    const grammar = Grammar{
        .rules = &[_]Rule{rule},
        .start_rule = "expr",
        .allocator = std.testing.allocator,
    };

    try grammar.validate();
}

test "grammar_validate_missing_start" {
    const rule = Rule.init("expr", &[_]Alternative{Alternative.init(&[_]Item{.{ .literal = "x" }})});
    const grammar = Grammar{
        .rules = &[_]Rule{rule},
        .start_rule = "missing",
        .allocator = std.testing.allocator,
    };

    try std.testing.expectError(error.StartRuleNotFound, grammar.validate());
}

test "grammar_builder_fluent" {
    var builder = GrammarBuilder.init(std.testing.allocator);
    defer builder.deinit();

    const alt1 = Alternative.init(&[_]Item{.{ .literal = "+" }});
    const alt2 = Alternative.init(&[_]Item{.{ .literal = "-" }});

    _ = try builder.addRule("op", &[_]Alternative{ alt1, alt2 });
    const grammar = builder.build("op");

    try std.testing.expectEqualStrings("op", grammar.start_rule);
    try std.testing.expectEqual(@as(usize, 1), grammar.rules.len);
}

test "grammar_item_optional" {
    const inner = Item{ .literal = "opt" };
    const optional = Item{ .optional = &inner };
    try std.testing.expect(optional.isOptional());
    try std.testing.expect(!inner.isOptional());
}

test "grammar_item_repeating" {
    const inner = Item{ .literal = "rep" };
    const zero_more = Item{ .zero_or_more = &inner };
    const one_more = Item{ .one_or_more = &inner };

    try std.testing.expect(zero_more.isRepeating());
    try std.testing.expect(one_more.isRepeating());
    try std.testing.expect(!inner.isRepeating());
}

test "grammar_alternative_empty" {
    const empty_alt = Alternative.init(&[_]Item{});
    try std.testing.expect(empty_alt.isEmpty());

    const non_empty = Alternative.init(&[_]Item{.{ .literal = "x" }});
    try std.testing.expect(!non_empty.isEmpty());
}

test "grammar_rule_has_action" {
    const alt_no_action = Alternative.init(&[_]Item{.{ .literal = "x" }});
    const rule_no_action = Rule.init("r1", &[_]Alternative{alt_no_action});
    try std.testing.expect(!rule_no_action.hasAction());

    const alt_with_action = Alternative.withAction(&[_]Item{.{ .literal = "x" }}, "action");
    const rule_with_action = Rule.init("r2", &[_]Alternative{alt_with_action});
    try std.testing.expect(rule_with_action.hasAction());
}
