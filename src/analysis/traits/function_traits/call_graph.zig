/// Call graph building and function trait analysis infrastructure
/// Main module for building CallGraph from Python AST
const std = @import("std");
const ast = @import("analysis.ast");
const hashmap_helper = @import("utils.hashmap_helper");
const types = @import("types.zig");
const error_types = @import("error_types.zig");
const heterogeneous = @import("heterogeneous_analysis.zig");

pub const FunctionTraits = types.FunctionTraits;
pub const FunctionRef = types.FunctionRef;
pub const AsyncComplexity = types.AsyncComplexity;
pub const ListAlias = types.ListAlias;

/// Call graph built from module analysis
pub const CallGraph = struct {
    /// Map from function name to its traits
    functions: hashmap_helper.StringHashMap(FunctionTraits),
    /// Map from class name to its methods
    classes: hashmap_helper.StringHashMap([]const []const u8),
    /// Global variables that are modified
    modified_globals: hashmap_helper.StringHashMap(void),
    /// Allocator for internal storage
    allocator: std.mem.Allocator,

    pub fn init(allocator: std.mem.Allocator) CallGraph {
        return .{
            .functions = hashmap_helper.StringHashMap(FunctionTraits).init(allocator),
            .classes = hashmap_helper.StringHashMap([]const []const u8).init(allocator),
            .modified_globals = hashmap_helper.StringHashMap(void).init(allocator),
            .allocator = allocator,
        };
    }

    pub fn deinit(self: *CallGraph) void {
        var it = self.functions.iterator();
        while (it.next()) |entry| {
            var traits_val = entry.value_ptr.*;
            traits_val.deinit(self.allocator);
        }
        self.functions.deinit();

        var class_it = self.classes.iterator();
        while (class_it.next()) |entry| {
            self.allocator.free(entry.value_ptr.*);
        }
        self.classes.deinit();

        self.modified_globals.deinit();
    }

    /// Get traits for a function
    pub fn getTraits(self: *const CallGraph, name: []const u8) ?FunctionTraits {
        return self.functions.get(name);
    }

    /// Check if a function is reachable from entry points
    pub fn isReachable(self: *const CallGraph, name: []const u8) bool {
        if (self.functions.get(name)) |traits_val| {
            return traits_val.is_called;
        }
        return false;
    }

    /// Get all functions called by a function (transitive)
    pub fn getTransitiveCalls(self: *const CallGraph, name: []const u8, allocator: std.mem.Allocator) ![]FunctionRef {
        var visited = hashmap_helper.StringHashMap(void).init(allocator);
        defer visited.deinit();

        var result = std.ArrayList(FunctionRef){};
        errdefer result.deinit(allocator);

        try self.collectTransitiveCalls(name, &visited, &result, allocator);

        return result.toOwnedSlice(allocator);
    }

    fn collectTransitiveCalls(
        self: *const CallGraph,
        name: []const u8,
        visited: *hashmap_helper.StringHashMap(void),
        result: *std.ArrayList(FunctionRef),
        allocator: std.mem.Allocator,
    ) !void {
        if (visited.contains(name)) return;
        try visited.put(name, {});

        if (self.functions.get(name)) |traits_val| {
            for (traits_val.calls) |call| {
                try result.append(allocator, call);
                try self.collectTransitiveCalls(call.name, visited, result, allocator);
            }
        }
    }
};

