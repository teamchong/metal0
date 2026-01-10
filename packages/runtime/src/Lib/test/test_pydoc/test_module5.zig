//! test.test_pydoc.test_topics - Tests for topic-based help
//! Tests the help topics system for keywords, symbols, and concepts.

const std = @import("std");
const testing = std.testing;

/// Categories of help topics
pub const TopicCategory = enum {
    keywords,
    symbols,
    modules,
    topics,

    pub fn displayName(self: TopicCategory) []const u8 {
        return switch (self) {
            .keywords => "KEYWORDS",
            .symbols => "SYMBOLS",
            .modules => "MODULES",
            .topics => "TOPICS",
        };
    }
};

/// A help topic entry
pub const Topic = struct {
    name: []const u8,
    aliases: []const []const u8,
    category: TopicCategory,
    short_desc: []const u8,
    long_desc: []const u8,
    examples: []const Example,
    see_also: []const []const u8,

    pub const Example = struct {
        code: []const u8,
        description: []const u8,
    };

    pub fn init(name: []const u8, category: TopicCategory) Topic {
        return .{
            .name = name,
            .aliases = &.{},
            .category = category,
            .short_desc = "",
            .long_desc = "",
            .examples = &.{},
            .see_also = &.{},
        };
    }

    pub fn withDescription(self: Topic, short: []const u8, long: []const u8) Topic {
        var result = self;
        result.short_desc = short;
        result.long_desc = long;
        return result;
    }

    pub fn matches(self: Topic, query: []const u8) bool {
        if (std.ascii.eqlIgnoreCase(self.name, query)) return true;
        for (self.aliases) |alias| {
            if (std.ascii.eqlIgnoreCase(alias, query)) return true;
        }
        return false;
    }
};

/// Python keyword topics
pub const KeywordTopics = struct {
    pub const @"if" = Topic.init("if", .keywords)
        .withDescription(
        "Conditional execution",
        "The if statement is used for conditional execution.",
    );

    pub const @"for" = Topic.init("for", .keywords)
        .withDescription(
        "Iteration over a sequence",
        "The for statement is used to iterate over elements of a sequence.",
    );

    pub const @"while" = Topic.init("while", .keywords)
        .withDescription(
        "Loop while condition is true",
        "The while statement is used for repeated execution as long as a condition is true.",
    );

    pub const def = Topic.init("def", .keywords)
        .withDescription(
        "Define a function",
        "The def statement defines a function object and binds it to a name.",
    );

    pub const class = Topic.init("class", .keywords)
        .withDescription(
        "Define a class",
        "The class statement creates a new class object.",
    );

    pub const @"return" = Topic.init("return", .keywords)
        .withDescription(
        "Return from a function",
        "The return statement exits a function and optionally returns a value.",
    );

    pub const import = Topic.init("import", .keywords)
        .withDescription(
        "Import a module",
        "The import statement finds and loads a module.",
    );

    pub const @"try" = Topic.init("try", .keywords)
        .withDescription(
        "Exception handling",
        "The try statement specifies exception handlers.",
    );

    pub const all = &[_]Topic{
        @"if",
        @"for",
        @"while",
        def,
        class,
        @"return",
        import,
        @"try",
    };
};

/// Python symbol topics
pub const SymbolTopics = struct {
    pub const plus = Topic.init("+", .symbols)
        .withDescription("Addition operator", "Adds two numbers or concatenates sequences.");

    pub const minus = Topic.init("-", .symbols)
        .withDescription("Subtraction operator", "Subtracts one number from another or negates.");

    pub const star = Topic.init("*", .symbols)
        .withDescription("Multiplication operator", "Multiplies numbers or repeats sequences.");

    pub const slash = Topic.init("/", .symbols)
        .withDescription("Division operator", "Divides two numbers (true division).");

    pub const double_slash = Topic.init("//", .symbols)
        .withDescription("Floor division", "Divides and rounds down to nearest integer.");

    pub const percent = Topic.init("%", .symbols)
        .withDescription("Modulo operator", "Returns remainder of division.");

    pub const double_star = Topic.init("**", .symbols)
        .withDescription("Power operator", "Raises a number to a power.");

    pub const at = Topic.init("@", .symbols)
        .withDescription("Decorator/matrix multiplication", "Applies decorator or matrix multiply.");

    pub const all = &[_]Topic{
        plus,
        minus,
        star,
        slash,
        double_slash,
        percent,
        double_star,
        at,
    };
};

/// General help topics
pub const GeneralTopics = struct {
    pub const TRUTHVALUE = Topic.init("TRUTHVALUE", .topics)
        .withDescription(
        "Truth value testing",
        "Any object can be tested for truth value.",
    );

    pub const COMPARISON = Topic.init("COMPARISON", .topics)
        .withDescription(
        "Comparison operations",
        "There are eight comparison operations in Python.",
    );

    pub const SEQUENCES = Topic.init("SEQUENCES", .topics)
        .withDescription(
        "Sequence types",
        "There are three basic sequence types: list, tuple, and range.",
    );

    pub const MAPPINGS = Topic.init("MAPPINGS", .topics)
        .withDescription(
        "Mapping types",
        "A mapping object maps hashable values to arbitrary objects.",
    );

    pub const FUNCTIONS = Topic.init("FUNCTIONS", .topics)
        .withDescription(
        "Function definitions",
        "A function definition defines a user-defined function object.",
    );

    pub const CLASSES = Topic.init("CLASSES", .topics)
        .withDescription(
        "Class definitions",
        "A class definition defines a class object.",
    );

    pub const all = &[_]Topic{
        TRUTHVALUE,
        COMPARISON,
        SEQUENCES,
        MAPPINGS,
        FUNCTIONS,
        CLASSES,
    };
};

