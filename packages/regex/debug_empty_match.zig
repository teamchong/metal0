const std = @import("std");
const parser = @import("src/pyregex/parser.zig");
const nfa_mod = @import("src/pyregex/nfa.zig");
const pikevm = @import("src/pyregex/pikevm.zig");

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

    std.debug.print("NFA start state: {d}\n", .{nfa.start});
    std.debug.print("State {d} transitions:\n", .{nfa.start});
    for (nfa.states[nfa.start].transitions) |trans| {
        switch (trans) {
            .split => |s| {
                std.debug.print("  split -> [", .{});
                for (s.targets, 0..) |t, i| {
                    if (i > 0) std.debug.print(", ", .{});
                    if (t == nfa_mod.MATCH_STATE) {
                        std.debug.print("MATCH({d})", .{t});
                    } else {
                        std.debug.print("{d}", .{t});
                    }
                }
                std.debug.print("]\n", .{});
            },
            else => {},
        }
    }

    // Test matching empty string
    var vm = pikevm.PikeVM.init(allocator, &nfa);
    
    std.debug.print("\nMatching ''...\n", .{});
    const result = try vm.find("");
    
    if (result) |match| {
        var mut_match = match;
        defer mut_match.deinit(allocator);
        std.debug.print("Match: ({d}, {d})\n", .{match.span.start, match.span.end});
    } else {
        std.debug.print("No match\n", .{});
    }
}
