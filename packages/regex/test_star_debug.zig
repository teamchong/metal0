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

    std.debug.print("AST root type: {}\n", .{ast.root});

    // Build NFA
    var builder = nfa_mod.Builder.init(allocator);
    const nfa = try builder.build(ast.root);
    defer {
        var mut_nfa = nfa;
        mut_nfa.deinit();
    }

    std.debug.print("NFA states: {d}\n", .{nfa.states.len});
    std.debug.print("NFA start: {d}\n", .{nfa.start});

    // Test matching
    var vm = pikevm.PikeVM.init(allocator, &nfa);
    
    std.debug.print("\nTrying to match 'aaa'...\n", .{});
    const result = try vm.find("aaa");
    
    if (result) |match| {
        var mut_match = match;
        defer mut_match.deinit(allocator);
        std.debug.print("Match found: ({d}, {d})\n", .{match.span.start, match.span.end});
    } else {
        std.debug.print("No match found\n", .{});
    }
}
