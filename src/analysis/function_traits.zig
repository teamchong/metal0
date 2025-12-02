/// Unified function traits analysis framework
/// Build call graph once, query for multiple codegen decisions
///
/// One analysis, many uses:
/// | Trait                  | Used For                                      |
/// |------------------------|-----------------------------------------------|
/// | has_io_await           | Async strategy (state machine vs thread pool) |
/// | mutates_params         | var vs const parameters                       |
/// | can_error              | !T vs T return type                           |
/// | needs_allocator        | Pass allocator or not                         |
/// | is_pure                | Memoization / comptime eval                   |
/// | is_tail_recursive      | Tail call optimization                        |
/// | captures_vars          | Closure generation                            |
/// | is_generator           | Generator state machine                       |
/// | calls                  | Call graph edges for dead code elimination    |
const std = @import("std");
const ast = @import("ast");
const hashmap_helper = @import("hashmap_helper");

/// Reference to a function (module-qualified name)
pub const FunctionRef = struct {
    module: []const u8, // Empty string for current module
    name: []const u8,
    class_name: ?[]const u8 = null, // For methods

    pub fn format(self: FunctionRef, comptime _: []const u8, _: std.fmt.FormatOptions, writer: anytype) !void {
        if (self.module.len > 0) {
            try writer.print("{s}.", .{self.module});
        }
        if (self.class_name) |cls| {
            try writer.print("{s}.", .{cls});
        }
        try writer.print("{s}", .{self.name});
    }

    pub fn eql(self: FunctionRef, other: FunctionRef) bool {
        return std.mem.eql(u8, self.module, other.module) and
            std.mem.eql(u8, self.name, other.name) and
            ((self.class_name == null and other.class_name == null) or
            (self.class_name != null and other.class_name != null and
            std.mem.eql(u8, self.class_name.?, other.class_name.?)));
    }
};

/// Traits computed for each function
pub const FunctionTraits = struct {
    /// Function reference
    ref: FunctionRef,

    /// Whether function contains await expressions
    has_await: bool = false,

    /// Whether function contains I/O operations (file, network, print)
    has_io: bool = false,

    /// Which parameters are mutated (indexed by param position)
    mutates_params: []bool = &.{},

    /// Whether function can raise/return an error
    can_error: bool = false,

    /// Whether function needs an allocator parameter
    needs_allocator: bool = false,

    /// Whether function is pure (no I/O, no side effects)
    is_pure: bool = true,

    /// Whether function is tail-recursive
    is_tail_recursive: bool = false,

    /// Whether function is a generator (contains yield)
    is_generator: bool = false,

    /// Variables captured from outer scope (for closures)
    captured_vars: []const []const u8 = &.{},

    /// Functions called directly by this function
    calls: []FunctionRef = &.{},

    /// Whether this function is called by anyone (for DCE)
    is_called: bool = false,

    /// Whether function modifies global state
    modifies_globals: bool = false,

    /// Whether function reads global state
    reads_globals: bool = false,

    /// Async complexity classification
    async_complexity: AsyncComplexity = .trivial,

    /// Return type hint (if determinable)
    return_type_hint: ?TypeHint = null,

    pub fn deinit(self: *FunctionTraits, allocator: std.mem.Allocator) void {
        if (self.mutates_params.len > 0) allocator.free(self.mutates_params);
        if (self.captured_vars.len > 0) allocator.free(self.captured_vars);
        if (self.calls.len > 0) allocator.free(self.calls);
    }
};

pub const AsyncComplexity = enum {
    trivial, // Single expression, no calls - inline always
    simple, // Few operations, no loops - prefer inline
    moderate, // Has loops or multiple awaits - generate both
    complex, // Recursive or many awaits - spawn only
};

pub const TypeHint = enum {
    void,
    int,
    float,
    bool,
    string,
    list,
    dict,
    tuple,
    none,
    object,
    any,
};

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
            var traits = entry.value_ptr.*;
            traits.deinit(self.allocator);
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
        if (self.functions.get(name)) |traits| {
            return traits.is_called;
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

        if (self.functions.get(name)) |traits| {
            for (traits.calls) |call| {
                try result.append(allocator, call);
                try self.collectTransitiveCalls(call.name, visited, result, allocator);
            }
        }
    }
};

