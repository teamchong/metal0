/// Analyze variable mutations to determine if lists need ArrayList vs fixed array
const std = @import("std");
const ast = @import("../../ast.zig");
const hashmap_helper = @import("../../utils/hashmap_helper.zig");

pub const MutationMap = hashmap_helper.StringHashMap(MutationInfo);

/// List mutation methods (DCE optimized lookup)
const ListMutationMethods = std.StaticStringMap(MutationType).initComptime(.{
    .{ "append", .list_append },
    .{ "pop", .list_pop },
    .{ "extend", .list_extend },
    .{ "insert", .list_insert },
    .{ "remove", .list_remove },
    .{ "clear", .list_clear },
    .{ "sort", .list_sort },
    .{ "reverse", .list_reverse },
});

pub const MutationType = enum {
    list_append,
    list_pop,
    list_extend,
    list_insert,
    list_remove,
    list_clear,
    list_sort,
    list_reverse,
    dict_setitem,
    reassignment,
};

pub const MutationInfo = struct {
    is_mutated: bool,
    mutation_types: std.ArrayList(MutationType),

    pub fn deinit(self: *MutationInfo) void {
        self.mutation_types.deinit();
    }
};

/// Analyze all mutations in a module and return a map of variable name -> mutation info
pub fn analyzeMutations(module: ast.Node.Module, allocator: std.mem.Allocator) !hashmap_helper.StringHashMap(MutationInfo) {
    var mutations = hashmap_helper.StringHashMap(MutationInfo).init(allocator);

    for (module.body) |stmt| {
        try collectMutations(stmt, &mutations, allocator);
    }

    return mutations;
}

/// Recursively collect mutations from statements
fn collectMutations(
    stmt: ast.Node,
    mutations: *hashmap_helper.StringHashMap(MutationInfo),
    allocator: std.mem.Allocator,
) !void {
    switch (stmt) {
        .expr_stmt => |e| {
            // Check for mutation calls: x.append(y), x.pop(), etc.
            try checkExprForMutation(e.value.*, mutations, allocator);
        },
        .assign => |a| {
            // Check if this is a reassignment (variable already declared)
            for (a.targets) |target| {
                if (target == .name) {
                    _ = target.name.id; // var_name unused currently
                    // Check if RHS has mutations
                    try checkExprForMutation(a.value.*, mutations, allocator);
                }
                // Also check for subscript assignment: list[0] = value
                if (target == .subscript) {
                    if (target.subscript.value.* == .name) {
                        const obj_name = target.subscript.value.name.id;
                        try recordMutation(obj_name, .dict_setitem, mutations, allocator);
                    }
                }
            }
        },
        .aug_assign => |a| {
            // x += 1 is a reassignment
            if (a.target.* == .name) {
                const var_name = a.target.name.id;
                try recordMutation(var_name, .reassignment, mutations, allocator);
            }
        },
        .if_stmt => |i| {
            // Check condition
            try checkExprForMutation(i.condition.*, mutations, allocator);
            // Check body
            for (i.body) |s| {
                try collectMutations(s, mutations, allocator);
            }
            // Check else body
            for (i.else_body) |s| {
                try collectMutations(s, mutations, allocator);
            }
        },
        .while_stmt => |w| {
            // Check condition
            try checkExprForMutation(w.condition.*, mutations, allocator);
            // Check body
            for (w.body) |s| {
                try collectMutations(s, mutations, allocator);
            }
        },
        .for_stmt => |f| {
            // Check iterator
            try checkExprForMutation(f.iter.*, mutations, allocator);
            // Check body
            for (f.body) |s| {
                try collectMutations(s, mutations, allocator);
            }
        },
        .function_def => |func| {
            // Check function body for mutations
            for (func.body) |s| {
                try collectMutations(s, mutations, allocator);
            }
        },
        .return_stmt => |r| {
            if (r.value) |v| {
                try checkExprForMutation(v.*, mutations, allocator);
            }
        },
        .try_stmt => |t| {
            // Check try body
            for (t.body) |s| {
                try collectMutations(s, mutations, allocator);
            }
            // Check handlers
            for (t.handlers) |h| {
                for (h.body) |s| {
                    try collectMutations(s, mutations, allocator);
                }
            }
        },
        else => {},
    }
}

