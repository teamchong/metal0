/// Heterogeneous list analysis - detect variables needing PyValue type
/// Analyzes list aliases that get heterogeneous items, variables with mixed types
const std = @import("std");
const ast = @import("analysis.ast");
const hashmap_helper = @import("utils.hashmap_helper");
const types = @import("types.zig");

/// Analyze a function body for heterogeneous list patterns
/// Returns lists of variables that need special handling
pub fn analyzeHeterogeneousLists(
    allocator: std.mem.Allocator,
    body: []const ast.Node,
) struct { heterogeneous_vars: [][]const u8, list_aliases: []types.ListAlias } {
    var heterogeneous_vars = std.ArrayList([]const u8){};
    var list_aliases_list = std.ArrayList(types.ListAlias){};
    var list_vars = hashmap_helper.StringHashMap(types.TypeHint).init(allocator);
    defer list_vars.deinit();

    // Two-pass analysis:
    // Pass 1: Find all list variables and aliases
    // Pass 2: Check augmented assignments for type mismatches
    for (body) |stmt| {
        analyzeStmtForLists(stmt, &list_vars, &list_aliases_list, allocator);
    }

    // Pass 2: Check for heterogeneous augmented assignments
    for (body) |stmt| {
        checkHeterogeneousAugAssign(stmt, &list_vars, &heterogeneous_vars, allocator);
    }

    return .{
        .heterogeneous_vars = heterogeneous_vars.toOwnedSlice(allocator) catch &.{},
        .list_aliases = list_aliases_list.toOwnedSlice(allocator) catch &.{},
    };
}

fn analyzeStmtForLists(
    stmt: ast.Node,
    list_vars: *hashmap_helper.StringHashMap(types.TypeHint),
    list_aliases: *std.ArrayList(types.ListAlias),
    allocator: std.mem.Allocator,
) void {
    switch (stmt) {
        .assign => |assign| {
            // Check if this is a list assignment
            for (assign.targets) |target| {
                if (target == .name) {
                    const var_name = target.name.id;
                    // Check RHS type
                    const rhs_type = inferSimpleType(assign.value.*);
                    if (rhs_type == .list) {
                        list_vars.put(allocator.dupe(u8, var_name) catch var_name, .list) catch {};
                    } else if (assign.value.* == .name) {
                        // Potential alias: T = A
                        const rhs_name = assign.value.name.id;
                        if (list_vars.contains(rhs_name)) {
                            list_aliases.append(allocator, .{
                                .alias_name = allocator.dupe(u8, var_name) catch var_name,
                                .original_name = allocator.dupe(u8, rhs_name) catch rhs_name,
                            }) catch {};
                            list_vars.put(allocator.dupe(u8, var_name) catch var_name, .list) catch {};
                        }
                    }
                }
            }
        },
        .for_stmt => |for_stmt| {
            for (for_stmt.body) |s| analyzeStmtForLists(s, list_vars, list_aliases, allocator);
            if (for_stmt.orelse_body) |else_body| {
                for (else_body) |s| analyzeStmtForLists(s, list_vars, list_aliases, allocator);
            }
        },
        .while_stmt => |while_stmt| {
            for (while_stmt.body) |s| analyzeStmtForLists(s, list_vars, list_aliases, allocator);
            if (while_stmt.orelse_body) |else_body| {
                for (else_body) |s| analyzeStmtForLists(s, list_vars, list_aliases, allocator);
            }
        },
        .if_stmt => |if_stmt| {
            for (if_stmt.body) |s| analyzeStmtForLists(s, list_vars, list_aliases, allocator);
            for (if_stmt.else_body) |s| analyzeStmtForLists(s, list_vars, list_aliases, allocator);
        },
        .try_stmt => |try_stmt| {
            for (try_stmt.body) |s| analyzeStmtForLists(s, list_vars, list_aliases, allocator);
            for (try_stmt.handlers) |handler| {
                for (handler.body) |s| analyzeStmtForLists(s, list_vars, list_aliases, allocator);
            }
            for (try_stmt.else_body) |s| analyzeStmtForLists(s, list_vars, list_aliases, allocator);
            for (try_stmt.finalbody) |s| analyzeStmtForLists(s, list_vars, list_aliases, allocator);
        },
        .with_stmt => |with_stmt| {
            for (with_stmt.body) |s| analyzeStmtForLists(s, list_vars, list_aliases, allocator);
        },
        .match_stmt => |match_stmt| {
            for (match_stmt.cases) |case| {
                for (case.body) |s| analyzeStmtForLists(s, list_vars, list_aliases, allocator);
            }
        },
        else => {},
    }
}