/// Analyzer context for building traits
pub const AnalyzerContext = struct {
    allocator: std.mem.Allocator,
    current_func: ?[]const u8 = null,
    current_class: ?[]const u8 = null,
    current_module: []const u8 = "",
    scope_vars: hashmap_helper.StringHashMap(void),
    param_names: []const []const u8 = &.{},
    param_mutations: std.ArrayList(bool),
    calls: std.ArrayList(FunctionRef),
    captured: std.ArrayList([]const u8),

    // Trait flags
    has_await: bool = false,
    has_io: bool = false,
    can_error: bool = false,
    needs_allocator: bool = false,
    is_pure: bool = true,
    is_tail_recursive: bool = false,
    is_generator: bool = false,
    modifies_globals: bool = false,
    reads_globals: bool = false,
    op_count: usize = 0,
    await_count: usize = 0,
    has_loops: bool = false,

    // Escape analysis
    escaping_params: std.ArrayList(bool),
    escaping_locals: std.ArrayList([]const u8),
    local_vars: hashmap_helper.StringHashMap(void),
    return_aliases_param: ?usize = null,

    // Precise error types
    error_set: error_types.ErrorSet = .{},

    // Parameter usage analysis
    params_used: std.ArrayList(bool),

    // Block-scoped variable analysis
    block_scope_depth: usize = 0,
    vars_at_depth: hashmap_helper.StringHashMap(usize),
    escaping_block_vars: std.ArrayList([]const u8),
    block_scoped_vars: std.ArrayList([]const u8),

    pub fn init(allocator: std.mem.Allocator) AnalyzerContext {
        return .{
            .allocator = allocator,
            .scope_vars = hashmap_helper.StringHashMap(void).init(allocator),
            .param_mutations = std.ArrayList(bool){},
            .calls = std.ArrayList(FunctionRef){},
            .captured = std.ArrayList([]const u8){},
            .escaping_params = std.ArrayList(bool){},
            .escaping_locals = std.ArrayList([]const u8){},
            .local_vars = hashmap_helper.StringHashMap(void).init(allocator),
            .params_used = std.ArrayList(bool){},
            .vars_at_depth = hashmap_helper.StringHashMap(usize).init(allocator),
            .escaping_block_vars = std.ArrayList([]const u8){},
            .block_scoped_vars = std.ArrayList([]const u8){},
        };
    }

    pub fn deinit(self: *AnalyzerContext) void {
        self.scope_vars.deinit();
        self.param_mutations.deinit(self.allocator);
        self.calls.deinit(self.allocator);
        self.captured.deinit(self.allocator);
        self.escaping_params.deinit(self.allocator);
        self.escaping_locals.deinit(self.allocator);
        self.local_vars.deinit();
        self.params_used.deinit(self.allocator);
        self.vars_at_depth.deinit();
        self.escaping_block_vars.deinit(self.allocator);
        self.block_scoped_vars.deinit(self.allocator);
    }

    pub fn reset(self: *AnalyzerContext) void {
        self.scope_vars.clearRetainingCapacity();
        self.param_mutations.clearRetainingCapacity();
        self.calls.clearRetainingCapacity();
        self.captured.clearRetainingCapacity();
        self.escaping_params.clearRetainingCapacity();
        self.escaping_locals.clearRetainingCapacity();
        self.local_vars.clearRetainingCapacity();
        self.params_used.clearRetainingCapacity();
        self.vars_at_depth.clearRetainingCapacity();
        self.escaping_block_vars.clearRetainingCapacity();
        self.block_scoped_vars.clearRetainingCapacity();
        self.has_await = false;
        self.has_io = false;
        self.can_error = false;
        self.needs_allocator = false;
        self.is_pure = true;
        self.is_tail_recursive = false;
        self.is_generator = false;
        self.modifies_globals = false;
        self.reads_globals = false;
        self.op_count = 0;
        self.await_count = 0;
        self.has_loops = false;
        self.return_aliases_param = null;
        self.error_set = .{};
        self.block_scope_depth = 0;
    }

    /// Mark a parameter as used
    pub fn markParamUsed(self: *AnalyzerContext, param_name: []const u8) !void {
        for (self.param_names, 0..) |name, i| {
            if (std.mem.eql(u8, name, param_name)) {
                while (self.params_used.items.len <= i) {
                    try self.params_used.append(self.allocator, false);
                }
                self.params_used.items[i] = true;
                return;
            }
        }
    }

    /// Declare a variable at current block depth
    pub fn declareVarAtDepth(self: *AnalyzerContext, var_name: []const u8) !void {
        try self.vars_at_depth.put(var_name, self.block_scope_depth);
    }

    /// Check if a variable use escapes its declaring block
    pub fn checkVarEscape(self: *AnalyzerContext, var_name: []const u8) !void {
        if (self.vars_at_depth.get(var_name)) |decl_depth| {
            if (decl_depth > 0 and self.block_scope_depth < decl_depth) {
                for (self.escaping_block_vars.items) |v| {
                    if (std.mem.eql(u8, v, var_name)) return;
                }
                try self.escaping_block_vars.append(self.allocator, var_name);
            }
        }
    }

    pub fn enterBlockScope(self: *AnalyzerContext) void {
        self.block_scope_depth += 1;
    }

    pub fn exitBlockScope(self: *AnalyzerContext) void {
        if (self.block_scope_depth > 0) {
            self.block_scope_depth -= 1;
        }
    }
};

