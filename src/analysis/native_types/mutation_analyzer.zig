/// Analyze variable mutations to determine if lists need ArrayList vs fixed array
const std = @import("std");
const ast = @import("analysis.ast");
const hashmap_helper = @import("utils.hashmap_helper");

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
    list_concat_aug, // x += [...] - list concatenation augmented assignment
    list_repeat_aug, // x *= n - list repeat augmented assignment
    dict_setitem,
    dict_setitem_int_key, // d[int] = value - subscript assign with int key
    dict_setitem_str_key, // d[str] = value - subscript assign with string key
    reassignment,
    attr_setattr, // setattr(obj, name, value)
    attr_delattr, // delattr(obj, name)
    attr_direct_assign, // obj.name = value
};

pub const MutationInfo = struct {
    is_mutated: bool,
    mutation_types: std.ArrayList(MutationType),
    /// Types of values appended via .append() - for inferring empty list element type
    append_arg_nodes: std.ArrayList(ast.Node),

    pub fn deinit(self: *MutationInfo) void {
        self.mutation_types.deinit();
        self.append_arg_nodes.deinit();
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
                // Also check for subscript assignment: list[0] = value or d[key] = value
                if (target == .subscript) {
                    if (target.subscript.value.* == .name) {
                        const obj_name = target.subscript.value.name.id;
                        // Detect key type for dict subscript assignments
                        const mutation_type: MutationType = switch (target.subscript.slice) {
                            .index => |idx| blk: {
                                // Check key type
                                if (idx.* == .constant) {
                                    switch (idx.constant.value) {
                                        .int => break :blk .dict_setitem_int_key,
                                        .string => break :blk .dict_setitem_str_key,
                                        else => break :blk .dict_setitem,
                                    }
                                } else if (idx.* == .name) {
                                    // Variable - could be int from for-loop
                                    // Check if it's a range iterator var (common pattern)
                                    break :blk .dict_setitem_int_key;
                                }
                                break :blk .dict_setitem;
                            },
                            else => .dict_setitem,
                        };
                        try recordMutation(obj_name, mutation_type, mutations, allocator);
                    }
                }
                // Note: We intentionally do NOT track direct attribute assignment (o.attr = value) here.
                // Direct attribute assignment works fine on const class instances in Zig because
                // fields are part of the struct definition. The issue is specifically with __dict__
                // mutations via setattr/delattr builtin functions, which we track separately.
                // Tracking o.attr = value would cause scoping issues (different variables named 'o'
                // in different methods would interfere with each other).
            }
        },
        .aug_assign => |a| {
            if (a.target.* == .name) {
                const var_name = a.target.name.id;
                // Check for list augmented operations that change list size
                if (a.op == .Add and a.value.* == .list) {
                    // x += [...] - list concatenation
                    try recordMutation(var_name, .list_concat_aug, mutations, allocator);
                } else if (a.op == .Mult) {
                    // x *= n - could be list repeat
                    try recordMutation(var_name, .list_repeat_aug, mutations, allocator);
                } else {
                    // Regular reassignment
                    try recordMutation(var_name, .reassignment, mutations, allocator);
                }
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
            // Check else body
            if (w.orelse_body) |ob| {
                for (ob) |s| {
                    try collectMutations(s, mutations, allocator);
                }
            }
        },
        .for_stmt => |f| {
            // Check iterator
            try checkExprForMutation(f.iter.*, mutations, allocator);
            // Check body
            for (f.body) |s| {
                try collectMutations(s, mutations, allocator);
            }
            // Check else body
            if (f.orelse_body) |ob| {
                for (ob) |s| {
                    try collectMutations(s, mutations, allocator);
                }
            }
        },
        .function_def => |func| {
            // Check function body for mutations
            for (func.body) |s| {
                try collectMutations(s, mutations, allocator);
            }
        },
        .class_def => |class| {
            // Check class body for mutations (methods, etc.)
            for (class.body) |s| {
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
            // Check else body
            for (t.else_body) |s| {
                try collectMutations(s, mutations, allocator);
            }
            // Check finally body
            for (t.finalbody) |s| {
                try collectMutations(s, mutations, allocator);
            }
        },
        .with_stmt => |w| {
            // Check with body for mutations
            for (w.body) |s| {
                try collectMutations(s, mutations, allocator);
            }
        },
        .match_stmt => |m| {
            // Check subject
            try checkExprForMutation(m.subject.*, mutations, allocator);
            // Check case bodies
            for (m.cases) |case| {
                if (case.guard) |guard| {
                    try checkExprForMutation(guard.*, mutations, allocator);
                }
                for (case.body) |s| {
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
            // Check if this is a setattr/delattr call
            if (c.func.* == .name) {
                const func_name = c.func.name.id;
                if (std.mem.eql(u8, func_name, "setattr") and c.args.len >= 1) {
                    // setattr(obj, name, value) - first arg is the object being mutated
                    if (c.args[0] == .name) {
                        try recordMutation(c.args[0].name.id, .attr_setattr, mutations, allocator);
                    }
                } else if (std.mem.eql(u8, func_name, "delattr") and c.args.len >= 1) {
                    // delattr(obj, name) - first arg is the object being mutated
                    if (c.args[0] == .name) {
                        try recordMutation(c.args[0].name.id, .attr_delattr, mutations, allocator);
                    }
                }
            }
            // Check if this is a mutating method call
            if (c.func.* == .attribute) {
                const attr = c.func.attribute;
                if (attr.value.* == .name) {
                    const obj_name = attr.value.name.id;
                    const method_name = attr.attr;

                    // Special handling for append - capture the argument for element type inference
                    if (std.mem.eql(u8, method_name, "append") and c.args.len > 0) {
                        try recordAppendMutation(obj_name, c.args[0], mutations, allocator);
                    }
                    // Other list mutating methods (O(1) lookup via StaticStringMap)
                    else if (ListMutationMethods.get(method_name)) |mutation_type| {
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
        .append_arg_nodes = std.ArrayList(ast.Node){},
    };

    info.is_mutated = true;
    try info.mutation_types.append(allocator, mutation_type);
    try mutations.put(var_name, info);
}

/// Record a mutation with the append argument for element type inference
fn recordAppendMutation(
    var_name: []const u8,
    append_arg: ast.Node,
    mutations: *hashmap_helper.StringHashMap(MutationInfo),
    allocator: std.mem.Allocator,
) !void {
    var info = mutations.get(var_name) orelse MutationInfo{
        .is_mutated = false,
        .mutation_types = std.ArrayList(MutationType){},
        .append_arg_nodes = std.ArrayList(ast.Node){},
    };

    info.is_mutated = true;
    try info.mutation_types.append(allocator, .list_append);
    try info.append_arg_nodes.append(allocator, append_arg);
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
            .list_concat_aug,
            .list_repeat_aug,
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
        switch (mut_type) {
            .dict_setitem, .dict_setitem_int_key, .dict_setitem_str_key => return true,
            else => {},
        }
    }
    return false;
}

/// Check if dict has int key mutations (d[int] = value pattern)
pub fn hasDictIntKeyMutation(mutations: hashmap_helper.StringHashMap(MutationInfo), var_name: []const u8) bool {
    const info = mutations.get(var_name) orelse return false;
    if (!info.is_mutated) return false;

    for (info.mutation_types.items) |mut_type| {
        if (mut_type == .dict_setitem_int_key) return true;
    }
    return false;
}

/// Check if dict has string key mutations (d[str] = value pattern)
pub fn hasDictStrKeyMutation(mutations: hashmap_helper.StringHashMap(MutationInfo), var_name: []const u8) bool {
    const info = mutations.get(var_name) orelse return false;
    if (!info.is_mutated) return false;

    for (info.mutation_types.items) |mut_type| {
        if (mut_type == .dict_setitem_str_key) return true;
    }
    return false;
}

/// Get the AST nodes of values appended to a list variable
/// Used for inferring empty list element types from .append() calls
pub fn getAppendedNodes(mutations: hashmap_helper.StringHashMap(MutationInfo), var_name: []const u8) ?[]const ast.Node {
    const info = mutations.get(var_name) orelse return null;
    if (info.append_arg_nodes.items.len == 0) return null;
    return info.append_arg_nodes.items;
}

/// Check if dict has mixed key types (both int and string keys)
/// This indicates the dict needs PyValue key type for heterogeneous access
pub fn hasMixedDictKeys(mutations: hashmap_helper.StringHashMap(MutationInfo), var_name: []const u8) bool {
    const info = mutations.get(var_name) orelse return false;
    if (!info.is_mutated) return false;

    var has_int_key = false;
    var has_str_key = false;
    for (info.mutation_types.items) |mut_type| {
        if (mut_type == .dict_setitem_int_key) has_int_key = true;
        if (mut_type == .dict_setitem_str_key) has_str_key = true;
    }
    return has_int_key and has_str_key;
}

/// Check if a variable has any attribute mutations (setattr, delattr, or direct assignment)
pub fn hasAttrMutation(mutations: hashmap_helper.StringHashMap(MutationInfo), var_name: []const u8) bool {
    const info = mutations.get(var_name) orelse return false;
    if (!info.is_mutated) return false;

    for (info.mutation_types.items) |mut_type| {
        switch (mut_type) {
            .attr_setattr, .attr_delattr, .attr_direct_assign => return true,
            else => {},
        }
    }
    return false;
}

/// Info about a closure that appends to a captured list
pub const ClosureAppendInfo = struct {
    func_name: []const u8, // Name of the function that appends
    list_var: []const u8, // Name of the list being appended to
    param_names: []const []const u8, // Function parameter names
    append_tuple_indices: []const usize, // Which params are in the appended tuple (in order)
};

/// Map from list variable name -> closures that append to it
pub const ClosureAppendMap = hashmap_helper.StringHashMap(std.ArrayListUnmanaged(ClosureAppendInfo));

/// Analyze closures that append to captured lists
/// Returns map of list_var -> ClosureAppendInfo for closures that append tuples
pub fn analyzeClosureAppends(module: ast.Node.Module, allocator: std.mem.Allocator) !ClosureAppendMap {
    var result = ClosureAppendMap.init(allocator);

    for (module.body) |stmt| {
        try collectClosureAppends(stmt, &result, allocator);
    }

    return result;
}

/// Recursively collect closure append patterns
fn collectClosureAppends(
    stmt: ast.Node,
    result: *ClosureAppendMap,
    allocator: std.mem.Allocator,
) !void {
    switch (stmt) {
        .function_def => |func| {
            // Check if this function appends to any captured variable
            try analyzeClosureBody(func, result, allocator);

            // Also check nested functions
            for (func.body) |s| {
                try collectClosureAppends(s, result, allocator);
            }
        },
        .class_def => |class| {
            for (class.body) |s| {
                try collectClosureAppends(s, result, allocator);
            }
        },
        .if_stmt => |i| {
            for (i.body) |s| try collectClosureAppends(s, result, allocator);
            for (i.else_body) |s| try collectClosureAppends(s, result, allocator);
        },
        .for_stmt => |f| {
            for (f.body) |s| try collectClosureAppends(s, result, allocator);
            if (f.orelse_body) |ob| {
                for (ob) |s| try collectClosureAppends(s, result, allocator);
            }
        },
        .while_stmt => |w| {
            for (w.body) |s| try collectClosureAppends(s, result, allocator);
            if (w.orelse_body) |ob| {
                for (ob) |s| try collectClosureAppends(s, result, allocator);
            }
        },
        .try_stmt => |t| {
            for (t.body) |s| try collectClosureAppends(s, result, allocator);
            for (t.handlers) |h| {
                for (h.body) |s| try collectClosureAppends(s, result, allocator);
            }
            for (t.else_body) |s| try collectClosureAppends(s, result, allocator);
            for (t.finalbody) |s| try collectClosureAppends(s, result, allocator);
        },
        .with_stmt => |w| {
            for (w.body) |s| try collectClosureAppends(s, result, allocator);
        },
        .match_stmt => |m| {
            for (m.cases) |case| {
                for (case.body) |s| try collectClosureAppends(s, result, allocator);
            }
        },
        else => {},
    }
}

/// Analyze a function body for append patterns to captured variables
fn analyzeClosureBody(
    func: ast.Node.FunctionDef,
    result: *ClosureAppendMap,
    allocator: std.mem.Allocator,
) !void {
    // Collect parameter names
    var param_names: std.ArrayListUnmanaged([]const u8) = .{};
    defer param_names.deinit(allocator);

    for (func.args) |arg| {
        try param_names.append(allocator, arg.name);
    }

    // Look for append calls in the function body
    for (func.body) |stmt| {
        try findAppendToCapture(stmt, func.name, param_names.items, result, allocator);
    }
}

/// Find append calls that use function parameters in tuples
fn findAppendToCapture(
    stmt: ast.Node,
    func_name: []const u8,
    param_names: []const []const u8,
    result: *ClosureAppendMap,
    allocator: std.mem.Allocator,
) !void {
    switch (stmt) {
        .expr_stmt => |e| {
            try checkExprForAppendCapture(e.value.*, func_name, param_names, result, allocator);
        },
        .if_stmt => |i| {
            for (i.body) |s| try findAppendToCapture(s, func_name, param_names, result, allocator);
            for (i.else_body) |s| try findAppendToCapture(s, func_name, param_names, result, allocator);
        },
        .for_stmt => |f| {
            for (f.body) |s| try findAppendToCapture(s, func_name, param_names, result, allocator);
            if (f.orelse_body) |ob| {
                for (ob) |s| try findAppendToCapture(s, func_name, param_names, result, allocator);
            }
        },
        .while_stmt => |w| {
            for (w.body) |s| try findAppendToCapture(s, func_name, param_names, result, allocator);
            if (w.orelse_body) |ob| {
                for (ob) |s| try findAppendToCapture(s, func_name, param_names, result, allocator);
            }
        },
        .try_stmt => |t| {
            for (t.body) |s| try findAppendToCapture(s, func_name, param_names, result, allocator);
            for (t.handlers) |h| {
                for (h.body) |s| try findAppendToCapture(s, func_name, param_names, result, allocator);
            }
            for (t.else_body) |s| try findAppendToCapture(s, func_name, param_names, result, allocator);
            for (t.finalbody) |s| try findAppendToCapture(s, func_name, param_names, result, allocator);
        },
        .with_stmt => |w| {
            for (w.body) |s| try findAppendToCapture(s, func_name, param_names, result, allocator);
        },
        .match_stmt => |m| {
            for (m.cases) |case| {
                for (case.body) |s| try findAppendToCapture(s, func_name, param_names, result, allocator);
            }
        },
        else => {},
    }
}

/// Check if expression is an append call with a tuple of parameters
fn checkExprForAppendCapture(
    expr: ast.Node,
    func_name: []const u8,
    param_names: []const []const u8,
    result: *ClosureAppendMap,
    allocator: std.mem.Allocator,
) !void {
    if (expr != .call) return;

    const call = expr.call;
    if (call.func.* != .attribute) return;

    const attr = call.func.attribute;
    if (!std.mem.eql(u8, attr.attr, "append")) return;
    if (attr.value.* != .name) return;

    const list_var = attr.value.name.id;

    // Check if the argument is a tuple
    if (call.args.len == 0) return;
    const arg = call.args[0];

    if (arg != .tuple) return;

    // Check if tuple elements are function parameters
    var tuple_param_indices: std.ArrayListUnmanaged(usize) = .{};
    defer tuple_param_indices.deinit(allocator);

    for (arg.tuple.elts) |elt| {
        if (elt == .name) {
            // Check if this name is a function parameter
            for (param_names, 0..) |pname, idx| {
                if (std.mem.eql(u8, elt.name.id, pname)) {
                    try tuple_param_indices.append(allocator, idx);
                    break;
                }
            }
        }
    }

    // If we found parameters in the tuple, record this pattern
    if (tuple_param_indices.items.len > 0) {
        const info = ClosureAppendInfo{
            .func_name = func_name,
            .list_var = list_var,
            .param_names = try allocator.dupe([]const u8, param_names),
            .append_tuple_indices = try allocator.dupe(usize, tuple_param_indices.items),
        };

        const gop = try result.getOrPut(list_var);
        if (!gop.found_existing) {
            gop.value_ptr.* = .{};
        }
        try gop.value_ptr.append(allocator, info);
    }
}

/// Get closures that append to a given list variable
pub fn getClosureAppendsForList(map: ClosureAppendMap, list_var: []const u8) ?[]const ClosureAppendInfo {
    const list = map.get(list_var) orelse return null;
    if (list.items.len == 0) return null;
    return list.items;
}

/// Map from function name -> list of call site argument types
pub const CallSiteMap = hashmap_helper.StringHashMap(std.ArrayListUnmanaged([]const ast.Node));

/// Analyze call sites to functions in a module
pub fn analyzeCallSites(module: ast.Node.Module, allocator: std.mem.Allocator) !CallSiteMap {
    var result = CallSiteMap.init(allocator);

    for (module.body) |stmt| {
        try collectCallSites(stmt, &result, allocator);
    }

    return result;
}

/// Recursively collect call sites
fn collectCallSites(
    node: ast.Node,
    result: *CallSiteMap,
    allocator: std.mem.Allocator,
) !void {
    switch (node) {
        .call => |c| {
            // Direct function call: func(args)
            if (c.func.* == .name) {
                const func_name = c.func.name.id;
                const args_copy = try allocator.dupe(ast.Node, c.args);
                const gop = try result.getOrPut(func_name);
                if (!gop.found_existing) {
                    gop.value_ptr.* = .{};
                }
                try gop.value_ptr.append(allocator, args_copy);
            }
            // Method call on closure: closure.call(args)
            else if (c.func.* == .attribute) {
                const attr = c.func.attribute;
                if (std.mem.eql(u8, attr.attr, "call") and attr.value.* == .name) {
                    const closure_name = attr.value.name.id;
                    const args_copy = try allocator.dupe(ast.Node, c.args);
                    const gop = try result.getOrPut(closure_name);
                    if (!gop.found_existing) {
                        gop.value_ptr.* = .{};
                    }
                    try gop.value_ptr.append(allocator, args_copy);
                }
            }
            // Recurse into arguments
            for (c.args) |arg| {
                try collectCallSites(arg, result, allocator);
            }
        },
        .expr_stmt => |e| try collectCallSites(e.value.*, result, allocator),
        .assign => |a| try collectCallSites(a.value.*, result, allocator),
        .function_def => |func| {
            for (func.body) |s| try collectCallSites(s, result, allocator);
        },
        .class_def => |class| {
            for (class.body) |s| try collectCallSites(s, result, allocator);
        },
        .if_stmt => |i| {
            try collectCallSites(i.condition.*, result, allocator);
            for (i.body) |s| try collectCallSites(s, result, allocator);
            for (i.else_body) |s| try collectCallSites(s, result, allocator);
        },
        .for_stmt => |f| {
            try collectCallSites(f.iter.*, result, allocator);
            for (f.body) |s| try collectCallSites(s, result, allocator);
            if (f.orelse_body) |ob| {
                for (ob) |s| try collectCallSites(s, result, allocator);
            }
        },
        .while_stmt => |w| {
            try collectCallSites(w.condition.*, result, allocator);
            for (w.body) |s| try collectCallSites(s, result, allocator);
            if (w.orelse_body) |ob| {
                for (ob) |s| try collectCallSites(s, result, allocator);
            }
        },
        .return_stmt => |r| {
            if (r.value) |v| try collectCallSites(v.*, result, allocator);
        },
        .dictcomp => |dc| {
            try collectCallSites(dc.key.*, result, allocator);
            try collectCallSites(dc.value.*, result, allocator);
        },
        .listcomp => |lc| {
            try collectCallSites(lc.elt.*, result, allocator);
        },
        .binop => |b| {
            try collectCallSites(b.left.*, result, allocator);
            try collectCallSites(b.right.*, result, allocator);
        },
        .boolop => |b| {
            for (b.values) |v| try collectCallSites(v, result, allocator);
        },
        .compare => |c| {
            try collectCallSites(c.left.*, result, allocator);
            for (c.comparators) |comp| try collectCallSites(comp, result, allocator);
        },
        .unaryop => |u| try collectCallSites(u.operand.*, result, allocator),
        .subscript => |s| {
            try collectCallSites(s.value.*, result, allocator);
            switch (s.slice) {
                .index => |idx| try collectCallSites(idx.*, result, allocator),
                .slice => |rng| {
                    if (rng.lower) |l| try collectCallSites(l.*, result, allocator);
                    if (rng.upper) |u| try collectCallSites(u.*, result, allocator);
                    if (rng.step) |st| try collectCallSites(st.*, result, allocator);
                },
            }
        },
        .attribute => |a| try collectCallSites(a.value.*, result, allocator),
        .list => |l| {
            for (l.elts) |e| try collectCallSites(e, result, allocator);
        },
        .tuple => |t| {
            for (t.elts) |e| try collectCallSites(e, result, allocator);
        },
        .dict => |d| {
            for (d.keys) |k| try collectCallSites(k, result, allocator);
            for (d.values) |v| try collectCallSites(v, result, allocator);
        },
        .try_stmt => |t| {
            for (t.body) |s| try collectCallSites(s, result, allocator);
            for (t.handlers) |h| {
                for (h.body) |s| try collectCallSites(s, result, allocator);
            }
            for (t.else_body) |s| try collectCallSites(s, result, allocator);
            for (t.finalbody) |s| try collectCallSites(s, result, allocator);
        },
        .with_stmt => |w| {
            for (w.body) |s| try collectCallSites(s, result, allocator);
        },
        .match_stmt => |m| {
            try collectCallSites(m.subject.*, result, allocator);
            for (m.cases) |case| {
                if (case.guard) |guard| try collectCallSites(guard.*, result, allocator);
                for (case.body) |s| try collectCallSites(s, result, allocator);
            }
        },
        else => {},
    }
}

/// Get call sites for a function
pub fn getCallSitesForFunc(map: CallSiteMap, func_name: []const u8) ?[]const []const ast.Node {
    const list = map.get(func_name) orelse return null;
    if (list.items.len == 0) return null;
    return list.items;
}
