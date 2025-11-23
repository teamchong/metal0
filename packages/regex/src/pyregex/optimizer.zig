/// Automatic regex optimization analyzer
/// Analyzes AST to detect optimization opportunities
const std = @import("std");
const ast_mod = @import("ast.zig");
const Expr = ast_mod.Expr;
const AST = ast_mod.AST;

/// Optimization strategy to use
pub const Strategy = enum {
    /// Use lazy DFA (default fallback)
    lazy_dfa,
    /// Use SIMD digit scanner for [0-9]+
    simd_digits,
    /// Use SIMD lowercase scanner for [a-z]+
    simd_lowercase,
    /// Use word boundary fast path for \b[a-z]{n,m}\b
    word_boundary,
    /// Use prefix scanning with DFA
    prefix_scan,
};

/// Detected optimization info
pub const OptimizationInfo = struct {
    strategy: Strategy,
    /// Literal prefix to scan for (if any)
    prefix_literal: ?[]const u8 = null,
    /// Window size before prefix
    window_before: usize = 5,
    /// Window size after prefix
    window_after: usize = 5,

    allocator: std.mem.Allocator,

    pub fn deinit(self: *OptimizationInfo) void {
        if (self.prefix_literal) |lit| {
            self.allocator.free(lit);
        }
    }
};

/// Analyze AST and determine best optimization strategy
pub fn analyze(allocator: std.mem.Allocator, ast: *const AST) !OptimizationInfo {
    var info = OptimizationInfo{
        .strategy = .lazy_dfa,
        .allocator = allocator,
    };

    // Try to detect optimization patterns
    if (try detectDigitsPlus(ast.root)) {
        info.strategy = .simd_digits;
        return info;
    }

    if (try detectWordBoundaryPattern(ast.root)) {
        info.strategy = .word_boundary;
        return info;
    }

    // Try to detect literal prefix for prefix scanning
    if (try detectLiteralPrefix(allocator, ast.root)) |prefix_info| {
        info.strategy = .prefix_scan;
        info.prefix_literal = prefix_info.literal;
        info.window_before = prefix_info.window_before;
        info.window_after = prefix_info.window_after;
        return info;
    }

    // Fallback: lazy DFA
    return info;
}

/// Detect [0-9]+ pattern (one or more digits)
fn detectDigitsPlus(expr: Expr) !bool {
    switch (expr) {
        .plus => |sub| {
            switch (sub.*) {
                .digit => return true,
                .class => |cc| {
                    // Check if it's exactly [0-9]
                    if (!cc.negated and cc.ranges.len == 1) {
                        const r = cc.ranges[0];
                        if (r.start == '0' and r.end == '9') {
                            return true;
                        }
                    }
                },
                else => {},
            }
        },
        .concat => |c| {
            // Check each term in sequence
            for (c.exprs) |e| {
                if (try detectDigitsPlus(e)) return true;
            }
        },
        else => {},
    }
    return false;
}

/// Detect \b[a-z]{n,m}\b pattern (word with boundaries)
fn detectWordBoundaryPattern(expr: Expr) !bool {
    // Look for: concat of [word_boundary, lowercase+, word_boundary]
    switch (expr) {
        .concat => |c| {
            if (c.exprs.len < 2) return false;

            // Check for word boundary at start
            const has_start_boundary = switch (c.exprs[0]) {
                .word_boundary => true,
                else => false,
            };

            if (!has_start_boundary) return false;

            // Check for lowercase chars in middle
            var has_lowercase = false;
            for (c.exprs[1..c.exprs.len - 1]) |e| {
                switch (e) {
                    .plus => |sub| {
                        switch (sub.*) {
                            .class => |cc| {
                                if (!cc.negated and cc.ranges.len == 1) {
                                    const r = cc.ranges[0];
                                    if (r.start == 'a' and r.end == 'z') {
                                        has_lowercase = true;
                                    }
                                }
                            },
                            else => {},
                        }
                    },
                    .repeat => |rep| {
                        switch (rep.expr.*) {
                            .class => |cc| {
                                if (!cc.negated and cc.ranges.len == 1) {
                                    const r = cc.ranges[0];
                                    if (r.start == 'a' and r.end == 'z') {
                                        has_lowercase = true;
                                    }
                                }
                            },
                            else => {},
                        }
                    },
                    else => {},
                }
            }

            if (!has_lowercase) return false;

            // Check for word boundary at end
            if (c.exprs.len > 2) {
                const has_end_boundary = switch (c.exprs[c.exprs.len - 1]) {
                    .word_boundary => true,
                    else => false,
                };
                return has_end_boundary;
            }
        },
        else => {},
    }
    return false;
}

const PrefixInfo = struct {
    literal: []const u8,
    window_before: usize,
    window_after: usize,
};

/// Detect literal prefix in pattern
fn detectLiteralPrefix(allocator: std.mem.Allocator, expr: Expr) !?PrefixInfo {
    switch (expr) {
        .concat => |c| {
            // Simple strategy: Find distinctive literal characters (@, ://, -)
            // and calculate window sizes based on surrounding expressions

            // Look for @ (email)
            for (c.exprs, 0..) |e, i| {
                if (e == .char and e.char == '@') {
                    // Found @ - count exprs before/after
                    const before = i;
                    const after = c.exprs.len - i - 1;

                    return PrefixInfo{
                        .literal = try allocator.dupe(u8, &[_]u8{'@'}),
                        .window_before = @min(before, 4),  // Up to 4 terms before
                        .window_after = @min(after, 6),    // Up to 6 terms after
                    };
                }
            }

            // Look for "://" sequence (URL)
            if (c.exprs.len >= 3) {
                for (0..c.exprs.len - 2) |i| {
                    const e1 = c.exprs[i];
                    const e2 = c.exprs[i + 1];
                    const e3 = c.exprs[i + 2];

                    if (e1 == .char and e1.char == ':' and
                        e2 == .char and e2.char == '/' and
                        e3 == .char and e3.char == '/')
                    {
                        // Found "://" - count exprs before/after
                        const before = i;
                        const after = c.exprs.len - i - 3;

                        return PrefixInfo{
                            .literal = try allocator.dupe(u8, "://"),
                            .window_before = @min(before + 1, 6),  // Need "http" or "https" before
                            .window_after = @min(after, 1),        // Rest handled by SIMD
                        };
                    }
                }
            }

            // Look for - (date ISO)
            for (c.exprs, 0..) |e, i| {
                if (e == .char and e.char == '-') {
                    // Found - (typical date format YYYY-MM-DD)
                    _ = i;  // unused but keep for clarity

                    return PrefixInfo{
                        .literal = try allocator.dupe(u8, &[_]u8{'-'}),
                        .window_before = 4,  // YYYY pattern before (we know dates are YYYY-MM-DD)
                        .window_after = 3,   // MM-DD after
                    };
                }
            }
        },
        else => {},
    }

    return null;
}
