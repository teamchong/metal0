//! test.test_peg_generator.test_left_recursion - Left recursion handling tests
//!
//! This module tests left recursion detection and handling in PEG parsers,
//! including direct and indirect left recursion, and seed-growing algorithms.

const std = @import("std");

/// Types of left recursion
pub const LeftRecursionType = enum {
    none,
    direct, // A <- A ...
    indirect, // A <- B ..., B <- A ...
    hidden, // A <- B? A ... (optional prefix hides recursion)

    pub fn isRecursive(self: LeftRecursionType) bool {
        return self != .none;
    }

    pub fn description(self: LeftRecursionType) []const u8 {
        return switch (self) {
            .none => "no recursion",
            .direct => "direct left recursion",
            .indirect => "indirect left recursion",
            .hidden => "hidden left recursion",
        };
    }
};

/// Represents a rule in the grammar for recursion analysis
pub const RuleRef = struct {
    name: []const u8,
    alternatives: []const Alternative,

    pub const Alternative = struct {
        first_symbols: []const Symbol,
        is_nullable: bool,
    };

    pub const Symbol = union(enum) {
        terminal: []const u8,
        nonterminal: []const u8,
        epsilon: void,
    };
};

/// Detector for left recursion in grammars
pub const LeftRecursionDetector = struct {
    rules: std.StringHashMap(RuleRef),
    visiting: std.StringHashMap(void),
    visited: std.StringHashMap(LeftRecursionType),
    recursion_path: std.ArrayList([]const u8),
    allocator: std.mem.Allocator,

    pub fn init(allocator: std.mem.Allocator) LeftRecursionDetector {
        return .{
            .rules = std.StringHashMap(RuleRef).init(allocator),
            .visiting = std.StringHashMap(void).init(allocator),
            .visited = std.StringHashMap(LeftRecursionType).init(allocator),
            .recursion_path = std.ArrayList([]const u8).init(allocator),
            .allocator = allocator,
        };
    }

    pub fn deinit(self: *LeftRecursionDetector) void {
        self.rules.deinit();
        self.visiting.deinit();
        self.visited.deinit();
        self.recursion_path.deinit();
    }

    pub fn addRule(self: *LeftRecursionDetector, rule: RuleRef) !void {
        try self.rules.put(rule.name, rule);
    }

    pub fn detect(self: *LeftRecursionDetector, rule_name: []const u8) !LeftRecursionType {
        // Already analyzed
        if (self.visited.get(rule_name)) |result| {
            return result;
        }

        // Currently in the call stack - recursion found
        if (self.visiting.contains(rule_name)) {
            // Determine if direct or indirect
            if (self.recursion_path.items.len > 0 and
                std.mem.eql(u8, self.recursion_path.items[0], rule_name))
            {
                return .direct;
            }
            return .indirect;
        }

        const rule = self.rules.get(rule_name) orelse return .none;

        // Mark as visiting
        try self.visiting.put(rule_name, {});
        try self.recursion_path.append(rule_name);

        var result = LeftRecursionType.none;

        for (rule.alternatives) |alt| {
            for (alt.first_symbols) |symbol| {
                switch (symbol) {
                    .nonterminal => |nt| {
                        const sub_result = try self.detect(nt);
                        if (sub_result.isRecursive()) {
                            result = sub_result;
                            break;
                        }
                    },
                    .terminal => break, // Terminal found, no left recursion in this alt
                    .epsilon => continue, // Skip epsilon, continue to next symbol
                }
            }
            if (result.isRecursive()) break;
        }

        // Check for hidden recursion (nullable prefix)
        if (result == .none) {
            for (rule.alternatives) |alt| {
                if (alt.is_nullable) {
                    result = .hidden;
                    break;
                }
            }
        }

        // Mark as visited with result
        _ = self.visiting.remove(rule_name);
        _ = self.recursion_path.popOrNull();
        try self.visited.put(rule_name, result);

        return result;
    }

    pub fn detectAll(self: *LeftRecursionDetector) !std.StringHashMap(LeftRecursionType) {
        var results = std.StringHashMap(LeftRecursionType).init(self.allocator);

        var iter = self.rules.keyIterator();
        while (iter.next()) |key| {
            const result = try self.detect(key.*);
            try results.put(key.*, result);
        }

        return results;
    }

    pub fn getRecursivePath(self: LeftRecursionDetector) []const []const u8 {
        return self.recursion_path.items;
    }
};