/// I/O function names that trigger state machine async
const IoFunctions = std.StaticStringMap(void).initComptime(.{
    .{ "input", {} }, .{ "open", {} }, .{ "read", {} }, .{ "write", {} }, .{ "close", {} },
    .{ "get", {} }, .{ "post", {} }, .{ "put", {} }, .{ "delete", {} }, .{ "patch", {} },
    .{ "request", {} }, .{ "fetch", {} }, .{ "connect", {} }, .{ "send", {} }, .{ "recv", {} },
    .{ "sendall", {} }, .{ "recvfrom", {} }, .{ "sendto", {} }, .{ "sleep", {} },
    .{ "call", {} }, .{ "check_call", {} }, .{ "check_output", {} }, .{ "communicate", {} }, .{ "Popen", {} },
});

const IoMethods = std.StaticStringMap(void).initComptime(.{
    .{ "flush", {} }, .{ "readline", {} }, .{ "readlines", {} },
    .{ "writelines", {} }, .{ "json", {} }, .{ "text", {} },
});

const ListMutationMethods = std.StaticStringMap(void).initComptime(.{
    .{ "append", {} }, .{ "extend", {} }, .{ "insert", {} }, .{ "pop", {} },
    .{ "remove", {} }, .{ "clear", {} }, .{ "sort", {} }, .{ "reverse", {} },
});

const ErrorFunctions = std.StaticStringMap(error_types.ErrorSet).initComptime(.{
    .{ "raise", error_types.ErrorSet{ .RuntimeError = true } },
    .{ "assert", error_types.ErrorSet{ .AssertionError = true } },
    .{ "open", error_types.ErrorSet{ .FileNotFoundError = true, .PermissionError = true, .IOError = true } },
    .{ "int", error_types.ErrorSet{ .ValueError = true } },
    .{ "float", error_types.ErrorSet{ .ValueError = true } },
    .{ "eval", error_types.ErrorSet{ .RuntimeError = true } },
    .{ "exec", error_types.ErrorSet{ .RuntimeError = true } },
    .{ "next", error_types.ErrorSet{ .StopIteration = true } },
    .{ "getattr", error_types.ErrorSet{ .AttributeError = true } },
    .{ "__floor__", error_types.ErrorSet{ .ValueError = true, .OverflowError = true } },
    .{ "__ceil__", error_types.ErrorSet{ .ValueError = true, .OverflowError = true } },
    .{ "__trunc__", error_types.ErrorSet{ .ValueError = true, .OverflowError = true } },
    .{ "__round__", error_types.ErrorSet{ .ValueError = true, .OverflowError = true } },
});

const AllocatorFunctions = std.StaticStringMap(void).initComptime(.{
    .{ "list", {} }, .{ "dict", {} }, .{ "set", {} }, .{ "str", {} }, .{ "bytes", {} },
    .{ "bytearray", {} }, .{ "range", {} }, .{ "map", {} }, .{ "filter", {} },
    .{ "sorted", {} }, .{ "reversed", {} }, .{ "enumerate", {} }, .{ "zip", {} },
});

/// Build call graph from a module
pub fn buildCallGraph(module: ast.Node.Module, allocator: std.mem.Allocator) !CallGraph {
    std.debug.print("buildCallGraph: Initializing graph...\n", .{});
    var graph = CallGraph.init(allocator);
    errdefer graph.deinit();

    var ctx = AnalyzerContext.init(allocator);
    defer ctx.deinit();

    std.debug.print("buildCallGraph: First pass (collect definitions)...\n", .{});
    // First pass: collect all function definitions
    for (module.body) |stmt| {
        try collectDefinitions(stmt, &graph, &ctx);
    }

    std.debug.print("buildCallGraph: Second pass (analyze traits)...\n", .{});
    // Second pass: analyze each function's traits
    for (module.body) |stmt| {
        try analyzeStatement(stmt, &graph, &ctx);
    }

    std.debug.print("buildCallGraph: Third pass (mark reachable)...\n", .{});
    // Third pass: mark reachable functions from entry points
    try markReachable(&graph, allocator);

    std.debug.print("buildCallGraph: Complete.\n", .{});
    return graph;
}

