//! test.test_pydoc.test_search - Tests for documentation search
//! Tests the documentation search functionality in pydoc.

const std = @import("std");
const testing = std.testing;

/// Search result types
pub const ResultType = enum {
    module,
    class_type,
    function,
    method,
    attribute,
    topic,
    keyword,

    pub fn displayName(self: ResultType) []const u8 {
        return switch (self) {
            .module => "module",
            .class_type => "class",
            .function => "function",
            .method => "method",
            .attribute => "attribute",
            .topic => "topic",
            .keyword => "keyword",
        };
    }

    pub fn weight(self: ResultType) u32 {
        return switch (self) {
            .module => 100,
            .class_type => 90,
            .function => 80,
            .method => 70,
            .attribute => 60,
            .topic => 50,
            .keyword => 40,
        };
    }
};

/// A single search result
pub const SearchResult = struct {
    name: []const u8,
    qualified_name: []const u8,
    result_type: ResultType,
    module: ?[]const u8,
    docstring: ?[]const u8,
    score: f32,
    match_positions: []const usize,

    pub fn init(name: []const u8, result_type: ResultType) SearchResult {
        return .{
            .name = name,
            .qualified_name = name,
            .result_type = result_type,
            .module = null,
            .docstring = null,
            .score = 0.0,
            .match_positions = &.{},
        };
    }

    pub fn withScore(self: SearchResult, score: f32) SearchResult {
        var result = self;
        result.score = score;
        return result;
    }

    pub fn withModule(self: SearchResult, module: []const u8) SearchResult {
        var result = self;
        result.module = module;
        return result;
    }

    pub fn withDocstring(self: SearchResult, doc: []const u8) SearchResult {
        var result = self;
        result.docstring = doc;
        return result;
    }

    pub fn shortDoc(self: SearchResult) ?[]const u8 {
        if (self.docstring) |doc| {
            var lines = std.mem.splitScalar(u8, doc, '\n');
            return lines.first();
        }
        return null;
    }
};

/// Search query configuration
pub const SearchQuery = struct {
    text: []const u8,
    case_sensitive: bool = false,
    whole_word: bool = false,
    search_docstrings: bool = true,
    search_names: bool = true,
    type_filter: ?ResultType = null,
    module_filter: ?[]const u8 = null,
    max_results: u32 = 50,

    pub fn init(text: []const u8) SearchQuery {
        return .{ .text = text };
    }

    pub fn caseSensitive(self: SearchQuery) SearchQuery {
        var result = self;
        result.case_sensitive = true;
        return result;
    }

    pub fn wholeWord(self: SearchQuery) SearchQuery {
        var result = self;
        result.whole_word = true;
        return result;
    }

    pub fn filterType(self: SearchQuery, t: ResultType) SearchQuery {
        var result = self;
        result.type_filter = t;
        return result;
    }

    pub fn filterModule(self: SearchQuery, m: []const u8) SearchQuery {
        var result = self;
        result.module_filter = m;
        return result;
    }

    pub fn limit(self: SearchQuery, max: u32) SearchQuery {
        var result = self;
        result.max_results = max;
        return result;
    }
};

/// Search results container
pub const SearchResults = struct {
    query: SearchQuery,
    results: std.ArrayList(SearchResult),
    total_matches: usize,
    search_time_ms: u64,
    allocator: std.mem.Allocator,

    pub fn init(allocator: std.mem.Allocator, query: SearchQuery) SearchResults {
        return .{
            .query = query,
            .results = std.ArrayList(SearchResult).init(allocator),
            .total_matches = 0,
            .search_time_ms = 0,
            .allocator = allocator,
        };
    }

    pub fn deinit(self: *SearchResults) void {
        self.results.deinit();
    }

    pub fn add(self: *SearchResults, result: SearchResult) !void {
        try self.results.append(result);
        self.total_matches += 1;
    }

    pub fn isEmpty(self: SearchResults) bool {
        return self.results.items.len == 0;
    }

    pub fn count(self: SearchResults) usize {
        return self.results.items.len;
    }

    pub fn sortByScore(self: *SearchResults) void {
        std.mem.sort(SearchResult, self.results.items, {}, struct {
            fn lessThan(_: void, a: SearchResult, b: SearchResult) bool {
                return a.score > b.score;
            }
        }.lessThan);
    }

    pub fn sortByName(self: *SearchResults) void {
        std.mem.sort(SearchResult, self.results.items, {}, struct {
            fn lessThan(_: void, a: SearchResult, b: SearchResult) bool {
                return std.mem.lessThan(u8, a.name, b.name);
            }
        }.lessThan);
    }

    pub fn filterByType(self: *SearchResults, t: ResultType) !SearchResults {
        var filtered = SearchResults.init(self.allocator, self.query);
        for (self.results.items) |r| {
            if (r.result_type == t) {
                try filtered.add(r);
            }
        }
        return filtered;
    }
};