/// Topic registry and lookup
pub const TopicRegistry = struct {
    allocator: std.mem.Allocator,
    keywords: []const Topic,
    symbols: []const Topic,
    topics: []const Topic,

    pub fn init(allocator: std.mem.Allocator) TopicRegistry {
        return .{
            .allocator = allocator,
            .keywords = KeywordTopics.all,
            .symbols = SymbolTopics.all,
            .topics = GeneralTopics.all,
        };
    }

    pub fn lookup(self: TopicRegistry, query: []const u8) ?Topic {
        for (self.keywords) |topic| {
            if (topic.matches(query)) return topic;
        }
        for (self.symbols) |topic| {
            if (topic.matches(query)) return topic;
        }
        for (self.topics) |topic| {
            if (topic.matches(query)) return topic;
        }
        return null;
    }

    pub fn search(self: TopicRegistry, pattern: []const u8) []const Topic {
        _ = self;
        _ = pattern;
        // Would return matching topics
        return &.{};
    }

    pub fn listCategory(self: TopicRegistry, category: TopicCategory) []const Topic {
        return switch (category) {
            .keywords => self.keywords,
            .symbols => self.symbols,
            .topics => self.topics,
            .modules => &.{},
        };
    }

    pub fn allTopics(self: TopicRegistry) usize {
        return self.keywords.len + self.symbols.len + self.topics.len;
    }
};

/// Topic renderer
pub const TopicRenderer = struct {
    width: u32 = 80,

    pub fn render(self: TopicRenderer, topic: Topic) []const u8 {
        _ = self;
        return topic.long_desc;
    }

    pub fn renderList(self: TopicRenderer, topics: []const Topic) !void {
        _ = self;
        _ = topics;
        // Would format topic list
    }
};

// Tests
test "topic_category_display_name" {
    try testing.expectEqualStrings("KEYWORDS", TopicCategory.keywords.displayName());
    try testing.expectEqualStrings("SYMBOLS", TopicCategory.symbols.displayName());
    try testing.expectEqualStrings("TOPICS", TopicCategory.topics.displayName());
}

test "topic_init" {
    const topic = Topic.init("test", .keywords);
    try testing.expectEqualStrings("test", topic.name);
    try testing.expectEqual(TopicCategory.keywords, topic.category);
}

test "topic_with_description" {
    const topic = Topic.init("test", .keywords)
        .withDescription("Short", "Long description here");
    try testing.expectEqualStrings("Short", topic.short_desc);
    try testing.expectEqualStrings("Long description here", topic.long_desc);
}

test "topic_matches_name" {
    const topic = Topic.init("if", .keywords);
    try testing.expect(topic.matches("if"));
    try testing.expect(topic.matches("IF"));
    try testing.expect(!topic.matches("for"));
}

test "keyword_topics_if" {
    const topic = KeywordTopics.@"if";
    try testing.expectEqualStrings("if", topic.name);
    try testing.expectEqual(TopicCategory.keywords, topic.category);
}

test "keyword_topics_for" {
    const topic = KeywordTopics.@"for";
    try testing.expectEqualStrings("for", topic.name);
}

test "keyword_topics_count" {
    try testing.expectEqual(@as(usize, 8), KeywordTopics.all.len);
}

test "symbol_topics_plus" {
    const topic = SymbolTopics.plus;
    try testing.expectEqualStrings("+", topic.name);
    try testing.expectEqual(TopicCategory.symbols, topic.category);
}

test "symbol_topics_count" {
    try testing.expectEqual(@as(usize, 8), SymbolTopics.all.len);
}

test "general_topics_truthvalue" {
    const topic = GeneralTopics.TRUTHVALUE;
    try testing.expectEqualStrings("TRUTHVALUE", topic.name);
}

test "general_topics_count" {
    try testing.expectEqual(@as(usize, 6), GeneralTopics.all.len);
}

test "topic_registry_init" {
    const registry = TopicRegistry.init(testing.allocator);
    try testing.expect(registry.allTopics() > 0);
}

test "topic_registry_lookup_keyword" {
    const registry = TopicRegistry.init(testing.allocator);
    const result = registry.lookup("if");
    try testing.expect(result != null);
    try testing.expectEqualStrings("if", result.?.name);
}

test "topic_registry_lookup_symbol" {
    const registry = TopicRegistry.init(testing.allocator);
    const result = registry.lookup("+");
    try testing.expect(result != null);
    try testing.expectEqualStrings("+", result.?.name);
}

test "topic_registry_lookup_unknown" {
    const registry = TopicRegistry.init(testing.allocator);
    const result = registry.lookup("nonexistent");
    try testing.expectEqual(@as(?Topic, null), result);
}

test "topic_registry_list_category" {
    const registry = TopicRegistry.init(testing.allocator);
    const keywords = registry.listCategory(.keywords);
    try testing.expectEqual(@as(usize, 8), keywords.len);
}

test "topic_renderer_init" {
    const renderer = TopicRenderer{ .width = 120 };
    try testing.expectEqual(@as(u32, 120), renderer.width);
}