/// Analyzer context for building traits
const AnalyzerContext = struct {
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

    pub fn init(allocator: std.mem.Allocator) AnalyzerContext {
        return .{
            .allocator = allocator,
            .scope_vars = hashmap_helper.StringHashMap(void).init(allocator),
            .param_mutations = std.ArrayList(bool){},
            .calls = std.ArrayList(FunctionRef){},
            .captured = std.ArrayList([]const u8){},
        };
    }

    pub fn deinit(self: *AnalyzerContext) void {
        self.scope_vars.deinit();
        self.param_mutations.deinit(self.allocator);
        self.calls.deinit(self.allocator);
        self.captured.deinit(self.allocator);
    }

    pub fn reset(self: *AnalyzerContext) void {
        self.scope_vars.clearRetainingCapacity();
        self.param_mutations.clearRetainingCapacity();
        self.calls.clearRetainingCapacity();
        self.captured.clearRetainingCapacity();
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
    }
};

/// I/O function names that trigger state machine async (actual async I/O operations)
/// NOTE: Excludes print (sync), includes only operations that benefit from kqueue/epoll
const IoFunctions = std.StaticStringMap(void).initComptime(.{
    // File I/O (async benefits from OS-level polling)
    .{ "input", {} },  // stdin waits for user input
    .{ "open", {} },
    .{ "read", {} },
    .{ "write", {} },
    .{ "close", {} },
    // Network/HTTP
    .{ "get", {} },
    .{ "post", {} },
    .{ "put", {} },
    .{ "delete", {} },
    .{ "patch", {} },
    .{ "request", {} },
    .{ "fetch", {} },
    .{ "connect", {} },
    .{ "send", {} },
    .{ "recv", {} },
    .{ "sendall", {} },
    .{ "recvfrom", {} },
    .{ "sendto", {} },
    // Async I/O (actual I/O operations, not coordination primitives)
    .{ "sleep", {} },  // Timer I/O via kqueue/epoll
    // Subprocess
    .{ "call", {} },
    .{ "check_call", {} },
    .{ "check_output", {} },
    .{ "communicate", {} },
    .{ "Popen", {} },
});

/// Functions that can raise errors
const ErrorFunctions = std.StaticStringMap(void).initComptime(.{
    .{ "raise", {} },
    .{ "assert", {} },
    .{ "open", {} },
    .{ "int", {} },
    .{ "float", {} },
    .{ "eval", {} },
    .{ "exec", {} },
});

/// Functions that require allocator
const AllocatorFunctions = std.StaticStringMap(void).initComptime(.{
    .{ "list", {} },
    .{ "dict", {} },
    .{ "set", {} },
    .{ "str", {} },
    .{ "bytes", {} },
    .{ "bytearray", {} },
    .{ "range", {} },
    .{ "map", {} },
    .{ "filter", {} },
    .{ "sorted", {} },
    .{ "reversed", {} },
    .{ "enumerate", {} },
    .{ "zip", {} },
});

/// Build call graph from a module
pub fn buildCallGraph(module: ast.Node.Module, allocator: std.mem.Allocator) !CallGraph {
    var graph = CallGraph.init(allocator);
    errdefer graph.deinit();

    var ctx = AnalyzerContext.init(allocator);
    defer ctx.deinit();

    // First pass: collect all function definitions
    for (module.body) |stmt| {
        try collectDefinitions(stmt, &graph, &ctx);
    }

    // Second pass: analyze each function's traits
    for (module.body) |stmt| {
        try analyzeStatement(stmt, &graph, &ctx);
    }

    // Third pass: mark reachable functions from entry points
    try markReachable(&graph, allocator);

    return graph;
}

/// Collect function and class definitions
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