/// Text matching utilities
pub const TextMatcher = struct {
    case_sensitive: bool = false,

    pub fn init(case_sensitive: bool) TextMatcher {
        return .{ .case_sensitive = case_sensitive };
    }

    pub fn contains(self: TextMatcher, haystack: []const u8, needle: []const u8) bool {
        if (self.case_sensitive) {
            return std.mem.indexOf(u8, haystack, needle) != null;
        }
        // Case insensitive search
        return self.containsIgnoreCase(haystack, needle);
    }

    fn containsIgnoreCase(self: TextMatcher, haystack: []const u8, needle: []const u8) bool {
        _ = self;
        if (needle.len > haystack.len) return false;
        const end = haystack.len - needle.len + 1;
        for (0..end) |i| {
            if (std.ascii.eqlIgnoreCase(haystack[i..][0..needle.len], needle)) {
                return true;
            }
        }
        return false;
    }

    pub fn startsWith(self: TextMatcher, haystack: []const u8, needle: []const u8) bool {
        if (needle.len > haystack.len) return false;
        if (self.case_sensitive) {
            return std.mem.startsWith(u8, haystack, needle);
        }
        return std.ascii.eqlIgnoreCase(haystack[0..needle.len], needle);
    }

    pub fn score(self: TextMatcher, name: []const u8, query: []const u8) f32 {
        _ = self;
        // Simple scoring: exact match > prefix > contains
        if (std.ascii.eqlIgnoreCase(name, query)) {
            return 1.0;
        }
        if (name.len >= query.len and std.ascii.eqlIgnoreCase(name[0..query.len], query)) {
            return 0.8;
        }
        return 0.5;
    }
};

/// Documentation search engine
pub const SearchEngine = struct {
    index: SearchIndex,
    matcher: TextMatcher,
    allocator: std.mem.Allocator,

    pub fn init(allocator: std.mem.Allocator) SearchEngine {
        return .{
            .index = SearchIndex.init(allocator),
            .matcher = TextMatcher.init(false),
            .allocator = allocator,
        };
    }

    pub fn deinit(self: *SearchEngine) void {
        self.index.deinit();
    }

    pub fn search(self: *SearchEngine, query: SearchQuery) !SearchResults {
        var results = SearchResults.init(self.allocator, query);

        // Search in index
        var iter = self.index.entries.iterator();
        while (iter.next()) |entry| {
            if (self.matcher.contains(entry.key_ptr.*, query.text)) {
                const result = SearchResult.init(entry.key_ptr.*, entry.value_ptr.*)
                    .withScore(self.matcher.score(entry.key_ptr.*, query.text));
                try results.add(result);
            }
        }

        results.sortByScore();
        return results;
    }

    pub fn addToIndex(self: *SearchEngine, name: []const u8, result_type: ResultType) !void {
        try self.index.add(name, result_type);
    }

    pub fn indexSize(self: SearchEngine) usize {
        return self.index.count();
    }
};

/// Search index
pub const SearchIndex = struct {
    entries: std.StringHashMap(ResultType),
    allocator: std.mem.Allocator,

    pub fn init(allocator: std.mem.Allocator) SearchIndex {
        return .{
            .entries = std.StringHashMap(ResultType).init(allocator),
            .allocator = allocator,
        };
    }

    pub fn deinit(self: *SearchIndex) void {
        self.entries.deinit();
    }

    pub fn add(self: *SearchIndex, name: []const u8, result_type: ResultType) !void {
        try self.entries.put(name, result_type);
    }

    pub fn remove(self: *SearchIndex, name: []const u8) bool {
        return self.entries.remove(name);
    }

    pub fn contains(self: SearchIndex, name: []const u8) bool {
        return self.entries.contains(name);
    }

    pub fn count(self: SearchIndex) usize {
        return self.entries.count();
    }

    pub fn clear(self: *SearchIndex) void {
        self.entries.clearRetainingCapacity();
    }
};

/// Search result highlighter
pub const Highlighter = struct {
    open_tag: []const u8 = "<b>",
    close_tag: []const u8 = "</b>",

    pub fn highlight(self: Highlighter, allocator: std.mem.Allocator, text: []const u8, query: []const u8) ![]const u8 {
        var result = std.ArrayList(u8).init(allocator);
        var i: usize = 0;

        while (i < text.len) {
            if (i + query.len <= text.len and std.ascii.eqlIgnoreCase(text[i..][0..query.len], query)) {
                try result.appendSlice(self.open_tag);
                try result.appendSlice(text[i..][0..query.len]);
                try result.appendSlice(self.close_tag);
                i += query.len;
            } else {
                try result.append(text[i]);
                i += 1;
            }
        }

        return result.toOwnedSlice();
    }
};