fn checkHeterogeneousAugAssign(
    stmt: ast.Node,
    list_vars: *hashmap_helper.StringHashMap(types.TypeHint),
    heterogeneous_vars: *std.ArrayList([]const u8),
    allocator: std.mem.Allocator,
) void {
    switch (stmt) {
        .aug_assign => |aug| {
            if (aug.op == .Add and aug.target.* == .name) {
                const var_name = aug.target.name.id;
                if (list_vars.contains(var_name)) {
                    // Check if RHS produces different type
                    const rhs_type = inferSimpleType(aug.value.*);
                    // List + tuple/product = heterogeneous
                    if (rhs_type == .tuple or rhs_type == .list) {
                        // Check if it's a comprehension producing tuples
                        if (aug.value.* == .listcomp) {
                            const comp = aug.value.listcomp;
                            const elem_type = inferSimpleType(comp.elt.*);
                            if (elem_type == .tuple) {
                                // This list will have heterogeneous elements
                                heterogeneous_vars.append(allocator, allocator.dupe(u8, var_name) catch var_name) catch {};
                            }
                        } else if (aug.value.* == .call) {
                            // Check if it's a product() call
                            if (aug.value.call.func.* == .name) {
                                const fn_name = aug.value.call.func.name.id;
                                if (std.mem.eql(u8, fn_name, "product")) {
                                    heterogeneous_vars.append(allocator, allocator.dupe(u8, var_name) catch var_name) catch {};
                                }
                            }
                        }
                    }
                }
            }
        },
        .for_stmt => |for_stmt| {
            for (for_stmt.body) |s| checkHeterogeneousAugAssign(s, list_vars, heterogeneous_vars, allocator);
            if (for_stmt.orelse_body) |else_body| {
                for (else_body) |s| checkHeterogeneousAugAssign(s, list_vars, heterogeneous_vars, allocator);
            }
        },
        .while_stmt => |while_stmt| {
            for (while_stmt.body) |s| checkHeterogeneousAugAssign(s, list_vars, heterogeneous_vars, allocator);
            if (while_stmt.orelse_body) |else_body| {
                for (else_body) |s| checkHeterogeneousAugAssign(s, list_vars, heterogeneous_vars, allocator);
            }
        },
        .if_stmt => |if_stmt| {
            for (if_stmt.body) |s| checkHeterogeneousAugAssign(s, list_vars, heterogeneous_vars, allocator);
            for (if_stmt.else_body) |s| checkHeterogeneousAugAssign(s, list_vars, heterogeneous_vars, allocator);
        },
        .try_stmt => |try_stmt| {
            for (try_stmt.body) |s| checkHeterogeneousAugAssign(s, list_vars, heterogeneous_vars, allocator);
            for (try_stmt.handlers) |handler| {
                for (handler.body) |s| checkHeterogeneousAugAssign(s, list_vars, heterogeneous_vars, allocator);
            }
            for (try_stmt.else_body) |s| checkHeterogeneousAugAssign(s, list_vars, heterogeneous_vars, allocator);
            for (try_stmt.finalbody) |s| checkHeterogeneousAugAssign(s, list_vars, heterogeneous_vars, allocator);
        },
        .with_stmt => |with_stmt| {
            for (with_stmt.body) |s| checkHeterogeneousAugAssign(s, list_vars, heterogeneous_vars, allocator);
        },
        .match_stmt => |match_stmt| {
            for (match_stmt.cases) |case| {
                for (case.body) |s| checkHeterogeneousAugAssign(s, list_vars, heterogeneous_vars, allocator);
            }
        },
        else => {},
    }
}

fn inferSimpleType(expr: ast.Node) types.TypeHint {
    return switch (expr) {
        .list => .list,
        .tuple => .tuple,
        .listcomp => .list,
        .dict, .dictcomp => .dict,
        .constant => |c| switch (c.value) {
            .int => .int,
            .float => .float,
            .bool => .bool,
            .string, .bytes => .string,
            .none => .none,
            else => .any,
        },
        .call => .any, // Could be anything
        else => .any,
    };
}