fn collectDefinitions(stmt: ast.Node, graph: *CallGraph, ctx: *AnalyzerContext) !void {
    switch (stmt) {
        .function_def => |func| {
            const ref = FunctionRef{
                .module = ctx.current_module,
                .name = func.name,
                .class_name = ctx.current_class,
            };
            try graph.functions.put(func.name, FunctionTraits{ .ref = ref });
        },
        .class_def => |class| {
            var methods = std.ArrayList([]const u8){};
            errdefer methods.deinit(ctx.allocator);

            const old_class = ctx.current_class;
            ctx.current_class = class.name;
            defer ctx.current_class = old_class;

            for (class.body) |body_stmt| {
                if (body_stmt == .function_def) {
                    try methods.append(ctx.allocator, body_stmt.function_def.name);
                    try collectDefinitions(body_stmt, graph, ctx);
                }
            }

            try graph.classes.put(class.name, try methods.toOwnedSlice(ctx.allocator));
        },
        else => {},
    }
}

fn analyzeStatement(stmt: ast.Node, graph: *CallGraph, ctx: *AnalyzerContext) !void {
    switch (stmt) {
        .function_def => |func| {
            ctx.reset();
            ctx.current_func = func.name;

            var param_names = std.ArrayList([]const u8){};
            defer param_names.deinit(ctx.allocator);

            for (func.args) |arg| {
                try param_names.append(ctx.allocator, arg.name);
                try ctx.scope_vars.put(arg.name, {});
                try ctx.param_mutations.append(ctx.allocator, false);
                try ctx.escaping_params.append(ctx.allocator, false);
            }
            ctx.param_names = param_names.items;

            for (func.body) |body_stmt| {
                try analyzeStmtForTraits(body_stmt, ctx);
            }

            if (func.body.len > 0) {
                ctx.is_tail_recursive = isTailRecursive(func.body[func.body.len - 1], func.name);
            }

            var traits_val = graph.functions.get(func.name) orelse FunctionTraits{
                .ref = .{ .module = ctx.current_module, .name = func.name, .class_name = ctx.current_class },
            };

            traits_val.has_await = ctx.has_await;
            traits_val.has_io = ctx.has_io;
            traits_val.can_error = ctx.can_error;
            traits_val.needs_allocator = ctx.needs_allocator;
            traits_val.is_pure = ctx.is_pure and !ctx.has_io and !ctx.modifies_globals;
            traits_val.is_tail_recursive = ctx.is_tail_recursive;
            traits_val.is_generator = ctx.is_generator;
            traits_val.modifies_globals = ctx.modifies_globals;
            traits_val.reads_globals = ctx.reads_globals;
            traits_val.async_complexity = computeAsyncComplexity(ctx);

            if (ctx.param_mutations.items.len > 0) {
                traits_val.mutates_params = try ctx.allocator.dupe(bool, ctx.param_mutations.items);
            }
            if (ctx.calls.items.len > 0) {
                traits_val.calls = try ctx.allocator.dupe(FunctionRef, ctx.calls.items);
            }
            if (ctx.captured.items.len > 0) {
                traits_val.captured_vars = try ctx.allocator.dupe([]const u8, ctx.captured.items);
            }
            if (ctx.escaping_params.items.len > 0) {
                traits_val.escaping_params = try ctx.allocator.dupe(bool, ctx.escaping_params.items);
            }
            if (ctx.escaping_locals.items.len > 0) {
                traits_val.escaping_locals = try ctx.allocator.dupe([]const u8, ctx.escaping_locals.items);
            }
            if (ctx.local_vars.count() > 0) {
                var all_locals_list = std.ArrayList([]const u8){};
                var local_iter = ctx.local_vars.iterator();
                while (local_iter.next()) |entry| {
                    try all_locals_list.append(ctx.allocator, entry.key_ptr.*);
                }
                traits_val.all_locals = try all_locals_list.toOwnedSlice(ctx.allocator);
            }
            traits_val.return_aliases_param = ctx.return_aliases_param;
            traits_val.error_types = ctx.error_set;

            if (ctx.params_used.items.len > 0) {
                traits_val.params_used_in_body = try ctx.allocator.dupe(bool, ctx.params_used.items);
            }
            if (ctx.escaping_block_vars.items.len > 0) {
                traits_val.escaping_block_vars = try ctx.allocator.dupe([]const u8, ctx.escaping_block_vars.items);
            }
            if (ctx.block_scoped_vars.items.len > 0) {
                traits_val.block_scoped_vars = try ctx.allocator.dupe([]const u8, ctx.block_scoped_vars.items);
            }

            const het_analysis = heterogeneous.analyzeHeterogeneousLists(ctx.allocator, func.body);
            traits_val.heterogeneous_vars = het_analysis.heterogeneous_vars;
            traits_val.list_aliases = het_analysis.list_aliases;

            try graph.functions.put(func.name, traits_val);
        },
        .class_def => |class| {
            const old_class = ctx.current_class;
            ctx.current_class = class.name;
            defer ctx.current_class = old_class;

            for (class.body) |body_stmt| {
                try analyzeStatement(body_stmt, graph, ctx);
            }
        },
        .assign => |assign| {
            if (ctx.current_func == null) {
                for (assign.targets) |target| {
                    if (target == .name) {
                        try graph.modified_globals.put(target.name.id, {});
                    }
                }
            }
        },
        else => {},
    }
}

