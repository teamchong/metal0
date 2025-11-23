const std = @import("std");
const parser = @import("src/pyregex/parser.zig");
const nfa_mod = @import("src/pyregex/nfa.zig");

pub fn main() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    // Parse "a*"
    var p = parser.Parser.init(allocator, "a*");
    var ast = try p.parse();
    defer ast.deinit();

    // Build NFA
    var builder = nfa_mod.Builder.init(allocator);
    const nfa = try builder.build(ast.root);
    defer {
        var mut_nfa = nfa;
        mut_nfa.deinit();
    }

    std.debug.print("NFA for 'a*':\n", .{});
    std.debug.print("  States: {d}\n", .{nfa.states.len});
    std.debug.print("  Start: {d}\n", .{nfa.start});
    std.debug.print("\n", .{});

    for (nfa.states, 0..) |state, i| {
        std.debug.print("State {d}:\n", .{i});
        for (state.transitions) |trans| {
            switch (trans) {
                .byte => |b| std.debug.print("  byte '{c}' -> {d}\n", .{b.value, b.target}),
                .split => |s| {
                    std.debug.print("  split -> [", .{});
                    for (s.targets, 0..) |t, j| {
                        if (j > 0) std.debug.print(", ", .{});
                        if (t == nfa_mod.MATCH_STATE) {
                            std.debug.print("MATCH", .{});
                        } else {
                            std.debug.print("{d}", .{t});
                        }
                    }
                    std.debug.print("]\n", .{});
                },
                .epsilon => |t| std.debug.print("  epsilon -> {d}\n", .{t}),
                .any => |t| std.debug.print("  any -> {d}\n", .{t}),
                .range => |r| std.debug.print("  range [{c}-{c}] -> {d}\n", .{r.start, r.end, r.target}),
                .match => std.debug.print("  MATCH\n", .{}),
            }
        }
    }
}