// Tests
test "result_type_display_name" {
    try testing.expectEqualStrings("module", ResultType.module.displayName());
    try testing.expectEqualStrings("class", ResultType.class_type.displayName());
    try testing.expectEqualStrings("function", ResultType.function.displayName());
}

test "result_type_weight" {
    try testing.expect(ResultType.module.weight() > ResultType.function.weight());
    try testing.expect(ResultType.function.weight() > ResultType.attribute.weight());
}

test "search_result_init" {
    const result = SearchResult.init("print", .function);
    try testing.expectEqualStrings("print", result.name);
    try testing.expectEqual(ResultType.function, result.result_type);
}

test "search_result_with_score" {
    const result = SearchResult.init("len", .function).withScore(0.9);
    try testing.expectEqual(@as(f32, 0.9), result.score);
}

test "search_result_with_module" {
    const result = SearchResult.init("path", .module).withModule("os");
    try testing.expectEqualStrings("os", result.module.?);
}

test "search_query_init" {
    const query = SearchQuery.init("test");
    try testing.expectEqualStrings("test", query.text);
    try testing.expect(!query.case_sensitive);
}

test "search_query_case_sensitive" {
    const query = SearchQuery.init("Test").caseSensitive();
    try testing.expect(query.case_sensitive);
}

test "search_query_filter_type" {
    const query = SearchQuery.init("test").filterType(.function);
    try testing.expectEqual(ResultType.function, query.type_filter.?);
}

test "search_query_limit" {
    const query = SearchQuery.init("test").limit(10);
    try testing.expectEqual(@as(u32, 10), query.max_results);
}

test "search_results_init" {
    const query = SearchQuery.init("test");
    var results = SearchResults.init(testing.allocator, query);
    defer results.deinit();
    try testing.expect(results.isEmpty());
}

test "search_results_add" {
    const query = SearchQuery.init("test");
    var results = SearchResults.init(testing.allocator, query);
    defer results.deinit();
    try results.add(SearchResult.init("test_func", .function));
    try testing.expectEqual(@as(usize, 1), results.count());
}

test "text_matcher_contains" {
    const matcher = TextMatcher.init(false);
    try testing.expect(matcher.contains("Hello World", "world"));
    try testing.expect(matcher.contains("Hello World", "Hello"));
    try testing.expect(!matcher.contains("Hello", "World"));
}

test "text_matcher_case_sensitive" {
    const matcher = TextMatcher.init(true);
    try testing.expect(matcher.contains("Hello World", "World"));
    try testing.expect(!matcher.contains("Hello World", "world"));
}

test "text_matcher_starts_with" {
    const matcher = TextMatcher.init(false);
    try testing.expect(matcher.startsWith("Hello World", "hello"));
    try testing.expect(!matcher.startsWith("Hello World", "world"));
}

test "text_matcher_score" {
    const matcher = TextMatcher.init(false);
    const exact = matcher.score("print", "print");
    const prefix = matcher.score("print", "pri");
    try testing.expect(exact > prefix);
}

test "search_engine_init" {
    var engine = SearchEngine.init(testing.allocator);
    defer engine.deinit();
    try testing.expectEqual(@as(usize, 0), engine.indexSize());
}

test "search_engine_add_to_index" {
    var engine = SearchEngine.init(testing.allocator);
    defer engine.deinit();
    try engine.addToIndex("print", .function);
    try testing.expectEqual(@as(usize, 1), engine.indexSize());
}

test "search_index_init" {
    var index = SearchIndex.init(testing.allocator);
    defer index.deinit();
    try testing.expectEqual(@as(usize, 0), index.count());
}

test "search_index_add_contains" {
    var index = SearchIndex.init(testing.allocator);
    defer index.deinit();
    try index.add("os", .module);
    try testing.expect(index.contains("os"));
    try testing.expect(!index.contains("sys"));
}

test "search_index_remove" {
    var index = SearchIndex.init(testing.allocator);
    defer index.deinit();
    try index.add("test", .function);
    try testing.expect(index.remove("test"));
    try testing.expect(!index.contains("test"));
}

test "highlighter_highlight" {
    const hl = Highlighter{};
    const result = try hl.highlight(testing.allocator, "Hello World", "World");
    defer testing.allocator.free(result);
    try testing.expectEqualStrings("Hello <b>World</b>", result);
}

test "highlighter_highlight_case_insensitive" {
    const hl = Highlighter{};
    const result = try hl.highlight(testing.allocator, "Hello WORLD", "world");
    defer testing.allocator.free(result);
    try testing.expectEqualStrings("Hello <b>WORLD</b>", result);
}