fn analyzeStmtForTraits(stmt: ast.Node, ctx: *AnalyzerContext) !void {
    switch (stmt) {
        .expr_stmt => |expr| {
            try analyzeExprForTraits(expr.value.*, ctx);
        },
        .assign => |assign| {
            for (assign.targets) |target| {
                try checkMutation(target, ctx);
                if (target == .name) {
                    try ctx.local_vars.put(target.name.id, {});
                    try ctx.declareVarAtDepth(target.name.id);
                }
                if (target == .name and !ctx.scope_vars.contains(target.name.id)) {
                    try markEscapingExpr(assign.value.*, ctx);
                }
            }
            try analyzeExprForTraits(assign.value.*, ctx);
            ctx.op_count += 1;
        },
        .aug_assign => |aug| {
            try checkMutation(aug.target.*, ctx);
            try analyzeExprForTraits(aug.value.*, ctx);
            ctx.op_count += 1;
        },
        .return_stmt => |ret| {
            if (ret.value) |val| {
                try analyzeExprForTraits(val.*, ctx);
                try markEscapingExpr(val.*, ctx);
                if (val.* == .name) {
                    for (ctx.param_names, 0..) |param, i| {
                        if (std.mem.eql(u8, param, val.name.id)) {
                            ctx.return_aliases_param = i;
                            break;
                        }
                    }
                }
            }
            ctx.op_count += 1;
        },
        .raise_stmt => {
            ctx.can_error = true;
            ctx.error_set.RuntimeError = true;
            ctx.is_pure = false;
        },
        .if_stmt => |if_stmt| {
            try analyzeExprForTraits(if_stmt.condition.*, ctx);
            ctx.enterBlockScope();
            for (if_stmt.body) |s| try analyzeStmtForTraits(s, ctx);
            ctx.exitBlockScope();
            ctx.enterBlockScope();
            for (if_stmt.else_body) |s| try analyzeStmtForTraits(s, ctx);
            ctx.exitBlockScope();
            ctx.op_count += 2;
        },
        .while_stmt => |while_stmt| {
            ctx.has_loops = true;
            try analyzeExprForTraits(while_stmt.condition.*, ctx);
            ctx.enterBlockScope();
            for (while_stmt.body) |s| try analyzeStmtForTraits(s, ctx);
            ctx.exitBlockScope();
            if (while_stmt.orelse_body) |orelse_body| {
                ctx.enterBlockScope();
                for (orelse_body) |s| try analyzeStmtForTraits(s, ctx);
                ctx.exitBlockScope();
            }
            ctx.op_count += 5;
        },
        .for_stmt => |for_stmt| {
            ctx.has_loops = true;
            try analyzeExprForTraits(for_stmt.iter.*, ctx);
            ctx.enterBlockScope();
            if (for_stmt.target.* == .name) {
                try ctx.declareVarAtDepth(for_stmt.target.name.id);
            }
            for (for_stmt.body) |s| try analyzeStmtForTraits(s, ctx);
            ctx.exitBlockScope();
            if (for_stmt.orelse_body) |orelse_body| {
                ctx.enterBlockScope();
                for (orelse_body) |s| try analyzeStmtForTraits(s, ctx);
                ctx.exitBlockScope();
            }
            ctx.op_count += 5;
        },
        .match_stmt => |match_stmt| {
            try analyzeExprForTraits(match_stmt.subject.*, ctx);
            for (match_stmt.cases) |case| {
                if (case.guard) |guard| {
                    try analyzeExprForTraits(guard.*, ctx);
                }
                ctx.enterBlockScope();
                for (case.body) |s| try analyzeStmtForTraits(s, ctx);
                ctx.exitBlockScope();
            }
            ctx.op_count += 3;
        },
        .try_stmt => |try_stmt| {
            ctx.can_error = true;
            ctx.enterBlockScope();
            for (try_stmt.body) |s| try analyzeStmtForTraits(s, ctx);
            ctx.exitBlockScope();
            for (try_stmt.handlers) |h| {
                ctx.enterBlockScope();
                for (h.body) |s| try analyzeStmtForTraits(s, ctx);
                ctx.exitBlockScope();
            }
            ctx.enterBlockScope();
            for (try_stmt.else_body) |s| try analyzeStmtForTraits(s, ctx);
            ctx.exitBlockScope();
            ctx.enterBlockScope();
            for (try_stmt.finalbody) |s| try analyzeStmtForTraits(s, ctx);
            ctx.exitBlockScope();
        },
        .with_stmt => |with_stmt| {
            try analyzeExprForTraits(with_stmt.context_expr.*, ctx);
            ctx.enterBlockScope();
            for (with_stmt.body) |s| try analyzeStmtForTraits(s, ctx);
            ctx.exitBlockScope();
        },
        .yield_stmt, .yield_from_stmt => {
            ctx.is_generator = true;
        },
        .assert_stmt => |assert_stmt| {
            try analyzeExprForTraits(assert_stmt.condition.*, ctx);
            if (assert_stmt.msg) |msg| {
                try analyzeExprForTraits(msg.*, ctx);
            }
            ctx.op_count += 1;
        },
        else => {
            ctx.op_count += 1;
        },
    }
}