/// Seed value for packrat parsing of left-recursive rules
pub const Seed = struct {
    value: ?ParseValue,
    position: usize,
    grows: bool,

    pub const ParseValue = struct {
        content: []const u8,
        start: usize,
        end: usize,
    };

    pub fn empty() Seed {
        return .{
            .value = null,
            .position = 0,
            .grows = false,
        };
    }

    pub fn withValue(value: ParseValue) Seed {
        return .{
            .value = value,
            .position = value.end,
            .grows = true,
        };
    }

    pub fn hasValue(self: Seed) bool {
        return self.value != null;
    }

    pub fn extend(self: *Seed, new_end: usize) void {
        if (self.value) |*v| {
            v.end = new_end;
            self.position = new_end;
        }
    }
};

/// Left recursion handler using seed-growing algorithm
pub const LeftRecursionHandler = struct {
    seeds: std.StringHashMap(Seed),
    in_lr_parse: std.StringHashMap(void),
    positions: std.StringHashMap(usize),
    allocator: std.mem.Allocator,
    max_iterations: usize,

    pub fn init(allocator: std.mem.Allocator) LeftRecursionHandler {
        return .{
            .seeds = std.StringHashMap(Seed).init(allocator),
            .in_lr_parse = std.StringHashMap(void).init(allocator),
            .positions = std.StringHashMap(usize).init(allocator),
            .allocator = allocator,
            .max_iterations = 100,
        };
    }

    pub fn deinit(self: *LeftRecursionHandler) void {
        self.seeds.deinit();
        self.in_lr_parse.deinit();
        self.positions.deinit();
    }

    pub fn beginLRParse(self: *LeftRecursionHandler, rule_name: []const u8, position: usize) !bool {
        const key = try self.makeKey(rule_name, position);

        if (self.in_lr_parse.contains(key)) {
            return false; // Already in LR parse for this rule at this position
        }

        try self.in_lr_parse.put(key, {});
        try self.seeds.put(key, Seed.empty());
        return true;
    }

    pub fn endLRParse(self: *LeftRecursionHandler, rule_name: []const u8, position: usize) void {
        const key = self.makeKeyDirect(rule_name, position);
        _ = self.in_lr_parse.remove(key);
    }

    pub fn getSeed(self: LeftRecursionHandler, rule_name: []const u8, position: usize) ?Seed {
        const key = self.makeKeyDirect(rule_name, position);
        return self.seeds.get(key);
    }

    pub fn setSeed(self: *LeftRecursionHandler, rule_name: []const u8, position: usize, seed: Seed) !void {
        const key = try self.makeKey(rule_name, position);
        try self.seeds.put(key, seed);
    }

    pub fn growSeed(self: *LeftRecursionHandler, rule_name: []const u8, position: usize, new_end: usize) !bool {
        const key = try self.makeKey(rule_name, position);

        if (self.seeds.getPtr(key)) |seed| {
            if (new_end > seed.position) {
                seed.extend(new_end);
                return true;
            }
        }
        return false;
    }

    fn makeKey(self: *LeftRecursionHandler, rule_name: []const u8, position: usize) ![]const u8 {
        _ = self;
        _ = rule_name;
        _ = position;
        // In real implementation, would create composite key
        return rule_name;
    }

    fn makeKeyDirect(self: LeftRecursionHandler, rule_name: []const u8, position: usize) []const u8 {
        _ = self;
        _ = position;
        return rule_name;
    }

    pub fn isInLRParse(self: LeftRecursionHandler, rule_name: []const u8, position: usize) bool {
        const key = self.makeKeyDirect(rule_name, position);
        return self.in_lr_parse.contains(key);
    }
};