/// Check if an expression contains a mutation
fn checkExprForMutation(
    expr: ast.Node,
    mutations: *hashmap_helper.StringHashMap(MutationInfo),
    allocator: std.mem.Allocator,
) error{OutOfMemory}!void {
    switch (expr) {
        .call => |c| {
            // Check if this is a mutating method call
            if (c.func.* == .attribute) {
                const attr = c.func.attribute;
                if (attr.value.* == .name) {
                    const obj_name = attr.value.name.id;
                    const method_name = attr.attr;

                    // List mutating methods (O(1) lookup via StaticStringMap)
                    if (ListMutationMethods.get(method_name)) |mutation_type| {
                        try recordMutation(obj_name, mutation_type, mutations, allocator);
                    }
                }
            }
            // Recursively check arguments
            for (c.args) |arg| {
                try checkExprForMutation(arg, mutations, allocator);
            }
        },
        .binop => |b| {
            try checkExprForMutation(b.left.*, mutations, allocator);
            try checkExprForMutation(b.right.*, mutations, allocator);
        },
        .unaryop => |u| {
            try checkExprForMutation(u.operand.*, mutations, allocator);
        },
        .compare => |c| {
            try checkExprForMutation(c.left.*, mutations, allocator);
            for (c.comparators) |comp| {
                try checkExprForMutation(comp, mutations, allocator);
            }
        },
        .boolop => |b| {
            for (b.values) |val| {
                try checkExprForMutation(val, mutations, allocator);
            }
        },
        .subscript => |s| {
            try checkExprForMutation(s.value.*, mutations, allocator);
            switch (s.slice) {
                .index => |idx| try checkExprForMutation(idx.*, mutations, allocator),
                .slice => |rng| {
                    if (rng.lower) |l| try checkExprForMutation(l.*, mutations, allocator);
                    if (rng.upper) |u| try checkExprForMutation(u.*, mutations, allocator);
                    if (rng.step) |st| try checkExprForMutation(st.*, mutations, allocator);
                },
            }
        },
        .attribute => |a| {
            try checkExprForMutation(a.value.*, mutations, allocator);
        },
        .list => |l| {
            for (l.elts) |elt| {
                try checkExprForMutation(elt, mutations, allocator);
            }
        },
        .dict => |d| {
            for (d.keys) |key| {
                try checkExprForMutation(key, mutations, allocator);
            }
            for (d.values) |val| {
                try checkExprForMutation(val, mutations, allocator);
            }
        },
        .tuple => |t| {
            for (t.elts) |elt| {
                try checkExprForMutation(elt, mutations, allocator);
            }
        },
        else => {},
    }
}

/// Record a mutation for a variable
fn recordMutation(
    var_name: []const u8,
    mutation_type: MutationType,
    mutations: *hashmap_helper.StringHashMap(MutationInfo),
    allocator: std.mem.Allocator,
) !void {
    var info = mutations.get(var_name) orelse MutationInfo{
        .is_mutated = false,
        .mutation_types = std.ArrayList(MutationType){},
    };

    info.is_mutated = true;
    try info.mutation_types.append(allocator, mutation_type);
    try mutations.put(var_name, info);
}

/// Check if a variable has any list mutations
pub fn hasListMutation(mutations: hashmap_helper.StringHashMap(MutationInfo), var_name: []const u8) bool {
    const info = mutations.get(var_name) orelse return false;
    if (!info.is_mutated) return false;

    for (info.mutation_types.items) |mut_type| {
        switch (mut_type) {
            .list_append,
            .list_pop,
            .list_extend,
            .list_insert,
            .list_remove,
            .list_clear,
            .list_sort,
            .list_reverse,
            => return true,
            else => {},
        }
    }
    return false;
}

/// Check if a variable has any dict mutations
pub fn hasDictMutation(mutations: hashmap_helper.StringHashMap(MutationInfo), var_name: []const u8) bool {
    const info = mutations.get(var_name) orelse return false;
    if (!info.is_mutated) return false;

    for (info.mutation_types.items) |mut_type| {
        if (mut_type == .dict_setitem) return true;
    }
    return false;
}