fn analyzeExprForTraits(expr: ast.Node, ctx: *AnalyzerContext) error{OutOfMemory}!void {
    switch (expr) {
        .await_expr => |await_expr| {
            ctx.has_await = true;
            ctx.await_count += 1;
            try analyzeExprForTraits(await_expr.value.*, ctx);
        },
        .yield_stmt, .yield_from_stmt => {
            ctx.is_generator = true;
        },
        .call => |call| {
            if (call.func.* == .name) {
                const func_name = call.func.name.id;
                if (IoFunctions.has(func_name)) {
                    ctx.has_io = true;
                    ctx.is_pure = false;
                }
                if (ErrorFunctions.get(func_name)) |errors| {
                    ctx.can_error = true;
                    ctx.error_set = ctx.error_set.merge(errors);
                }
                if (AllocatorFunctions.has(func_name)) {
                    ctx.needs_allocator = true;
                }
                try ctx.calls.append(ctx.allocator, .{ .module = "", .name = func_name, .class_name = null });
            } else if (call.func.* == .attribute) {
                const attr = call.func.attribute;
                const method_name = attr.attr;
                if (IoFunctions.has(method_name) or IoMethods.has(method_name)) {
                    ctx.has_io = true;
                    ctx.is_pure = false;
                }
                if (ErrorFunctions.get(method_name)) |errors| {
                    ctx.can_error = true;
                    ctx.error_set = ctx.error_set.merge(errors);
                }
                if (ListMutationMethods.has(method_name)) {
                    ctx.is_pure = false;
                    if (attr.value.* == .name) {
                        try checkParamMutation(attr.value.name.id, ctx);
                    }
                }
                try analyzeExprForTraits(attr.value.*, ctx);
            }
            for (call.args) |arg| {
                try analyzeExprForTraits(arg, ctx);
            }
            for (call.keyword_args) |kw| {
                try analyzeExprForTraits(kw.value, ctx);
            }
            ctx.op_count += 2;
        },
        .name => |n| {
            try ctx.markParamUsed(n.id);
            try ctx.checkVarEscape(n.id);
            if (!ctx.scope_vars.contains(n.id)) {
                try ctx.captured.append(ctx.allocator, n.id);
                ctx.reads_globals = true;
            }
        },
        .binop => |binop| {
            try analyzeExprForTraits(binop.left.*, ctx);
            try analyzeExprForTraits(binop.right.*, ctx);
            ctx.op_count += 1;
        },
        .unaryop => |unary| {
            try analyzeExprForTraits(unary.operand.*, ctx);
            ctx.op_count += 1;
        },
        .compare => |comp| {
            try analyzeExprForTraits(comp.left.*, ctx);
            for (comp.comparators) |c| {
                try analyzeExprForTraits(c, ctx);
            }
            ctx.op_count += 1;
        },
        .boolop => |boolop| {
            for (boolop.values) |val| {
                try analyzeExprForTraits(val, ctx);
            }
        },
        .subscript => |sub| {
            try analyzeExprForTraits(sub.value.*, ctx);
            switch (sub.slice) {
                .index => |idx| {
                    try analyzeExprForTraits(idx.*, ctx);
                    ctx.can_error = true;
                    ctx.error_set.KeyError = true;
                    ctx.error_set.IndexError = true;
                },
                .slice => |rng| {
                    if (rng.lower) |l| try analyzeExprForTraits(l.*, ctx);
                    if (rng.upper) |u| try analyzeExprForTraits(u.*, ctx);
                    if (rng.step) |st| try analyzeExprForTraits(st.*, ctx);
                    ctx.can_error = true;
                    ctx.error_set.IndexError = true;
                },
            }
            ctx.op_count += 1;
        },
        .attribute => |attr| {
            try analyzeExprForTraits(attr.value.*, ctx);
            ctx.op_count += 1;
        },
        .list => |list| {
            ctx.needs_allocator = true;
            for (list.elts) |elt| {
                try analyzeExprForTraits(elt, ctx);
            }
            ctx.op_count += 1;
        },
        .dict => |dict| {
            ctx.needs_allocator = true;
            for (dict.keys) |key| {
                try analyzeExprForTraits(key, ctx);
            }
            for (dict.values) |val| {
                try analyzeExprForTraits(val, ctx);
            }
            ctx.op_count += 1;
        },
        .tuple => |tuple| {
            for (tuple.elts) |elt| {
                try analyzeExprForTraits(elt, ctx);
            }
        },
        .if_expr => |tern| {
            try analyzeExprForTraits(tern.condition.*, ctx);
            try analyzeExprForTraits(tern.body.*, ctx);
            try analyzeExprForTraits(tern.orelse_value.*, ctx);
        },
        .listcomp, .dictcomp, .genexp => {
            ctx.needs_allocator = true;
            ctx.has_loops = true;
        },
        .lambda => |lam| {
            try analyzeExprForTraits(lam.body.*, ctx);
        },
        .fstring => |fs| {
            ctx.needs_allocator = true;
            for (fs.parts) |part| {
                switch (part) {
                    .expr => |e| try analyzeExprForTraits(e.node.*, ctx),
                    .format_expr => |fe| try analyzeExprForTraits(fe.expr.*, ctx),
                    .conv_expr => |ce| try analyzeExprForTraits(ce.expr.*, ctx),
                    .literal => {},
                }
            }
        },
        .starred => |st| try analyzeExprForTraits(st.value.*, ctx),
        else => {},
    }
}