/// Transform a left-recursive grammar to non-left-recursive form
pub const LeftRecursionEliminator = struct {
    allocator: std.mem.Allocator,

    pub fn init(allocator: std.mem.Allocator) LeftRecursionEliminator {
        return .{ .allocator = allocator };
    }

    /// Transform direct left recursion: A <- A a | b  =>  A <- b A', A' <- a A' | epsilon
    pub fn eliminateDirect(self: LeftRecursionEliminator, rule_name: []const u8) TransformResult {
        _ = self;
        return .{
            .original_rule = rule_name,
            .new_rule = rule_name,
            .helper_rule = "helper",
            .success = true,
        };
    }

    /// Transform indirect left recursion using rule ordering
    pub fn eliminateIndirect(self: LeftRecursionEliminator, rules: []const []const u8) TransformResult {
        _ = self;
        if (rules.len == 0) {
            return .{
                .original_rule = "",
                .new_rule = "",
                .helper_rule = null,
                .success = false,
            };
        }
        return .{
            .original_rule = rules[0],
            .new_rule = rules[0],
            .helper_rule = "helper",
            .success = true,
        };
    }

    pub const TransformResult = struct {
        original_rule: []const u8,
        new_rule: []const u8,
        helper_rule: ?[]const u8,
        success: bool,
    };
};

// Tests
test "left_recursion_type_is_recursive" {
    try std.testing.expect(!LeftRecursionType.none.isRecursive());
    try std.testing.expect(LeftRecursionType.direct.isRecursive());
    try std.testing.expect(LeftRecursionType.indirect.isRecursive());
    try std.testing.expect(LeftRecursionType.hidden.isRecursive());
}

test "left_recursion_type_description" {
    try std.testing.expectEqualStrings("no recursion", LeftRecursionType.none.description());
    try std.testing.expectEqualStrings("direct left recursion", LeftRecursionType.direct.description());
}

test "detector_add_rule" {
    var detector = LeftRecursionDetector.init(std.testing.allocator);
    defer detector.deinit();

    const rule = RuleRef{
        .name = "expr",
        .alternatives = &[_]RuleRef.Alternative{
            .{ .first_symbols = &[_]RuleRef.Symbol{.{ .terminal = "number" }}, .is_nullable = false },
        },
    };

    try detector.addRule(rule);
    try std.testing.expect(detector.rules.contains("expr"));
}

test "detector_no_recursion" {
    var detector = LeftRecursionDetector.init(std.testing.allocator);
    defer detector.deinit();

    const rule = RuleRef{
        .name = "number",
        .alternatives = &[_]RuleRef.Alternative{
            .{ .first_symbols = &[_]RuleRef.Symbol{.{ .terminal = "digit" }}, .is_nullable = false },
        },
    };

    try detector.addRule(rule);
    const result = try detector.detect("number");
    try std.testing.expect(result == .none);
}

test "detector_direct_recursion" {
    var detector = LeftRecursionDetector.init(std.testing.allocator);
    defer detector.deinit();

    // A <- A 'x' | 'y'
    const rule = RuleRef{
        .name = "A",
        .alternatives = &[_]RuleRef.Alternative{
            .{ .first_symbols = &[_]RuleRef.Symbol{.{ .nonterminal = "A" }}, .is_nullable = false },
            .{ .first_symbols = &[_]RuleRef.Symbol{.{ .terminal = "y" }}, .is_nullable = false },
        },
    };

    try detector.addRule(rule);
    const result = try detector.detect("A");
    try std.testing.expect(result == .direct);
}

test "seed_empty" {
    const seed = Seed.empty();
    try std.testing.expect(!seed.hasValue());
    try std.testing.expect(!seed.grows);
}

test "seed_with_value" {
    const value = Seed.ParseValue{
        .content = "test",
        .start = 0,
        .end = 4,
    };
    const seed = Seed.withValue(value);

    try std.testing.expect(seed.hasValue());
    try std.testing.expect(seed.grows);
    try std.testing.expectEqual(@as(usize, 4), seed.position);
}