/// Analyze a statement for traits
fn analyzeStatement(stmt: ast.Node, graph: *CallGraph, ctx: *AnalyzerContext) !void {
    switch (stmt) {
        .function_def => |func| {
            ctx.reset();
            ctx.current_func = func.name;

            // Set up parameter tracking
            var param_names = std.ArrayList([]const u8){};
            defer param_names.deinit(ctx.allocator);

            for (func.args) |arg| {
                try param_names.append(ctx.allocator, arg.name);
                try ctx.scope_vars.put(arg.name, {});
                try ctx.param_mutations.append(ctx.allocator, false);
            }
            ctx.param_names = param_names.items;

            // Analyze function body
            for (func.body) |body_stmt| {
                try analyzeStmtForTraits(body_stmt, ctx);
            }

            // Check for tail recursion (last statement is return with recursive call)
            if (func.body.len > 0) {
                ctx.is_tail_recursive = isTailRecursive(func.body[func.body.len - 1], func.name);
            }

            // Build traits
            var traits = graph.functions.get(func.name) orelse FunctionTraits{
                .ref = .{ .module = ctx.current_module, .name = func.name, .class_name = ctx.current_class },
            };

            traits.has_await = ctx.has_await;
            traits.has_io = ctx.has_io;
            traits.can_error = ctx.can_error;
            traits.needs_allocator = ctx.needs_allocator;
            traits.is_pure = ctx.is_pure and !ctx.has_io and !ctx.modifies_globals;
            traits.is_tail_recursive = ctx.is_tail_recursive;
            traits.is_generator = ctx.is_generator;
            traits.modifies_globals = ctx.modifies_globals;
            traits.reads_globals = ctx.reads_globals;
            traits.async_complexity = computeAsyncComplexity(ctx);

            // Copy mutation info
            if (ctx.param_mutations.items.len > 0) {
                traits.mutates_params = try ctx.allocator.dupe(bool, ctx.param_mutations.items);
            }

            // Copy calls
            if (ctx.calls.items.len > 0) {
                traits.calls = try ctx.allocator.dupe(FunctionRef, ctx.calls.items);
            }

            // Copy captured vars
            if (ctx.captured.items.len > 0) {
                traits.captured_vars = try ctx.allocator.dupe([]const u8, ctx.captured.items);
            }

            try graph.functions.put(func.name, traits);
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
            // Track global modifications at module level
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

/// Analyze a statement for trait flags
fn analyzeStmtForTraits(stmt: ast.Node, ctx: *AnalyzerContext) !void {
    switch (stmt) {
        .expr_stmt => |expr| {
            try analyzeExprForTraits(expr.value.*, ctx);
        },
        .assign => |assign| {
            // Check for parameter mutation via attribute/subscript assignment
            for (assign.targets) |target| {
                try checkMutation(target, ctx);
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
            }
            ctx.op_count += 1;
        },
        .raise_stmt => {
            ctx.can_error = true;
            ctx.is_pure = false;
        },
        .if_stmt => |if_stmt| {
            try analyzeExprForTraits(if_stmt.condition.*, ctx);
            for (if_stmt.body) |s| try analyzeStmtForTraits(s, ctx);
            for (if_stmt.else_body) |s| try analyzeStmtForTraits(s, ctx);
            ctx.op_count += 2;
        },
        .while_stmt => |while_stmt| {
            ctx.has_loops = true;
            try analyzeExprForTraits(while_stmt.condition.*, ctx);
            for (while_stmt.body) |s| try analyzeStmtForTraits(s, ctx);
            ctx.op_count += 5;
        },
        .for_stmt => |for_stmt| {
            ctx.has_loops = true;
            try analyzeExprForTraits(for_stmt.iter.*, ctx);
            for (for_stmt.body) |s| try analyzeStmtForTraits(s, ctx);
            ctx.op_count += 5;
        },
        .try_stmt => |try_stmt| {
            ctx.can_error = true;
            for (try_stmt.body) |s| try analyzeStmtForTraits(s, ctx);
            for (try_stmt.handlers) |h| {
                for (h.body) |s| try analyzeStmtForTraits(s, ctx);
            }
            for (try_stmt.else_body) |s| try analyzeStmtForTraits(s, ctx);
            for (try_stmt.finalbody) |s| try analyzeStmtForTraits(s, ctx);
        },
        .with_stmt => |with_stmt| {
            try analyzeExprForTraits(with_stmt.context_expr.*, ctx);
            for (with_stmt.body) |s| try analyzeStmtForTraits(s, ctx);
        },
        .function_def => {
            // Nested function - check for captures
            // This is handled separately
        },
        .yield_stmt, .yield_from_stmt => {
            ctx.is_generator = true;
        },
        else => {
            ctx.op_count += 1;
        },
    }
}

/// Analyze an expression for trait flags
fn analyzeExprForTraits(expr: ast.Node, ctx: *AnalyzerContext) error{OutOfMemory}!void {
    switch (expr) {
        .await_expr => |await_expr| {
            ctx.has_await = true;
            ctx.await_count += 1;
            try analyzeExprForTraits(await_expr.value.*, ctx);
        },
        .yield_stmt => {
            ctx.is_generator = true;
        },
        .yield_from_stmt => {
            ctx.is_generator = true;
        },
        .call => |call| {
            // Check function name for traits
            if (call.func.* == .name) {
                const func_name = call.func.name.id;

                // Check if it's a recursive call
                if (ctx.current_func != null and std.mem.eql(u8, func_name, ctx.current_func.?)) {
                    // Self-recursive call
                }

                // I/O functions
                if (IoFunctions.has(func_name)) {
                    ctx.has_io = true;
                    ctx.is_pure = false;
                }

                // Error-raising functions
                if (ErrorFunctions.has(func_name)) {
                    ctx.can_error = true;
                }

                // Allocator-requiring functions
                if (AllocatorFunctions.has(func_name)) {
                    ctx.needs_allocator = true;
                }

                // Record call
                try ctx.calls.append(ctx.allocator, .{
                    .module = "",
                    .name = func_name,
                    .class_name = null,
                });
            } else if (call.func.* == .attribute) {
                const attr = call.func.attribute;
                const method_name = attr.attr;

                // I/O methods (also check IoFunctions for method calls)
                if (IoFunctions.has(method_name) or
                    std.mem.eql(u8, method_name, "flush") or
                    std.mem.eql(u8, method_name, "readline") or
                    std.mem.eql(u8, method_name, "readlines") or
                    std.mem.eql(u8, method_name, "writelines") or
                    std.mem.eql(u8, method_name, "json") or // response.json()
                    std.mem.eql(u8, method_name, "text")) // response.text()
                {
                    ctx.has_io = true;
                    ctx.is_pure = false;
                }

                // Mutating list methods
                if (std.mem.eql(u8, method_name, "append") or
                    std.mem.eql(u8, method_name, "extend") or
                    std.mem.eql(u8, method_name, "insert") or
                    std.mem.eql(u8, method_name, "pop") or
                    std.mem.eql(u8, method_name, "remove") or
                    std.mem.eql(u8, method_name, "clear") or
                    std.mem.eql(u8, method_name, "sort") or
                    std.mem.eql(u8, method_name, "reverse"))
                {
                    ctx.is_pure = false;
                    // Check if mutating a parameter
                    if (attr.value.* == .name) {
                        try checkParamMutation(attr.value.name.id, ctx);
                    }
                }

                try analyzeExprForTraits(attr.value.*, ctx);
            }

            // Analyze arguments
            for (call.args) |arg| {
                try analyzeExprForTraits(arg, ctx);
            }
            ctx.op_count += 2;
        },
        .name => |n| {
            // Check if accessing variable from outer scope (closure capture)
            if (!ctx.scope_vars.contains(n.id)) {
                // Could be a captured variable or global
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
                .index => |idx| try analyzeExprForTraits(idx.*, ctx),
                .slice => |rng| {
                    if (rng.lower) |l| try analyzeExprForTraits(l.*, ctx);
                    if (rng.upper) |u| try analyzeExprForTraits(u.*, ctx);
                    if (rng.step) |st| try analyzeExprForTraits(st.*, ctx);
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
        else => {},
    }
}

/// Check if a target expression mutates a parameter
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
            // Direct reassignment of parameter
            try checkParamMutation(n.id, ctx);
        },
        else => {},
    }
}

/// Check if name is a parameter and mark it as mutated
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

/// Check if a statement is a tail-recursive return
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

/// Compute async complexity from context
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

/// Mark functions reachable from entry points
fn markReachable(graph: *CallGraph, allocator: std.mem.Allocator) !void {
    var worklist = std.ArrayList([]const u8){};
    defer worklist.deinit(allocator);

    // Entry points: module-level code, main, test functions
    var it = graph.functions.iterator();
    while (it.next()) |entry| {
        const name = entry.key_ptr.*;
        // Mark test functions and main as entry points
        if (std.mem.startsWith(u8, name, "test_") or
            std.mem.eql(u8, name, "main") or
            std.mem.eql(u8, name, "__init__") or
            std.mem.eql(u8, name, "__new__"))
        {
            entry.value_ptr.is_called = true;
            try worklist.append(allocator, name);
        }
    }

    // Propagate reachability
    while (worklist.items.len > 0) {
        const name = worklist.pop() orelse break;
        if (graph.functions.get(name)) |traits| {
            for (traits.calls) |call| {
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

// ============================================================================
// Query API - Use these in codegen
// ============================================================================

/// Check if function should use state machine async (has I/O await)
pub fn shouldUseStateMachineAsync(graph: *const CallGraph, name: []const u8) bool {
    if (graph.functions.get(name)) |traits| {
        return traits.has_await and traits.has_io;
    }
    return false;
}

/// Check if ANY async function in module has I/O
/// Used to ensure all async functions use same interface (for gather compatibility)
pub fn anyAsyncHasIO(graph: *const CallGraph) bool {
    var it = graph.functions.iterator();
    while (it.next()) |entry| {
        const traits = entry.value_ptr.*;
        if (traits.has_await and traits.has_io) return true;
    }
    return false;
}

/// Check if parameter should be `var` (mutated) vs `const`
pub fn isParamMutated(graph: *const CallGraph, func_name: []const u8, param_idx: usize) bool {
    if (graph.functions.get(func_name)) |traits| {
        if (param_idx < traits.mutates_params.len) {
            return traits.mutates_params[param_idx];
        }
    }
    return false;
}

/// Check if function needs error union return type
pub fn needsErrorUnion(graph: *const CallGraph, name: []const u8) bool {
    if (graph.functions.get(name)) |traits| {
        return traits.can_error;
    }
    return false;
}

/// Check if function needs allocator parameter
pub fn needsAllocator(graph: *const CallGraph, name: []const u8) bool {
    if (graph.functions.get(name)) |traits| {
        return traits.needs_allocator;
    }
    return false;
}

/// Check if function is pure (can be memoized/comptime evaluated)
pub fn isPure(graph: *const CallGraph, name: []const u8) bool {
    if (graph.functions.get(name)) |traits| {
        return traits.is_pure;
    }
    return false;
}

/// Check if function can use tail call optimization
pub fn canUseTCO(graph: *const CallGraph, name: []const u8) bool {
    if (graph.functions.get(name)) |traits| {
        return traits.is_tail_recursive;
    }
    return false;
}

/// Check if function is a generator
pub fn isGenerator(graph: *const CallGraph, name: []const u8) bool {
    if (graph.functions.get(name)) |traits| {
        return traits.is_generator;
    }
    return false;
}

/// Get captured variables for closure generation
pub fn getCapturedVars(graph: *const CallGraph, name: []const u8) []const []const u8 {
    if (graph.functions.get(name)) |traits| {
        return traits.captured_vars;
    }
    return &.{};
}

/// Check if function is dead code (not reachable)
pub fn isDeadCode(graph: *const CallGraph, name: []const u8) bool {
    if (graph.functions.get(name)) |traits| {
        return !traits.is_called;
    }
    return true;
}

/// Get async complexity for optimization decisions
pub fn getAsyncComplexity(graph: *const CallGraph, name: []const u8) AsyncComplexity {
    if (graph.functions.get(name)) |traits| {
        return traits.async_complexity;
    }
    return .trivial;
}

// ============================================================================
// Tests
// ============================================================================

test "build call graph from simple function" {
    const allocator = std.testing.allocator;

    // This would need actual AST construction which is complex
    // In practice, test via integration with parser
    _ = allocator;
}