fn checkMutation(target: ast.Node, ctx: *AnalyzerContext) !void {
    switch (target) {
        .attribute => |attr| {
            if (attr.value.* == .name) {
                try checkParamMutation(attr.value.name.id, ctx);
            }
        },
        .subscript => |sub| {
            if (sub.value.* == .name) {
                try checkParamMutation(sub.value.name.id, ctx);
            }
        },
        .name => |n| {
            try checkParamMutation(n.id, ctx);
        },
        else => {},
    }
}

fn checkParamMutation(name: []const u8, ctx: *AnalyzerContext) !void {
    for (ctx.param_names, 0..) |param, i| {
        if (std.mem.eql(u8, param, name)) {
            if (i < ctx.param_mutations.items.len) {
                ctx.param_mutations.items[i] = true;
            }
            ctx.is_pure = false;
            return;
        }
    }
}

fn markEscapingExpr(expr: ast.Node, ctx: *AnalyzerContext) !void {
    switch (expr) {
        .name => |n| {
            for (ctx.param_names, 0..) |param, i| {
                if (std.mem.eql(u8, param, n.id)) {
                    if (i < ctx.escaping_params.items.len) {
                        ctx.escaping_params.items[i] = true;
                    }
                    return;
                }
            }
            if (ctx.local_vars.contains(n.id)) {
                for (ctx.escaping_locals.items) |local| {
                    if (std.mem.eql(u8, local, n.id)) return;
                }
                try ctx.escaping_locals.append(ctx.allocator, n.id);
            }
        },
        .tuple => |t| {
            for (t.elts) |elt| try markEscapingExpr(elt, ctx);
        },
        .list => |l| {
            for (l.elts) |elt| try markEscapingExpr(elt, ctx);
        },
        .subscript => |sub| {
            try markEscapingExpr(sub.value.*, ctx);
        },
        .attribute => |attr| {
            try markEscapingExpr(attr.value.*, ctx);
        },
        .call => |call| {
            for (call.args) |arg| {
                try markEscapingExpr(arg, ctx);
            }
        },
        .if_expr => |tern| {
            try markEscapingExpr(tern.body.*, ctx);
            try markEscapingExpr(tern.orelse_value.*, ctx);
        },
        else => {},
    }
}