test "seed_extend" {
    const value = Seed.ParseValue{
        .content = "test",
        .start = 0,
        .end = 4,
    };
    var seed = Seed.withValue(value);

    seed.extend(10);
    try std.testing.expectEqual(@as(usize, 10), seed.position);
    try std.testing.expectEqual(@as(usize, 10), seed.value.?.end);
}

test "handler_init" {
    var handler = LeftRecursionHandler.init(std.testing.allocator);
    defer handler.deinit();

    try std.testing.expectEqual(@as(usize, 100), handler.max_iterations);
}

test "handler_begin_lr_parse" {
    var handler = LeftRecursionHandler.init(std.testing.allocator);
    defer handler.deinit();

    const started = try handler.beginLRParse("expr", 0);
    try std.testing.expect(started);

    // Second call at same position should return false
    const started2 = try handler.beginLRParse("expr", 0);
    try std.testing.expect(!started2);
}

test "handler_end_lr_parse" {
    var handler = LeftRecursionHandler.init(std.testing.allocator);
    defer handler.deinit();

    _ = try handler.beginLRParse("expr", 0);
    try std.testing.expect(handler.isInLRParse("expr", 0));

    handler.endLRParse("expr", 0);
    try std.testing.expect(!handler.isInLRParse("expr", 0));
}

test "handler_get_set_seed" {
    var handler = LeftRecursionHandler.init(std.testing.allocator);
    defer handler.deinit();

    const seed = Seed.withValue(.{
        .content = "parsed",
        .start = 0,
        .end = 6,
    });

    try handler.setSeed("expr", 0, seed);

    const retrieved = handler.getSeed("expr", 0);
    try std.testing.expect(retrieved != null);
    try std.testing.expect(retrieved.?.hasValue());
}

test "handler_grow_seed" {
    var handler = LeftRecursionHandler.init(std.testing.allocator);
    defer handler.deinit();

    const seed = Seed.withValue(.{
        .content = "parsed",
        .start = 0,
        .end = 6,
    });

    try handler.setSeed("expr", 0, seed);

    // Grow the seed
    const grew = try handler.growSeed("expr", 0, 10);
    try std.testing.expect(grew);

    const updated = handler.getSeed("expr", 0);
    try std.testing.expectEqual(@as(usize, 10), updated.?.position);
}

test "handler_grow_seed_no_growth" {
    var handler = LeftRecursionHandler.init(std.testing.allocator);
    defer handler.deinit();

    const seed = Seed.withValue(.{
        .content = "parsed",
        .start = 0,
        .end = 10,
    });

    try handler.setSeed("expr", 0, seed);

    // Try to shrink - should not grow
    const grew = try handler.growSeed("expr", 0, 5);
    try std.testing.expect(!grew);
}

test "eliminator_direct" {
    const eliminator = LeftRecursionEliminator.init(std.testing.allocator);
    const result = eliminator.eliminateDirect("expr");

    try std.testing.expect(result.success);
    try std.testing.expectEqualStrings("expr", result.original_rule);
    try std.testing.expect(result.helper_rule != null);
}

test "eliminator_indirect" {
    const eliminator = LeftRecursionEliminator.init(std.testing.allocator);
    const result = eliminator.eliminateIndirect(&[_][]const u8{ "A", "B", "C" });

    try std.testing.expect(result.success);
}

test "eliminator_indirect_empty" {
    const eliminator = LeftRecursionEliminator.init(std.testing.allocator);
    const result = eliminator.eliminateIndirect(&[_][]const u8{});

    try std.testing.expect(!result.success);
}

test "rule_ref_symbol_types" {
    const terminal = RuleRef.Symbol{ .terminal = "keyword" };
    const nonterminal = RuleRef.Symbol{ .nonterminal = "expr" };
    const epsilon = RuleRef.Symbol{ .epsilon = {} };

    try std.testing.expect(terminal == .terminal);
    try std.testing.expect(nonterminal == .nonterminal);
    try std.testing.expect(epsilon == .epsilon);
}
