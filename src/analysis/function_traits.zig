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

    /// Whether function needs an allocator parameter (for error union return)
    needs_allocator: bool = false,

    /// Whether function actually uses the allocator param (vs __global_allocator)
    uses_allocator_param: bool = false,

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

    // ========== ESCAPE ANALYSIS ==========
    /// Which parameters escape this function (returned, stored globally, passed to escaping call)
    escaping_params: []bool = &.{},
    /// Local variables that escape (by name)
    escaping_locals: []const []const u8 = &.{},
    /// If return value aliases a parameter, which one? (for ownership tracking)
    return_aliases_param: ?usize = null,

    pub fn deinit(self: *FunctionTraits, allocator: std.mem.Allocator) void {
        if (self.mutates_params.len > 0) allocator.free(self.mutates_params);
        if (self.captured_vars.len > 0) allocator.free(self.captured_vars);
        if (self.calls.len > 0) allocator.free(self.calls);
        if (self.escaping_params.len > 0) allocator.free(self.escaping_params);
        if (self.escaping_locals.len > 0) allocator.free(self.escaping_locals);
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

// ============================================================================
// SIMD Vectorization Analysis
// ============================================================================

/// SIMD vectorization info for list comprehensions
pub const SimdInfo = struct {
    /// Can this comprehension be vectorized?
    vectorizable: bool = false,
    /// Element type (i64, f64)
    element_type: SimdElementType = .i64,
    /// The vectorizable operation
    op: SimdOp = .none,
    /// Vector width to use (4, 8, 16)
    vector_width: u8 = 8,
    /// Is the source a contiguous range?
    is_range: bool = false,
    /// Static range bounds (if known)
    range_start: ?i64 = null,
    range_end: ?i64 = null,
};

pub const SimdElementType = enum { i64, f64, i32, f32 };

pub const SimdOp = enum {
    none,
    // Arithmetic
    add, // x + c or c + x
    sub, // x - c or c - x
    mul, // x * c or c * x
    div, // x / c
    neg, // -x
    // Bitwise
    bit_and,
    bit_or,
    bit_xor,
    shl, // x << c
    shr, // x >> c
    // Compound
    mul_add, // x * a + b (FMA)
    square, // x * x
};

/// Analyze a list comprehension for SIMD vectorization potential
pub fn analyzeListCompForSimd(listcomp: ast.Node.ListComp) SimdInfo {
    var info = SimdInfo{};

    // Must have exactly one generator with no conditions
    if (listcomp.generators.len != 1) return info;
    const gen = listcomp.generators[0];
    if (gen.ifs.len > 0) return info; // Conditionals break vectorization

    // Check if iterating over range()
    if (gen.iter.* == .call and gen.iter.call.func.* == .name) {
        if (std.mem.eql(u8, gen.iter.call.func.name.id, "range")) {
            info.is_range = true;
            const args = gen.iter.call.args;
            // Extract static bounds if possible
            if (args.len >= 1 and args[0] == .constant and args[0].constant.value == .int) {
                if (args.len == 1) {
                    info.range_start = 0;
                    info.range_end = args[0].constant.value.int;
                } else if (args.len >= 2 and args[1] == .constant and args[1].constant.value == .int) {
                    info.range_start = args[0].constant.value.int;
                    info.range_end = args[1].constant.value.int;
                }
            }
        }
    }

    // Target must be a simple name
    if (gen.target.* != .name) return info;
    const loop_var = gen.target.name.id;

    // Analyze the element expression
    const elt = listcomp.elt.*;
    const op_info = analyzeSimdExpr(elt, loop_var);
    if (op_info.op == .none) return info;

    info.vectorizable = true;
    info.op = op_info.op;
    info.element_type = op_info.element_type;

    // Choose vector width based on element type
    info.vector_width = switch (info.element_type) {
        .i64, .f64 => 4, // 256-bit vectors / 64-bit = 4 elements
        .i32, .f32 => 8, // 256-bit vectors / 32-bit = 8 elements
    };

    return info;
}

const SimdExprInfo = struct {
    op: SimdOp = .none,
    element_type: SimdElementType = .i64,
    constant: ?i64 = null,
};

/// Analyze expression to determine if it's a simple vectorizable op
fn analyzeSimdExpr(expr: ast.Node, loop_var: []const u8) SimdExprInfo {
    var info = SimdExprInfo{};

    switch (expr) {
        .name => |n| {
            // Just the loop variable: identity (can still vectorize as copy)
            if (std.mem.eql(u8, n.id, loop_var)) {
                info.op = .add; // x + 0 is identity
                info.constant = 0;
                return info;
            }
        },
        .binop => |b| {
            // Check for simple patterns: x op const, const op x
            const left_is_var = b.left.* == .name and std.mem.eql(u8, b.left.name.id, loop_var);
            const right_is_var = b.right.* == .name and std.mem.eql(u8, b.right.name.id, loop_var);
            const left_is_const = b.left.* == .constant and b.left.constant.value == .int;
            const right_is_const = b.right.* == .constant and b.right.constant.value == .int;

            // x * x pattern (square)
            if (left_is_var and right_is_var and b.op == .Mult) {
                info.op = .square;
                return info;
            }

            // x op const or const op x
            if ((left_is_var and right_is_const) or (left_is_const and right_is_var)) {
                const c = if (right_is_const) b.right.constant.value.int else b.left.constant.value.int;
                info.constant = c;

                info.op = switch (b.op) {
                    .Add => .add,
                    .Sub => if (left_is_var) .sub else .none, // const - x not simple
                    .Mult => .mul,
                    .Div, .FloorDiv => if (left_is_var) .div else .none,
                    .BitOr => .bit_or,
                    .BitAnd => .bit_and,
                    .BitXor => .bit_xor,
                    .LShift => if (left_is_var) .shl else .none,
                    .RShift => if (left_is_var) .shr else .none,
                    else => .none,
                };
                return info;
            }
        },
        .unaryop => |u| {
            // -x pattern
            if (u.op == .USub and u.operand.* == .name and std.mem.eql(u8, u.operand.name.id, loop_var)) {
                info.op = .neg;
                return info;
            }
        },
        else => {},
    }

    return info;
}

// ============================================================================
// Parallelization Analysis
// ============================================================================

/// Info about whether a list comprehension can be parallelized
pub const ParallelInfo = struct {
    /// Can this be safely parallelized?
    parallelizable: bool = false,
    /// Is it a large enough workload to benefit from parallelization?
    worth_parallelizing: bool = false,
    /// Minimum threshold for parallel (smaller runs sequentially)
    min_parallel_size: usize = 1024,
    /// Operation type (for runtime.parallel)
    op: SimdOp = .none,
};

/// Check if a list comprehension can be safely parallelized
/// Requires: pure element expression, no loop-carried dependencies
pub fn analyzeListCompForParallel(listcomp: ast.Node.ListComp) ParallelInfo {
    var info = ParallelInfo{};

    // Must have exactly one generator
    if (listcomp.generators.len != 1) return info;
    const gen = listcomp.generators[0];

    // Conditionals make parallelization complex (varying output size)
    if (gen.ifs.len > 0) return info;

    // Target must be simple name
    if (gen.target.* != .name) return info;
    const loop_var = gen.target.name.id;

    // Check if element expression is pure and parallelizable
    if (!isParallelizableExpr(listcomp.elt.*, loop_var)) return info;

    // Check for large range (worth parallelizing)
    if (gen.iter.* == .call and gen.iter.call.func.* == .name) {
        if (std.mem.eql(u8, gen.iter.call.func.name.id, "range")) {
            const args = gen.iter.call.args;
            if (args.len >= 1 and args[0] == .constant and args[0].constant.value == .int) {
                const end_val = if (args.len == 1)
                    args[0].constant.value.int
                else if (args.len >= 2 and args[1] == .constant and args[1].constant.value == .int)
                    args[1].constant.value.int
                else
                    0;
                const start_val: i64 = if (args.len >= 2 and args[0] == .constant and args[0].constant.value == .int)
                    args[0].constant.value.int
                else
                    0;

                const size = end_val - start_val;
                info.worth_parallelizing = size >= info.min_parallel_size;
            }
        }
    }

    // Get the operation type
    const simd_info = analyzeSimdExpr(listcomp.elt.*, loop_var);
    info.op = simd_info.op;
    info.parallelizable = simd_info.op != .none;

    return info;
}

/// Check if expression is safe to parallelize (no side effects, no shared state)
fn isParallelizableExpr(expr: ast.Node, loop_var: []const u8) bool {
    return switch (expr) {
        .name => |n| std.mem.eql(u8, n.id, loop_var), // Only loop var is safe
        .constant => true,
        .binop => |b| isParallelizableExpr(b.left.*, loop_var) and isParallelizableExpr(b.right.*, loop_var),
        .unaryop => |u| isParallelizableExpr(u.operand.*, loop_var),
        // Function calls are NOT parallelizable (might have side effects)
        .call => false,
        // Attribute access might access shared state
        .attribute => false,
        // Subscript might access shared state
        .subscript => false,
        else => false,
    };
}

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

    // Escape analysis
    escaping_params: std.ArrayList(bool),
    escaping_locals: std.ArrayList([]const u8),
    local_vars: hashmap_helper.StringHashMap(void), // Track locally defined vars
    return_aliases_param: ?usize = null,

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
    }

    pub fn reset(self: *AnalyzerContext) void {
        self.scope_vars.clearRetainingCapacity();
        self.param_mutations.clearRetainingCapacity();
        self.calls.clearRetainingCapacity();
        self.captured.clearRetainingCapacity();
        self.escaping_params.clearRetainingCapacity();
        self.escaping_locals.clearRetainingCapacity();
        self.local_vars.clearRetainingCapacity();
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

/// I/O method names (additional methods not in IoFunctions)
const IoMethods = std.StaticStringMap(void).initComptime(.{
    .{ "flush", {} },
    .{ "readline", {} },
    .{ "readlines", {} },
    .{ "writelines", {} },
    .{ "json", {} }, // response.json()
    .{ "text", {} }, // response.text()
});

/// List mutation methods (make function impure)
const ListMutationMethods = std.StaticStringMap(void).initComptime(.{
    .{ "append", {} },
    .{ "extend", {} },
    .{ "insert", {} },
    .{ "pop", {} },
    .{ "remove", {} },
    .{ "clear", {} },
    .{ "sort", {} },
    .{ "reverse", {} },
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
                try ctx.escaping_params.append(ctx.allocator, false); // Initialize escape tracking
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

            // Copy escape analysis results
            if (ctx.escaping_params.items.len > 0) {
                traits.escaping_params = try ctx.allocator.dupe(bool, ctx.escaping_params.items);
            }
            if (ctx.escaping_locals.items.len > 0) {
                traits.escaping_locals = try ctx.allocator.dupe([]const u8, ctx.escaping_locals.items);
            }
            traits.return_aliases_param = ctx.return_aliases_param;

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
                // Track local variable definitions
                if (target == .name) {
                    try ctx.local_vars.put(target.name.id, {});
                }
                // Check if storing param into global (escape)
                if (target == .name and !ctx.scope_vars.contains(target.name.id)) {
                    // Global assignment - check if value is a param
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
                // Mark returned values as escaping
                try markEscapingExpr(val.*, ctx);
                // Check if return directly aliases a param
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

                // I/O methods (check both IoFunctions and IoMethods)
                if (IoFunctions.has(method_name) or IoMethods.has(method_name)) {
                    ctx.has_io = true;
                    ctx.is_pure = false;
                }

                // Mutating list methods
                if (ListMutationMethods.has(method_name)) {
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

/// Mark expression as escaping (returned, stored globally, passed to external func)
fn markEscapingExpr(expr: ast.Node, ctx: *AnalyzerContext) !void {
    switch (expr) {
        .name => |n| {
            // Check if it's a param
            for (ctx.param_names, 0..) |param, i| {
                if (std.mem.eql(u8, param, n.id)) {
                    if (i < ctx.escaping_params.items.len) {
                        ctx.escaping_params.items[i] = true;
                    }
                    return;
                }
            }
            // Check if it's a local var
            if (ctx.local_vars.contains(n.id)) {
                // Check if already marked
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
            // x[i] escapes → x escapes
            try markEscapingExpr(sub.value.*, ctx);
        },
        .attribute => |attr| {
            // x.attr escapes → x escapes
            try markEscapingExpr(attr.value.*, ctx);
        },
        .call => |call| {
            // Function call result can escape - args passed to external func escape
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

/// Check if function needs allocator parameter (for error union return type)
pub fn needsAllocator(graph: *const CallGraph, name: []const u8) bool {
    if (graph.functions.get(name)) |traits| {
        return traits.needs_allocator;
    }
    return false;
}

/// Check if function actually uses allocator param (not just __global_allocator)
pub fn usesAllocatorParam(graph: *const CallGraph, name: []const u8) bool {
    if (graph.functions.get(name)) |traits| {
        return traits.uses_allocator_param;
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
// Escape Analysis Query API
// ============================================================================

/// Check if a parameter escapes its function (returned, stored globally, etc.)
/// If param doesn't escape → can stack allocate caller's argument
pub fn paramEscapes(graph: *const CallGraph, func_name: []const u8, param_idx: usize) bool {
    if (graph.functions.get(func_name)) |traits| {
        if (param_idx < traits.escaping_params.len) {
            return traits.escaping_params[param_idx];
        }
    }
    return true; // Conservative: assume escapes if unknown
}

/// Check if a local variable can be stack allocated (doesn't escape)
pub fn canStackAllocate(graph: *const CallGraph, func_name: []const u8, var_name: []const u8) bool {
    if (graph.functions.get(func_name)) |traits| {
        // If in escaping_locals list, can't stack allocate
        for (traits.escaping_locals) |local| {
            if (std.mem.eql(u8, local, var_name)) return false;
        }
        return true; // Not in escaping list → safe for stack
    }
    return false; // Conservative: heap allocate if unknown
}

/// Get which parameter the return value aliases (if any)
/// Useful for ownership tracking and avoiding copies
pub fn getReturnAliasParam(graph: *const CallGraph, func_name: []const u8) ?usize {
    if (graph.functions.get(func_name)) |traits| {
        return traits.return_aliases_param;
    }
    return null;
}

/// Get all non-escaping locals in a function (candidates for stack allocation)
pub fn getNonEscapingLocals(graph: *const CallGraph, func_name: []const u8) []const []const u8 {
    _ = graph;
    _ = func_name;
    // TODO: Return inverse of escaping_locals once we track all locals
    return &.{};
}

// ============================================================================
// Static AST Analysis (no CallGraph needed)
// ============================================================================

/// Methods that use allocator param
const AllocatorMethods = std.StaticStringMap(void).initComptime(.{
    .{ "upper", {} }, .{ "lower", {} }, .{ "strip", {} }, .{ "split", {} },
    .{ "replace", {} }, .{ "join", {} }, .{ "write", {} }, .{ "getvalue", {} },
});

/// Methods using __global_allocator (need error union but not allocator param)
const GlobalAllocMethods = std.StaticStringMap(void).initComptime(.{
    .{ "hexdigest", {} }, .{ "digest", {} }, .{ "append", {} },
    .{ "extend", {} }, .{ "insert", {} }, .{ "appendleft", {} }, .{ "extendleft", {} },
});

/// Builtins needing allocator
const AllocBuiltins = std.StaticStringMap(void).initComptime(.{
    .{ "str", {} }, .{ "list", {} }, .{ "dict", {} }, .{ "input", {} },
    .{ "StringIO", {} }, .{ "BytesIO", {} }, .{ "int", {} }, .{ "float", {} },
    .{ "Counter", {} }, .{ "deque", {} }, .{ "defaultdict", {} }, .{ "OrderedDict", {} },
});

/// Builtins using __global_allocator
const GlobalAllocBuiltins = std.StaticStringMap(void).initComptime(.{
    .{ "str", {} }, .{ "list", {} }, .{ "dict", {} }, .{ "print", {} },
    .{ "eval", {} }, .{ "exec", {} }, .{ "compile", {} },
});

/// Module functions using allocator param
const ModuleAllocFuncs = std.StaticStringMap(void).initComptime(.{
    .{ "dumps", {} }, .{ "loads", {} }, .{ "match", {} }, .{ "search", {} },
    .{ "findall", {} }, .{ "sub", {} }, .{ "split", {} }, .{ "compile", {} },
    .{ "compress", {} }, .{ "decompress", {} },
});

/// Constructors using allocator
const AllocConstructors = std.StaticStringMap(void).initComptime(.{
    .{ "Counter", {} }, .{ "deque", {} }, .{ "defaultdict", {} },
    .{ "OrderedDict", {} }, .{ "StringIO", {} }, .{ "BytesIO", {} },
});

/// Analyze function AST to determine if it needs allocator (for error union)
pub fn analyzeNeedsAllocator(func: ast.Node.FunctionDef, class_name: ?[]const u8) bool {
    // Check for nested class instantiation
    var nested: [32][]const u8 = undefined;
    var count: usize = 0;
    collectNestedClasses(func.body, &nested, &count);
    if (class_name) |cn| if (count < 32) { nested[count] = cn; count += 1; };
    if (count > 0 and hasNestedClassCalls(func.body, nested[0..count])) return true;

    for (func.body) |stmt| if (stmtNeedsAlloc(stmt)) return true;
    return false;
}

/// Analyze if function actually uses allocator param (not __global_allocator)
pub fn analyzeUsesAllocatorParam(func: ast.Node.FunctionDef, class_name: ?[]const u8) bool {
    _ = class_name; // Same-class calls use __global_allocator
    var nested: [32][]const u8 = undefined;
    var count: usize = 0;
    collectNestedClasses(func.body, &nested, &count);

    for (func.body) |stmt| if (stmtUsesAllocParam(stmt, func.name, nested[0..count])) return true;
    return false;
}

fn collectNestedClasses(stmts: []ast.Node, names: *[32][]const u8, count: *usize) void {
    for (stmts) |stmt| switch (stmt) {
        .class_def => |c| if (count.* < 32) { names[count.*] = c.name; count.* += 1; },
        .if_stmt => |i| { collectNestedClasses(i.body, names, count); collectNestedClasses(i.else_body, names, count); },
        .for_stmt => |f| collectNestedClasses(f.body, names, count),
        .while_stmt => |w| collectNestedClasses(w.body, names, count),
        .try_stmt => |t| { collectNestedClasses(t.body, names, count); for (t.handlers) |h| collectNestedClasses(h.body, names, count); },
        .with_stmt => |w| collectNestedClasses(w.body, names, count),
        else => {},
    };
}

fn hasNestedClassCalls(stmts: []ast.Node, nested: []const []const u8) bool {
    for (stmts) |stmt| if (stmtHasNestedCall(stmt, nested)) return true;
    return false;
}

fn stmtHasNestedCall(stmt: ast.Node, nested: []const []const u8) bool {
    return switch (stmt) {
        .expr_stmt => |e| exprHasNestedCall(e.value.*, nested),
        .assign => |a| exprHasNestedCall(a.value.*, nested),
        .return_stmt => |r| if (r.value) |v| exprHasNestedCall(v.*, nested) else false,
        .if_stmt => |i| exprHasNestedCall(i.condition.*, nested) or hasNestedClassCalls(i.body, nested) or hasNestedClassCalls(i.else_body, nested),
        .while_stmt => |w| exprHasNestedCall(w.condition.*, nested) or hasNestedClassCalls(w.body, nested),
        .for_stmt => |f| exprHasNestedCall(f.iter.*, nested) or hasNestedClassCalls(f.body, nested),
        .try_stmt => |t| blk: { if (hasNestedClassCalls(t.body, nested)) break :blk true; for (t.handlers) |h| if (hasNestedClassCalls(h.body, nested)) break :blk true; break :blk false; },
        .with_stmt => |w| exprHasNestedCall(w.context_expr.*, nested) or hasNestedClassCalls(w.body, nested),
        else => false,
    };
}

fn exprHasNestedCall(expr: ast.Node, nested: []const []const u8) bool {
    return switch (expr) {
        .call => |c| blk: {
            if (c.func.* == .name) for (nested) |n| if (std.mem.eql(u8, c.func.name.id, n)) break :blk true;
            for (c.args) |a| if (exprHasNestedCall(a, nested)) break :blk true;
            break :blk exprHasNestedCall(c.func.*, nested);
        },
        .binop => |b| exprHasNestedCall(b.left.*, nested) or exprHasNestedCall(b.right.*, nested),
        .unaryop => |u| exprHasNestedCall(u.operand.*, nested),
        .attribute => |a| exprHasNestedCall(a.value.*, nested),
        .subscript => |s| exprHasNestedCall(s.value.*, nested) or switch (s.slice) {
            .index => |i| exprHasNestedCall(i.*, nested),
            .slice => |r| (if (r.lower) |l| exprHasNestedCall(l.*, nested) else false) or (if (r.upper) |u| exprHasNestedCall(u.*, nested) else false),
        },
        .tuple => |t| blk: { for (t.elts) |e| if (exprHasNestedCall(e, nested)) break :blk true; break :blk false; },
        .list => |l| blk: { for (l.elts) |e| if (exprHasNestedCall(e, nested)) break :blk true; break :blk false; },
        .compare => |co| blk: { if (exprHasNestedCall(co.left.*, nested)) break :blk true; for (co.comparators) |c| if (exprHasNestedCall(c, nested)) break :blk true; break :blk false; },
        else => false,
    };
}

fn stmtNeedsAlloc(stmt: ast.Node) bool {
    return switch (stmt) {
        .expr_stmt => |e| exprNeedsAlloc(e.value.*),
        .assign => |a| blk: {
            for (a.targets) |t| if (t == .attribute and t.attribute.value.* == .name and std.mem.eql(u8, t.attribute.value.name.id, "self")) break :blk true;
            break :blk exprNeedsAlloc(a.value.*);
        },
        .aug_assign => |a| exprNeedsAlloc(a.value.*),
        .return_stmt => |r| if (r.value) |v| exprNeedsAlloc(v.*) else false,
        .if_stmt => |i| exprNeedsAlloc(i.condition.*) or blk: { for (i.body) |s| if (stmtNeedsAlloc(s)) break :blk true; for (i.else_body) |s| if (stmtNeedsAlloc(s)) break :blk true; break :blk false; },
        .while_stmt => |w| exprNeedsAlloc(w.condition.*) or blk: { for (w.body) |s| if (stmtNeedsAlloc(s)) break :blk true; break :blk false; },
        .for_stmt => |f| exprNeedsAlloc(f.iter.*) or blk: { for (f.body) |s| if (stmtNeedsAlloc(s)) break :blk true; break :blk false; },
        .try_stmt => |t| blk: { for (t.body) |s| if (stmtNeedsAlloc(s)) break :blk true; for (t.handlers) |h| for (h.body) |s| if (stmtNeedsAlloc(s)) break :blk true; break :blk false; },
        .class_def => |c| blk: { for (c.body) |s| if (stmtNeedsAlloc(s)) break :blk true; break :blk false; },
        .function_def => true, // Nested functions need allocator for closure
        .with_stmt => |w| exprNeedsAlloc(w.context_expr.*) or blk: { for (w.body) |s| if (stmtNeedsAlloc(s)) break :blk true; break :blk false; },
        else => false,
    };
}

fn exprNeedsAlloc(expr: ast.Node) bool {
    return switch (expr) {
        .binop => |b| (b.op == .Add and (mightBeStr(b.left.*) or mightBeStr(b.right.*))) or
            b.op == .Div or b.op == .FloorDiv or b.op == .Mod or exprNeedsAlloc(b.left.*) or exprNeedsAlloc(b.right.*),
        .call => |c| callNeedsAlloc(c),
        .fstring, .listcomp, .dictcomp, .dict => true,
        .list => |l| l.elts.len > 0 or blk: { for (l.elts) |e| if (exprNeedsAlloc(e)) break :blk true; break :blk false; },
        .tuple => |t| blk: { for (t.elts) |e| if (exprNeedsAlloc(e)) break :blk true; break :blk false; },
        .subscript => |s| exprNeedsAlloc(s.value.*) or switch (s.slice) { .index => |i| exprNeedsAlloc(i.*), .slice => |r| (if (r.lower) |l| exprNeedsAlloc(l.*) else false) or (if (r.upper) |u| exprNeedsAlloc(u.*) else false) },
        .attribute => |a| exprNeedsAlloc(a.value.*),
        .compare => |c| exprNeedsAlloc(c.left.*) or blk: { for (c.comparators) |x| if (exprNeedsAlloc(x)) break :blk true; break :blk false; },
        .boolop => |b| blk: { for (b.values) |v| if (exprNeedsAlloc(v)) break :blk true; break :blk false; },
        .unaryop => |u| exprNeedsAlloc(u.operand.*),
        else => false,
    };
}

fn callNeedsAlloc(call: ast.Node.Call) bool {
    for (call.args) |a| if (exprNeedsAlloc(a)) return true;
    if (call.func.* == .attribute) {
        const m = call.func.attribute.attr;
        if (AllocatorMethods.has(m) or GlobalAllocMethods.has(m)) return true;
        if (call.func.attribute.value.* == .call and exprNeedsAlloc(call.func.attribute.value.*)) return true;
        if (call.func.attribute.value.* == .name) {
            const obj = call.func.attribute.value.name.id;
            if (std.mem.eql(u8, obj, "self")) return true;
            if (ModuleAllocFuncs.has(m)) return true;
        }
    }
    if (call.func.* == .name and AllocBuiltins.has(call.func.name.id)) return true;
    return false;
}

fn mightBeStr(expr: ast.Node) bool {
    return switch (expr) {
        .constant => |c| c.value == .string,
        .fstring => true,
        .call => |c| (c.func.* == .name and (std.mem.eql(u8, c.func.name.id, "str") or std.mem.eql(u8, c.func.name.id, "input"))) or
            (c.func.* == .attribute and (std.mem.eql(u8, c.func.attribute.attr, "upper") or std.mem.eql(u8, c.func.attribute.attr, "lower"))),
        .binop => |b| b.op == .Add and (mightBeStr(b.left.*) or mightBeStr(b.right.*)),
        else => false,
    };
}

fn stmtUsesAllocParam(stmt: ast.Node, func_name: []const u8, nested: []const []const u8) bool {
    return switch (stmt) {
        .expr_stmt => |e| exprUsesAllocParam(e.value.*, func_name, nested),
        .assign => |a| exprUsesAllocParam(a.value.*, func_name, nested),
        .aug_assign => |a| exprUsesAllocParam(a.value.*, func_name, nested),
        .return_stmt => |r| if (r.value) |v| exprUsesAllocParam(v.*, func_name, nested) else false,
        .if_stmt => |i| exprUsesAllocParam(i.condition.*, func_name, nested) or blk: { for (i.body) |s| if (stmtUsesAllocParam(s, func_name, nested)) break :blk true; for (i.else_body) |s| if (stmtUsesAllocParam(s, func_name, nested)) break :blk true; break :blk false; },
        .while_stmt => |w| exprUsesAllocParam(w.condition.*, func_name, nested) or blk: { for (w.body) |s| if (stmtUsesAllocParam(s, func_name, nested)) break :blk true; break :blk false; },
        .for_stmt => |f| exprUsesAllocParam(f.iter.*, func_name, nested) or blk: { for (f.body) |s| if (stmtUsesAllocParam(s, func_name, nested)) break :blk true; break :blk false; },
        .try_stmt => |t| blk: { for (t.body) |s| if (stmtUsesAllocParam(s, func_name, nested)) break :blk true; for (t.handlers) |h| for (h.body) |s| if (stmtUsesAllocParam(s, func_name, nested)) break :blk true; break :blk false; },
        .class_def => |c| blk: { for (c.body) |s| if (stmtUsesAllocParam(s, func_name, nested)) break :blk true; break :blk false; },
        .with_stmt => |w| exprUsesAllocParam(w.context_expr.*, func_name, nested) or blk: { for (w.body) |s| if (stmtUsesAllocParam(s, func_name, nested)) break :blk true; break :blk false; },
        else => false,
    };
}

fn exprUsesAllocParam(expr: ast.Node, func_name: []const u8, nested: []const []const u8) bool {
    return switch (expr) {
        .binop => |b| exprUsesAllocParam(b.left.*, func_name, nested) or exprUsesAllocParam(b.right.*, func_name, nested),
        .call => |c| callUsesAllocParam(c, func_name, nested),
        .listcomp, .dictcomp => true,
        .list => |l| blk: { for (l.elts) |e| if (exprUsesAllocParam(e, func_name, nested)) break :blk true; break :blk false; },
        .tuple => |t| blk: { for (t.elts) |e| if (exprUsesAllocParam(e, func_name, nested)) break :blk true; break :blk false; },
        .subscript => |s| exprUsesAllocParam(s.value.*, func_name, nested) or switch (s.slice) { .index => |i| exprUsesAllocParam(i.*, func_name, nested), .slice => |r| (if (r.lower) |l| exprUsesAllocParam(l.*, func_name, nested) else false) or (if (r.upper) |u| exprUsesAllocParam(u.*, func_name, nested) else false) },
        .attribute => |a| exprUsesAllocParam(a.value.*, func_name, nested),
        .compare => |co| exprUsesAllocParam(co.left.*, func_name, nested) or blk: { for (co.comparators) |x| if (exprUsesAllocParam(x, func_name, nested)) break :blk true; break :blk false; },
        .boolop => |b| blk: { for (b.values) |v| if (exprUsesAllocParam(v, func_name, nested)) break :blk true; break :blk false; },
        .unaryop => |u| exprUsesAllocParam(u.operand.*, func_name, nested),
        .name => |n| std.mem.eql(u8, n.id, "allocator"),
        .if_expr => |ie| exprUsesAllocParam(ie.body.*, func_name, nested) or exprUsesAllocParam(ie.orelse_value.*, func_name, nested),
        else => false,
    };
}

fn callUsesAllocParam(call: ast.Node.Call, func_name: []const u8, nested: []const []const u8) bool {
    for (call.args) |a| if (exprUsesAllocParam(a, func_name, nested)) return true;
    if (call.func.* == .attribute) {
        if (AllocatorMethods.has(call.func.attribute.attr)) return true;
        if (call.func.attribute.value.* == .name) {
            const obj = call.func.attribute.value.name.id;
            if (ModuleAllocFuncs.has(call.func.attribute.attr) and !std.mem.eql(u8, obj, "self")) return true;
        }
    }
    if (call.func.* == .name) {
        const n = call.func.name.id;
        if (GlobalAllocBuiltins.has(n)) return false;
        if (std.mem.eql(u8, n, func_name)) return true; // Recursive call
        if (AllocBuiltins.has(n)) return true;
        if (AllocConstructors.has(n)) return true;
        for (nested) |c| if (std.mem.eql(u8, n, c)) return true;
    }
    return false;
}

// ============================================================================
// Tests
// ============================================================================

test "build call graph from simple function" {
    const allocator = std.testing.allocator;
    _ = allocator;
}