fn isTailRecursive(stmt: ast.Node, func_name: []const u8) bool {
    if (stmt != .return_stmt) return false;
    const ret = stmt.return_stmt;
    if (ret.value == null) return false;

    const val = ret.value.?.*;
    if (val != .call) return false;

    const call = val.call;
    if (call.func.* != .name) return false;

    return std.mem.eql(u8, call.func.name.id, func_name);
}

fn computeAsyncComplexity(ctx: *const AnalyzerContext) AsyncComplexity {
    if (ctx.op_count <= 5 and ctx.await_count == 0 and !ctx.has_loops) {
        return .trivial;
    }
    if (ctx.op_count <= 20 and ctx.await_count <= 1 and !ctx.has_loops and !ctx.is_tail_recursive) {
        return .simple;
    }
    if (ctx.await_count <= 5) {
        return .moderate;
    }
    return .complex;
}

fn markReachable(graph: *CallGraph, allocator: std.mem.Allocator) !void {
    var worklist = std.ArrayList([]const u8){};
    defer worklist.deinit(allocator);

    var it = graph.functions.iterator();
    while (it.next()) |entry| {
        const name = entry.key_ptr.*;
        if (std.mem.startsWith(u8, name, "test_") or
            std.mem.eql(u8, name, "main") or
            std.mem.eql(u8, name, "__init__") or
            std.mem.eql(u8, name, "__new__"))
        {
            entry.value_ptr.is_called = true;
            try worklist.append(allocator, name);
        }
    }

    while (worklist.items.len > 0) {
        const name = worklist.pop() orelse break;
        if (graph.functions.get(name)) |traits_val| {
            for (traits_val.calls) |call| {
                if (graph.functions.getPtr(call.name)) |callee_ptr| {
                    if (!callee_ptr.is_called) {
                        callee_ptr.is_called = true;
                        try worklist.append(allocator, call.name);
                    }
                }
            }
        }
    }
}
