//! test.test_pydoc.test_help - Tests for the help() function
//! Tests the interactive help system that pydoc provides through help().

const std = @import("std");
const testing = std.testing;

/// Represents a help topic that can be queried
pub const HelpTopic = struct {
    name: []const u8,
    category: TopicCategory,
    content: []const u8,
    keywords: []const []const u8,
    related: []const []const u8,

    pub const TopicCategory = enum {
        builtin,
        module,
        class_type,
        function,
        method,
        keyword,
        symbol,
    };

    pub fn init(name: []const u8, category: TopicCategory) HelpTopic {
        return .{
            .name = name,
            .category = category,
            .content = "",
            .keywords = &.{},
            .related = &.{},
        };
    }

    pub fn withContent(self: HelpTopic, content: []const u8) HelpTopic {
        var result = self;
        result.content = content;
        return result;
    }

    pub fn matches(self: HelpTopic, query: []const u8) bool {
        if (std.mem.eql(u8, self.name, query)) return true;
        for (self.keywords) |kw| {
            if (std.mem.eql(u8, kw, query)) return true;
        }
        return false;
    }
};

/// Configuration for help output formatting
pub const HelpConfig = struct {
    max_width: u32 = 80,
    indent_size: u32 = 4,
    show_source_path: bool = true,
    show_signature: bool = true,
    show_docstring: bool = true,
    show_methods: bool = true,
    show_attributes: bool = true,
    pager: ?[]const u8 = null,

    pub const default = HelpConfig{};

    pub fn withWidth(self: HelpConfig, width: u32) HelpConfig {
        var result = self;
        result.max_width = width;
        return result;
    }

    pub fn withPager(self: HelpConfig, pager: []const u8) HelpConfig {
        var result = self;
        result.pager = pager;
        return result;
    }
};

/// Interactive help session state
pub const HelpSession = struct {
    allocator: std.mem.Allocator,
    config: HelpConfig,
    history: std.ArrayList([]const u8),
    current_topic: ?HelpTopic,

    pub fn init(allocator: std.mem.Allocator) HelpSession {
        return .{
            .allocator = allocator,
            .config = HelpConfig.default,
            .history = std.ArrayList([]const u8).init(allocator),
            .current_topic = null,
        };
    }

    pub fn deinit(self: *HelpSession) void {
        self.history.deinit();
    }

    pub fn lookup(self: *HelpSession, query: []const u8) !?HelpTopic {
        // Record in history
        try self.history.append(query);

        // Built-in topics
        const builtins = [_]HelpTopic{
            HelpTopic.init("print", .builtin).withContent("Print objects to the text stream file."),
            HelpTopic.init("len", .builtin).withContent("Return the number of items in a container."),
            HelpTopic.init("range", .builtin).withContent("Return an object that produces a sequence of integers."),
            HelpTopic.init("type", .builtin).withContent("Return the type of an object."),
            HelpTopic.init("str", .class_type).withContent("String type and constructor."),
            HelpTopic.init("int", .class_type).withContent("Integer type and constructor."),
            HelpTopic.init("list", .class_type).withContent("List type and constructor."),
            HelpTopic.init("dict", .class_type).withContent("Dictionary type and constructor."),
        };

        for (builtins) |topic| {
            if (topic.matches(query)) {
                self.current_topic = topic;
                return topic;
            }
        }

        return null;
    }

    pub fn getHistory(self: HelpSession) []const []const u8 {
        return self.history.items;
    }
};

/// Formats help text for display
pub const HelpFormatter = struct {
    config: HelpConfig,
    output: std.ArrayList(u8),
    allocator: std.mem.Allocator,

    pub fn init(allocator: std.mem.Allocator, config: HelpConfig) HelpFormatter {
        return .{
            .config = config,
            .output = std.ArrayList(u8).init(allocator),
            .allocator = allocator,
        };
    }

    pub fn deinit(self: *HelpFormatter) void {
        self.output.deinit();
    }

    pub fn formatTopic(self: *HelpFormatter, topic: HelpTopic) ![]const u8 {
        self.output.clearRetainingCapacity();
        const writer = self.output.writer();

        // Header
        try writer.print("Help on {s} in module builtins:\n\n", .{topic.name});

        // Category
        try writer.print("TYPE: {s}\n\n", .{@tagName(topic.category)});

        // Content
        if (topic.content.len > 0) {
            try writer.print("DESCRIPTION:\n", .{});
            try self.writeIndented(topic.content);
            try writer.writeByte('\n');
        }

        return self.output.items;
    }

    fn writeIndented(self: *HelpFormatter, text: []const u8) !void {
        const writer = self.output.writer();
        var lines = std.mem.splitScalar(u8, text, '\n');
        while (lines.next()) |line| {
            for (0..self.config.indent_size) |_| {
                try writer.writeByte(' ');
            }
            try writer.print("{s}\n", .{line});
        }
    }
};

// Test functions
test "help_topic_creation" {
    const topic = HelpTopic.init("print", .builtin);
    try testing.expectEqualStrings("print", topic.name);
    try testing.expectEqual(HelpTopic.TopicCategory.builtin, topic.category);
}

test "help_topic_with_content" {
    const topic = HelpTopic.init("len", .builtin)
        .withContent("Returns the length of an object.");
    try testing.expectEqualStrings("Returns the length of an object.", topic.content);
}

test "help_topic_matches" {
    const topic = HelpTopic.init("str", .class_type);
    try testing.expect(topic.matches("str"));
    try testing.expect(!topic.matches("int"));
}

test "help_config_defaults" {
    const config = HelpConfig.default;
    try testing.expectEqual(@as(u32, 80), config.max_width);
    try testing.expectEqual(@as(u32, 4), config.indent_size);
    try testing.expect(config.show_docstring);
}

test "help_config_with_width" {
    const config = HelpConfig.default.withWidth(120);
    try testing.expectEqual(@as(u32, 120), config.max_width);
}

test "help_session_init" {
    var session = HelpSession.init(testing.allocator);
    defer session.deinit();
    try testing.expectEqual(@as(?HelpTopic, null), session.current_topic);
}

test "help_session_lookup_builtin" {
    var session = HelpSession.init(testing.allocator);
    defer session.deinit();
    const result = try session.lookup("print");
    try testing.expect(result != null);
    try testing.expectEqualStrings("print", result.?.name);
}

test "help_session_lookup_unknown" {
    var session = HelpSession.init(testing.allocator);
    defer session.deinit();
    const result = try session.lookup("nonexistent_module");
    try testing.expectEqual(@as(?HelpTopic, null), result);
}

test "help_session_history" {
    var session = HelpSession.init(testing.allocator);
    defer session.deinit();
    _ = try session.lookup("print");
    _ = try session.lookup("len");
    const history = session.getHistory();
    try testing.expectEqual(@as(usize, 2), history.len);
}

test "help_formatter_init" {
    var formatter = HelpFormatter.init(testing.allocator, HelpConfig.default);
    defer formatter.deinit();
    try testing.expectEqual(@as(usize, 0), formatter.output.items.len);
}

test "help_formatter_format_topic" {
    var formatter = HelpFormatter.init(testing.allocator, HelpConfig.default);
    defer formatter.deinit();
    const topic = HelpTopic.init("print", .builtin)
        .withContent("Print to stdout.");
    const output = try formatter.formatTopic(topic);
    try testing.expect(std.mem.indexOf(u8, output, "print") != null);
    try testing.expect(std.mem.indexOf(u8, output, "builtin") != null);
}
