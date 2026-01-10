//! Pass 2: Unified Analysis
//!
//! Consolidates all variable analysis into a single pass:
//! - Mutation tracking (const vs var decision)
//! - Variable hoisting detection (scope escape analysis)
//! - Branched variable tracking
//! - Closure capture analysis
//! - Declaration ordering (topological sort)
//!
//! This information is used in Pass 3 to:
//! - Emit `const` vs `var` declarations
//! - Hoist variables to function scope when needed
//! - Handle Python's function-scoped variables in Zig's block-scoped world
//! - Generate correct closure structs with captured variables
//! - Order declarations to avoid forward references

const std = @import("std");
const ir = @import("../ir.zig");
const hashmap_helper = @import("utils.hashmap_helper");

pub const ZigIR = ir.ZigIR;
pub const ZigIRExpr = ir.ZigIRExpr;

// ============================================================================
// Public Types
// ============================================================================

/// Source: what kind of block declared the escaped var
pub const HoistSource = enum {
    with_stmt,
    try_except,
    for_loop,
    if_stmt,
    while_loop,
};

/// Information about a hoisted variable
pub const HoistedInfo = struct {
    /// The scope depth where the variable should be declared (0 = function level)
    target_scope: usize = 0,
    /// The initial expression (for @TypeOf inference)
    init_expr: ?*const ZigIRExpr = null,
    /// Source: what kind of block declared this var
    source: HoistSource = .if_stmt,
    /// For for-loop: the iteration expression (for type derivation)
    iter_expr: ?*const ZigIRExpr = null,
    /// For for-loop tuple unpacking: the index in the tuple (0, 1, 2, ...)
    tuple_index: ?usize = null,
};

/// How a variable is captured by a closure
pub const CaptureType = enum {
    value, // Captured by value (immutable in closure)
    pointer, // Captured by pointer (mutable in closure)
    closure, // Variable is itself a closure
};

/// Information about a captured variable
pub const CaptureInfo = struct {
    /// Whether the captured variable is mutated in the closure
    is_mutated: bool = false,
    /// Whether marked as nonlocal (Python's nonlocal keyword)
    is_nonlocal: bool = false,
    /// How the variable should be captured
    capture_type: CaptureType = .value,
    /// Optional inferred type for the capture
    inferred_type: ?[]const u8 = null,
};

/// Information about a closure/nested function
pub const ClosureInfo = struct {
    /// List of captured variable names
    captures: []const []const u8,
    /// Whether closure references variables declared after it
    has_forward_refs: bool = false,
    /// Whether closure emission needs to be deferred
    needs_deferred: bool = false,
};

/// Per-function scope analysis (replaces func_local_* tracking)
pub const FunctionScope = struct {
    /// Variables assigned more than once within this function
    mutations: hashmap_helper.StringHashMap(void),
    /// Variables with augmented assignment (+=, -=, etc.)
    aug_assigns: hashmap_helper.StringHashMap(void),
    /// Variables that are read (for unused detection)
    uses: hashmap_helper.StringHashMap(void),
    /// Whether this method mutates self
    mutates_self: bool = false,

    allocator: std.mem.Allocator,

    pub fn init(allocator: std.mem.Allocator) FunctionScope {
        return .{
            .mutations = hashmap_helper.StringHashMap(void).init(allocator),
            .aug_assigns = hashmap_helper.StringHashMap(void).init(allocator),
            .uses = hashmap_helper.StringHashMap(void).init(allocator),
            .mutates_self = false,
            .allocator = allocator,
        };
    }

    pub fn deinit(self: *FunctionScope) void {
        self.mutations.deinit();
        self.aug_assigns.deinit();
        self.uses.deinit();
    }
};

/// Result of unified analysis
pub const AnalysisResult = struct {
    // === Mutation Analysis ===
    /// Variables that are assigned more than once (must be var)
    mutated_vars: hashmap_helper.StringHashMap(void),

    /// Variables assigned in conditional branches (if/while/for - must be var)
    branched_vars: hashmap_helper.StringHashMap(void),

    // === Hoisting Analysis ===
    /// Variables that need hoisting (assigned in inner scope, used in outer)
    hoisted_vars: hashmap_helper.StringHashMap(HoistedInfo),

    // === Capture Analysis ===
    /// Variables that are captured by closures
    captured_vars: hashmap_helper.StringHashMap(CaptureInfo),

    /// Functions that capture outer variables (closure info)
    closure_functions: hashmap_helper.StringHashMap(ClosureInfo),

    // === Declaration Ordering ===
    /// Topologically sorted declaration order (safe emission order)
    declaration_order: std.ArrayList([]const u8),

    // === Per-Function Scope Analysis ===
    /// Per-function tracking (replaces func_local_* in native codegen)
    function_scopes: hashmap_helper.StringHashMap(FunctionScope),

    allocator: std.mem.Allocator,

    pub fn init(allocator: std.mem.Allocator) AnalysisResult {
        return .{
            .mutated_vars = hashmap_helper.StringHashMap(void).init(allocator),
            .branched_vars = hashmap_helper.StringHashMap(void).init(allocator),
            .hoisted_vars = hashmap_helper.StringHashMap(HoistedInfo).init(allocator),
            .captured_vars = hashmap_helper.StringHashMap(CaptureInfo).init(allocator),
            .closure_functions = hashmap_helper.StringHashMap(ClosureInfo).init(allocator),
            .declaration_order = std.ArrayList([]const u8){},
            .function_scopes = hashmap_helper.StringHashMap(FunctionScope).init(allocator),
            .allocator = allocator,
        };
    }

    pub fn deinit(self: *AnalysisResult) void {
        self.mutated_vars.deinit();
        self.branched_vars.deinit();
        self.hoisted_vars.deinit();
        self.captured_vars.deinit();
        // Free capture slices in closure_functions
        var closure_iter = self.closure_functions.iterator();
        while (closure_iter.next()) |entry| {
            self.allocator.free(entry.value_ptr.captures);
        }
        self.closure_functions.deinit();
        self.declaration_order.deinit(self.allocator);
        // Free function scopes
        var scope_iter = self.function_scopes.iterator();
        while (scope_iter.next()) |entry| {
            entry.value_ptr.deinit();
        }
        self.function_scopes.deinit();
    }

    /// Returns true if the variable should be declared as const
    pub fn shouldBeConst(self: *const AnalysisResult, name: []const u8) bool {
        // If mutated, must be var
        if (self.mutated_vars.contains(name)) {
            return false;
        }
        // If assigned in conditional branches, must be var
        if (self.branched_vars.contains(name)) {
            return false;
        }
        // If hoisted, must be var (initialized with undefined)
        if (self.hoisted_vars.contains(name)) {
            return false;
        }
        // If captured and mutated, must be var
        if (self.captured_vars.get(name)) |cap| {
            if (cap.is_mutated or cap.is_nonlocal) {
                return false;
            }
        }
        // Otherwise, const is safe
        return true;
    }

    /// Returns true if the variable needs hoisting
    pub fn needsHoisting(self: *const AnalysisResult, name: []const u8) bool {
        return self.hoisted_vars.contains(name);
    }

    /// Get hoisting info for a variable
    pub fn getHoistInfo(self: *const AnalysisResult, name: []const u8) ?HoistedInfo {
        return self.hoisted_vars.get(name);
    }

    /// Get capture info for a variable
    pub fn getCaptureInfo(self: *const AnalysisResult, name: []const u8) ?CaptureInfo {
        return self.captured_vars.get(name);
    }

    /// Get closure info for a function
    pub fn getClosureInfo(self: *const AnalysisResult, func_name: []const u8) ?ClosureInfo {
        return self.closure_functions.get(func_name);
    }

    /// Returns true if a function is a closure (captures outer variables)
    pub fn isClosure(self: *const AnalysisResult, func_name: []const u8) bool {
        return self.closure_functions.contains(func_name);
    }

    /// Get declaration order for safe emission
    pub fn getDeclarationOrder(self: *const AnalysisResult) []const []const u8 {
        return self.declaration_order.items;
    }

    // === Per-Function Scope Query Methods ===

    /// Get function scope for a function name
    pub fn getFunctionScope(self: *const AnalysisResult, func_name: []const u8) ?*const FunctionScope {
        return self.function_scopes.getPtr(func_name);
    }

    /// Check if variable is mutated within a specific function
    pub fn isVarMutatedInFunction(self: *const AnalysisResult, func_name: []const u8, var_name: []const u8) bool {
        if (self.function_scopes.getPtr(func_name)) |scope| {
            return scope.mutations.contains(var_name);
        }
        // If function scope not found (e.g., class methods not in IR), assume not mutated
        // This is conservative - generates const, may need var if actually mutated
        return false;
    }

    /// Check if variable has augmented assignment within a specific function
    pub fn isVarAugAssignedInFunction(self: *const AnalysisResult, func_name: []const u8, var_name: []const u8) bool {
        if (self.function_scopes.getPtr(func_name)) |scope| {
            return scope.aug_assigns.contains(var_name);
        }
        return false;
    }

    /// Check if variable is unused within a specific function
    pub fn isVarUnusedInFunction(self: *const AnalysisResult, func_name: []const u8, var_name: []const u8) bool {
        if (self.function_scopes.getPtr(func_name)) |scope| {
            return !scope.uses.contains(var_name);
        }
        return false; // If no scope info, assume used (safe default)
    }

    /// Check if a method mutates self
    pub fn methodMutatesSelf(self: *const AnalysisResult, func_name: []const u8) bool {
        if (self.function_scopes.getPtr(func_name)) |scope| {
            return scope.mutates_self;
        }
        return false;
    }

    /// Check if variable should be const within a specific function
    pub fn shouldBeConstInFunction(self: *const AnalysisResult, func_name: []const u8, var_name: []const u8) bool {
        if (self.function_scopes.getPtr(func_name)) |scope| {
            // If mutated in function scope, must be var
            if (scope.mutations.contains(var_name)) return false;
            if (scope.aug_assigns.contains(var_name)) return false;
        }
        // Also check module-level analysis
        return self.shouldBeConst(var_name);
    }
};

// Backward compatibility alias
pub const MutationAnalysis = AnalysisResult;

// ============================================================================
// Internal Types
// ============================================================================

/// Track variable usage during analysis
const VarUsage = struct {
    /// Number of times the variable is assigned
    assignment_count: usize = 0,
    /// Scope depth of first assignment
    first_assignment_scope: usize = 0,
    /// Whether the variable is used before its first assignment
    used_before_assignment: bool = false,
    /// Scope depths where assignments occur
    assignment_scopes: std.ArrayList(usize),

    fn init(_: std.mem.Allocator) VarUsage {
        return .{
            .assignment_scopes = std.ArrayList(usize){},
        };
    }

    fn deinit(self: *VarUsage, allocator: std.mem.Allocator) void {
        self.assignment_scopes.deinit(allocator);
    }
};

/// Information about a variable declared in an inner scope
const InnerScopeDecl = struct {
    name: []const u8,
    init_expr: ?*const ZigIRExpr,
    source: HoistSource,
    iter_expr: ?*const ZigIRExpr = null,
    tuple_index: ?usize = null,
};

/// Context for the analysis walk
const AnalysisContext = struct {
    /// Current scope depth (0 = function level)
    scope_depth: usize = 0,
    /// Whether we're in a conditional branch
    in_branch: bool = false,
    /// Variable usage tracking
    var_usages: hashmap_helper.StringHashMap(VarUsage),
    /// Variables that have been seen (for detecting use before assignment)
    seen_vars: hashmap_helper.StringHashMap(void),
    /// Variables declared in inner scopes (for hoisting detection)
    inner_scope_decls: hashmap_helper.StringHashMap(InnerScopeDecl),
    /// Variables used at outer (function) level
    outer_uses: hashmap_helper.StringHashMap(void),
    /// Function-level assignments (for init_expr tracking)
    func_level_assigns: hashmap_helper.StringHashMap(*const ZigIRExpr),
    allocator: std.mem.Allocator,

    fn init(allocator: std.mem.Allocator) AnalysisContext {
        return .{
            .var_usages = hashmap_helper.StringHashMap(VarUsage).init(allocator),
            .seen_vars = hashmap_helper.StringHashMap(void).init(allocator),
            .inner_scope_decls = hashmap_helper.StringHashMap(InnerScopeDecl).init(allocator),
            .outer_uses = hashmap_helper.StringHashMap(void).init(allocator),
            .func_level_assigns = hashmap_helper.StringHashMap(*const ZigIRExpr).init(allocator),
            .allocator = allocator,
        };
    }

    fn deinit(self: *AnalysisContext) void {
        var iter = self.var_usages.iterator();
        while (iter.next()) |entry| {
            var usage = entry.value_ptr;
            usage.deinit(self.allocator);
        }
        self.var_usages.deinit();
        self.seen_vars.deinit();
        self.inner_scope_decls.deinit();
        self.outer_uses.deinit();
        self.func_level_assigns.deinit();
    }
};

// ============================================================================
// Main Analysis Entry Point
// ============================================================================

/// Analyze IR statements for mutations, hoisting, captures, and ordering
pub fn analyze(statements: []const ZigIR, allocator: std.mem.Allocator) !AnalysisResult {
    var result = AnalysisResult.init(allocator);
    errdefer result.deinit();

    var ctx = AnalysisContext.init(allocator);
    defer ctx.deinit();

    // Pre-pass: collect function-level assignments for init_expr tracking
    for (statements) |stmt| {
        try collectFuncLevelAssignments(stmt, &ctx);
    }

    // Pass 1: Collect variables declared in inner scopes
    for (statements) |stmt| {
        try collectInnerScopeDecls(stmt, &ctx, .if_stmt);
    }

    // Pass 2: Collect variable uses at outer level
    for (statements) |stmt| {
        try collectOuterUses(stmt, &ctx);
    }

    // Pass 3: Analyze mutations and branching
    for (statements) |stmt| {
        try analyzeStmt(stmt, &ctx);
    }

    // Pass 4: Detect cross-scope escapes (vars declared inner, used outer)
    try detectScopeEscapes(&ctx, &result);

    // Pass 5: Capture analysis - find closures and their captured variables
    try analyzeCaptures(statements, &ctx, &result, allocator);

    // Pass 6: Declaration ordering - topological sort for safe emission
    try computeDeclarationOrder(statements, &ctx, &result, allocator);

    // Pass 7: Per-function scope analysis (replaces func_local_* tracking)
    for (statements) |stmt| {
        try analyzeFunctionScope(stmt, &result, allocator);
    }

    // Convert mutation usage data to result flags
    var iter = ctx.var_usages.iterator();
    while (iter.next()) |entry| {
        const var_name = entry.key_ptr.*;
        const usage = entry.value_ptr.*;

        // Multiple assignments = mutation
        if (usage.assignment_count > 1) {
            try result.mutated_vars.put(var_name, {});
        }

        // Used before assignment = mutation (needs initial value)
        if (usage.used_before_assignment) {
            try result.mutated_vars.put(var_name, {});
        }

        // Assignment in multiple scopes = needs hoisting
        if (usage.assignment_scopes.items.len > 1) {
            var min_scope: usize = std.math.maxInt(usize);
            for (usage.assignment_scopes.items) |scope| {
                min_scope = @min(min_scope, scope);
            }
            if (min_scope > 0 and !result.hoisted_vars.contains(var_name)) {
                try result.hoisted_vars.put(var_name, .{
                    .target_scope = 0,
                    .init_expr = null,
                    .source = .if_stmt,
                });
            }
        }
    }

    return result;
}

// ============================================================================
// Pre-pass: Function-level Assignment Collection
// ============================================================================

/// Collect function-level assignments (for init_expr tracking)
fn collectFuncLevelAssignments(stmt: ZigIR, ctx: *AnalysisContext) !void {
    switch (stmt) {
        .var_decl => |vd| {
            if (!ctx.func_level_assigns.contains(vd.name)) {
                try ctx.func_level_assigns.put(vd.name, vd.init);
            }
        },
        .const_decl => |cd| {
            if (!ctx.func_level_assigns.contains(cd.name)) {
                try ctx.func_level_assigns.put(cd.name, cd.init);
            }
        },
        .assign => |a| {
            if (a.target.* == .name) {
                const var_name = a.target.name;
                if (!ctx.func_level_assigns.contains(var_name)) {
                    try ctx.func_level_assigns.put(var_name, a.value);
                }
            }
        },
        // Don't recurse into nested scopes - we only want function-level
        else => {},
    }
}

// ============================================================================
// Pass 1: Inner Scope Declaration Collection
// ============================================================================

/// Collect variables declared inside inner scopes
fn collectInnerScopeDecls(stmt: ZigIR, ctx: *AnalysisContext, source: HoistSource) !void {
    switch (stmt) {
        .if_stmt => |i| {
            // Collect from then body
            for (i.then_body) |s| {
                try collectAssignmentDecl(s, ctx, .if_stmt);
                try collectInnerScopeDecls(s, ctx, .if_stmt);
            }
            // Collect from else-ifs
            for (i.else_ifs) |elif| {
                for (elif.body) |s| {
                    try collectAssignmentDecl(s, ctx, .if_stmt);
                    try collectInnerScopeDecls(s, ctx, .if_stmt);
                }
            }
            // Collect from else body
            if (i.else_body) |eb| {
                for (eb) |s| {
                    try collectAssignmentDecl(s, ctx, .if_stmt);
                    try collectInnerScopeDecls(s, ctx, .if_stmt);
                }
            }
        },
        .while_loop => |w| {
            for (w.body) |s| {
                try collectAssignmentDecl(s, ctx, .while_loop);
                try collectInnerScopeDecls(s, ctx, .while_loop);
            }
        },
        .for_loop => |f| {
            // Loop variable itself needs hoisting
            try ctx.inner_scope_decls.put(f.target, .{
                .name = f.target,
                .init_expr = null,
                .source = .for_loop,
                .iter_expr = f.iter,
                .tuple_index = null,
            });

            // Collect from body
            for (f.body) |s| {
                try collectAssignmentDecl(s, ctx, .for_loop);
                try collectInnerScopeDecls(s, ctx, .for_loop);
            }
        },
        .inline_for => |f| {
            try ctx.inner_scope_decls.put(f.target, .{
                .name = f.target,
                .init_expr = null,
                .source = .for_loop,
                .iter_expr = f.iter,
                .tuple_index = null,
            });

            for (f.body) |s| {
                try collectAssignmentDecl(s, ctx, .for_loop);
                try collectInnerScopeDecls(s, ctx, .for_loop);
            }
        },
        .block => |b| {
            for (b.body) |s| {
                try collectAssignmentDecl(s, ctx, source);
                try collectInnerScopeDecls(s, ctx, source);
            }
        },
        // Other statements don't introduce new scopes
        else => {},
    }
}

/// Collect assignment declarations from a statement
fn collectAssignmentDecl(stmt: ZigIR, ctx: *AnalysisContext, source: HoistSource) !void {
    switch (stmt) {
        .var_decl => |vd| {
            if (!ctx.inner_scope_decls.contains(vd.name)) {
                try ctx.inner_scope_decls.put(vd.name, .{
                    .name = vd.name,
                    .init_expr = vd.init,
                    .source = source,
                });
            }
        },
        .const_decl => |cd| {
            if (!ctx.inner_scope_decls.contains(cd.name)) {
                try ctx.inner_scope_decls.put(cd.name, .{
                    .name = cd.name,
                    .init_expr = cd.init,
                    .source = source,
                });
            }
        },
        .assign => |a| {
            if (a.target.* == .name) {
                const var_name = a.target.name;
                if (!ctx.inner_scope_decls.contains(var_name)) {
                    try ctx.inner_scope_decls.put(var_name, .{
                        .name = var_name,
                        .init_expr = a.value,
                        .source = source,
                    });
                }
            }
        },
        else => {},
    }
}

// ============================================================================
// Pass 2: Outer Scope Use Collection
// ============================================================================

/// Collect variable uses at outer (function) level
fn collectOuterUses(stmt: ZigIR, ctx: *AnalysisContext) !void {
    switch (stmt) {
        // Skip inner scopes - we only want outer-level uses
        .if_stmt, .while_loop, .for_loop, .inline_for, .block => {},

        // For statements at outer level, collect variable references
        .var_decl => |vd| {
            try collectExprUses(vd.init, ctx);
        },
        .const_decl => |cd| {
            try collectExprUses(cd.init, ctx);
        },
        .assign => |a| {
            try collectExprUses(a.value, ctx);
            // Also check target if it's not a simple name (subscript, etc.)
            if (a.target.* != .name) {
                try collectExprUses(a.target, ctx);
            }
        },
        .aug_assign => |aa| {
            try collectExprUses(aa.value, ctx);
            try collectExprUses(aa.target, ctx);
        },
        .return_ => |r| {
            if (r.value) |v| {
                try collectExprUses(v, ctx);
            }
        },
        .expr_stmt => |e| {
            try collectExprUses(e.expr, ctx);
        },
        .defer_ => |d| {
            try collectExprUses(d.expr, ctx);
        },
        .errdefer_ => |e| {
            try collectExprUses(e.expr, ctx);
        },
        .discard => |d| {
            try collectExprUses(d.expr, ctx);
        },
        else => {},
    }
}

/// Collect variable references from an expression
fn collectExprUses(expr: *const ZigIRExpr, ctx: *AnalysisContext) !void {
    switch (expr.*) {
        .name => |name| {
            try ctx.outer_uses.put(name, {});
        },
        .field_access => |fa| {
            try collectExprUses(fa.object, ctx);
        },
        .subscript => |s| {
            try collectExprUses(s.object, ctx);
            try collectExprUses(s.index, ctx);
        },
        .slice => |s| {
            try collectExprUses(s.object, ctx);
            if (s.start) |start| try collectExprUses(start, ctx);
            if (s.end) |end| try collectExprUses(end, ctx);
        },
        .call => |c| {
            try collectExprUses(c.func, ctx);
            for (c.args) |arg| {
                try collectExprUses(arg, ctx);
            }
        },
        .binop => |b| {
            try collectExprUses(b.left, ctx);
            try collectExprUses(b.right, ctx);
        },
        .unaryop => |u| {
            try collectExprUses(u.operand, ctx);
        },
        .boolop => |bo| {
            for (bo.operands) |op| {
                try collectExprUses(op, ctx);
            }
        },
        .ternary => |t| {
            try collectExprUses(t.condition, ctx);
            try collectExprUses(t.then_expr, ctx);
            try collectExprUses(t.else_expr, ctx);
        },
        .array => |a| {
            for (a.elements) |elem| {
                try collectExprUses(elem, ctx);
            }
        },
        .tuple => |t| {
            for (t.elements) |elem| {
                try collectExprUses(elem, ctx);
            }
        },
        .struct_init => |si| {
            for (si.fields) |field| {
                try collectExprUses(field.value, ctx);
            }
        },
        .cast => |c| {
            try collectExprUses(c.value, ctx);
        },
        .builtin => |b| {
            for (b.args) |arg| {
                try collectExprUses(arg, ctx);
            }
        },
        .try_ => |t| {
            try collectExprUses(t.expr, ctx);
        },
        .catch_ => |c| {
            try collectExprUses(c.expr, ctx);
            try collectExprUses(c.handler, ctx);
        },
        .orelse_ => |o| {
            try collectExprUses(o.expr, ctx);
            try collectExprUses(o.default, ctx);
        },
        .address_of => |a| {
            try collectExprUses(a.expr, ctx);
        },
        .deref => |d| {
            try collectExprUses(d.expr, ctx);
        },
        // Literals don't reference variables
        .int, .float, .bool_, .string, .null_, .undefined, .raw => {},
    }
}

// ============================================================================
// Pass 3: Mutation Analysis
// ============================================================================

/// Analyze a single statement for mutations
fn analyzeStmt(stmt: ZigIR, ctx: *AnalysisContext) !void {
    switch (stmt) {
        .const_decl => |cd| {
            try recordAssignment(cd.name, ctx);
            try analyzeExpr(cd.init, ctx);
        },
        .var_decl => |vd| {
            try recordAssignment(vd.name, ctx);
            try analyzeExpr(vd.init, ctx);
        },
        .assign => |a| {
            // Analyze RHS first (before recording assignment)
            try analyzeExpr(a.value, ctx);
            // Record assignment for target
            if (a.target.* == .name) {
                try recordAssignment(a.target.name, ctx);
            } else {
                try analyzeExpr(a.target, ctx);
            }
        },
        .aug_assign => |aa| {
            try analyzeExpr(aa.value, ctx);
            if (aa.target.* == .name) {
                try recordAssignment(aa.target.name, ctx);
            } else {
                try analyzeExpr(aa.target, ctx);
            }
        },
        .if_stmt => |i| {
            try analyzeExpr(i.condition, ctx);

            // Enter branch scope
            const was_in_branch = ctx.in_branch;
            ctx.in_branch = true;
            ctx.scope_depth += 1;

            for (i.then_body) |s| {
                try analyzeStmt(s, ctx);
            }

            for (i.else_ifs) |elif| {
                try analyzeExpr(elif.condition, ctx);
                for (elif.body) |s| {
                    try analyzeStmt(s, ctx);
                }
            }

            if (i.else_body) |eb| {
                for (eb) |s| {
                    try analyzeStmt(s, ctx);
                }
            }

            ctx.scope_depth -= 1;
            ctx.in_branch = was_in_branch;
        },
        .while_loop => |w| {
            try analyzeExpr(w.condition, ctx);

            const was_in_branch = ctx.in_branch;
            ctx.in_branch = true;
            ctx.scope_depth += 1;

            for (w.body) |s| {
                try analyzeStmt(s, ctx);
            }

            ctx.scope_depth -= 1;
            ctx.in_branch = was_in_branch;
        },
        .for_loop => |f| {
            try analyzeExpr(f.iter, ctx);

            ctx.scope_depth += 1;
            // Loop variable is assigned each iteration
            try recordAssignment(f.target, ctx);

            for (f.body) |s| {
                try analyzeStmt(s, ctx);
            }

            ctx.scope_depth -= 1;
        },
        .inline_for => |f| {
            try analyzeExpr(f.iter, ctx);

            ctx.scope_depth += 1;
            try recordAssignment(f.target, ctx);

            for (f.body) |s| {
                try analyzeStmt(s, ctx);
            }

            ctx.scope_depth -= 1;
        },
        .function => |func| {
            // Function body is a new scope
            ctx.scope_depth += 1;

            // Parameters are assignments
            for (func.params) |param| {
                try recordAssignment(param.name, ctx);
            }

            for (func.body) |s| {
                try analyzeStmt(s, ctx);
            }

            ctx.scope_depth -= 1;
        },
        .return_ => |r| {
            if (r.value) |v| {
                try analyzeExpr(v, ctx);
            }
        },
        .expr_stmt => |e| {
            try analyzeExpr(e.expr, ctx);
        },
        .block => |b| {
            ctx.scope_depth += 1;
            for (b.body) |s| {
                try analyzeStmt(s, ctx);
            }
            ctx.scope_depth -= 1;
        },
        .defer_ => |d| {
            try analyzeExpr(d.expr, ctx);
        },
        .errdefer_ => |e| {
            try analyzeExpr(e.expr, ctx);
        },
        .discard => |d| {
            try analyzeExpr(d.expr, ctx);
        },
        // Statements that don't affect mutation analysis
        .break_, .continue_, .comment, .blank, .raw, .var_undef => {},
    }
}

/// Analyze an expression for variable uses
fn analyzeExpr(expr: *const ZigIRExpr, ctx: *AnalysisContext) !void {
    switch (expr.*) {
        .name => |name| {
            // Record that we've seen this variable
            try recordUse(name, ctx);
        },
        .field_access => |fa| {
            try analyzeExpr(fa.object, ctx);
        },
        .subscript => |s| {
            try analyzeExpr(s.object, ctx);
            try analyzeExpr(s.index, ctx);
        },
        .slice => |s| {
            try analyzeExpr(s.object, ctx);
            if (s.start) |start| try analyzeExpr(start, ctx);
            if (s.end) |end| try analyzeExpr(end, ctx);
        },
        .call => |c| {
            try analyzeExpr(c.func, ctx);
            for (c.args) |arg| {
                try analyzeExpr(arg, ctx);
            }
        },
        .binop => |b| {
            try analyzeExpr(b.left, ctx);
            try analyzeExpr(b.right, ctx);
        },
        .unaryop => |u| {
            try analyzeExpr(u.operand, ctx);
        },
        .boolop => |bo| {
            for (bo.operands) |op| {
                try analyzeExpr(op, ctx);
            }
        },
        .ternary => |t| {
            try analyzeExpr(t.condition, ctx);
            try analyzeExpr(t.then_expr, ctx);
            try analyzeExpr(t.else_expr, ctx);
        },
        .array => |a| {
            for (a.elements) |elem| {
                try analyzeExpr(elem, ctx);
            }
        },
        .tuple => |t| {
            for (t.elements) |elem| {
                try analyzeExpr(elem, ctx);
            }
        },
        .struct_init => |si| {
            for (si.fields) |field| {
                try analyzeExpr(field.value, ctx);
            }
        },
        .cast => |c| {
            try analyzeExpr(c.value, ctx);
        },
        .builtin => |b| {
            for (b.args) |arg| {
                try analyzeExpr(arg, ctx);
            }
        },
        .try_ => |t| {
            try analyzeExpr(t.expr, ctx);
        },
        .catch_ => |c| {
            try analyzeExpr(c.expr, ctx);
            try analyzeExpr(c.handler, ctx);
        },
        .orelse_ => |o| {
            try analyzeExpr(o.expr, ctx);
            try analyzeExpr(o.default, ctx);
        },
        .address_of => |a| {
            try analyzeExpr(a.expr, ctx);
        },
        .deref => |d| {
            try analyzeExpr(d.expr, ctx);
        },
        // Literals don't reference variables
        .int, .float, .bool_, .string, .null_, .undefined, .raw => {},
    }
}

/// Record that a variable was assigned
fn recordAssignment(name: []const u8, ctx: *AnalysisContext) !void {
    if (ctx.var_usages.getPtr(name)) |usage| {
        usage.assignment_count += 1;
        try usage.assignment_scopes.append(ctx.allocator, ctx.scope_depth);
    } else {
        var usage = VarUsage.init(ctx.allocator);
        usage.assignment_count = 1;
        usage.first_assignment_scope = ctx.scope_depth;
        try usage.assignment_scopes.append(ctx.allocator, ctx.scope_depth);
        // Check if used before this first assignment
        if (ctx.seen_vars.contains(name)) {
            usage.used_before_assignment = true;
        }
        try ctx.var_usages.put(name, usage);
    }
}

/// Record that a variable was used (read)
fn recordUse(name: []const u8, ctx: *AnalysisContext) !void {
    try ctx.seen_vars.put(name, {});
}

// ============================================================================
// Pass 4: Scope Escape Detection
// ============================================================================

/// Detect variables that escape their declaring scope
fn detectScopeEscapes(ctx: *AnalysisContext, result: *AnalysisResult) !void {
    // Find variables declared in inner scopes but used at outer level
    var iter = ctx.inner_scope_decls.iterator();
    while (iter.next()) |entry| {
        const var_name = entry.key_ptr.*;
        const decl = entry.value_ptr.*;

        // Check if this variable is used at outer level
        if (ctx.outer_uses.contains(var_name)) {
            // Variable escapes! Add to hoisted_vars
            // Use function-level init_expr if available
            const init_expr = ctx.func_level_assigns.get(var_name) orelse decl.init_expr;

            try result.hoisted_vars.put(var_name, .{
                .target_scope = 0,
                .init_expr = init_expr,
                .source = decl.source,
                .iter_expr = decl.iter_expr,
                .tuple_index = decl.tuple_index,
            });
        }
    }
}

// ============================================================================
// Pass 5: Capture Analysis
// ============================================================================

/// Context for capture analysis within a function
const CaptureContext = struct {
    /// Outer scope variables (parameters + local vars)
    outer_vars: hashmap_helper.StringHashMap(void),
    /// Variables referenced in nested functions
    nested_refs: hashmap_helper.StringHashMap(void),
    /// Variables mutated in nested functions
    nested_mutations: hashmap_helper.StringHashMap(void),
    allocator: std.mem.Allocator,

    fn init(allocator: std.mem.Allocator) CaptureContext {
        return .{
            .outer_vars = hashmap_helper.StringHashMap(void).init(allocator),
            .nested_refs = hashmap_helper.StringHashMap(void).init(allocator),
            .nested_mutations = hashmap_helper.StringHashMap(void).init(allocator),
            .allocator = allocator,
        };
    }

    fn deinit(self: *CaptureContext) void {
        self.outer_vars.deinit();
        self.nested_refs.deinit();
        self.nested_mutations.deinit();
    }
};

/// Analyze captures for closures in the IR
fn analyzeCaptures(
    statements: []const ZigIR,
    ctx: *AnalysisContext,
    result: *AnalysisResult,
    allocator: std.mem.Allocator,
) !void {
    _ = ctx; // May be used for cross-referencing

    // For each function in the IR, find nested functions and their captures
    for (statements) |stmt| {
        try analyzeCapturesInStmt(stmt, result, allocator);
    }
}

/// Analyze captures in a single statement
fn analyzeCapturesInStmt(
    stmt: ZigIR,
    result: *AnalysisResult,
    allocator: std.mem.Allocator,
) !void {
    switch (stmt) {
        .function => |func| {
            // Create capture context for this function
            var cap_ctx = CaptureContext.init(allocator);
            defer cap_ctx.deinit();

            // Collect outer scope variables (parameters)
            for (func.params) |param| {
                try cap_ctx.outer_vars.put(param.name, {});
            }

            // Collect local variable declarations from body
            for (func.body) |body_stmt| {
                try collectLocalVarsFromStmt(body_stmt, &cap_ctx);
            }

            // Find nested functions and analyze their captures
            for (func.body) |body_stmt| {
                try findNestedFunctionCaptures(body_stmt, &cap_ctx, result, allocator);
            }
        },
        .if_stmt => |i| {
            for (i.then_body) |s| {
                try analyzeCapturesInStmt(s, result, allocator);
            }
            for (i.else_ifs) |elif| {
                for (elif.body) |s| {
                    try analyzeCapturesInStmt(s, result, allocator);
                }
            }
            if (i.else_body) |eb| {
                for (eb) |s| {
                    try analyzeCapturesInStmt(s, result, allocator);
                }
            }
        },
        .while_loop => |w| {
            for (w.body) |s| {
                try analyzeCapturesInStmt(s, result, allocator);
            }
        },
        .for_loop => |f| {
            for (f.body) |s| {
                try analyzeCapturesInStmt(s, result, allocator);
            }
        },
        .inline_for => |f| {
            for (f.body) |s| {
                try analyzeCapturesInStmt(s, result, allocator);
            }
        },
        .block => |b| {
            for (b.body) |s| {
                try analyzeCapturesInStmt(s, result, allocator);
            }
        },
        else => {},
    }
}

/// Collect local variables from a statement
fn collectLocalVarsFromStmt(stmt: ZigIR, cap_ctx: *CaptureContext) !void {
    switch (stmt) {
        .var_decl => |vd| {
            try cap_ctx.outer_vars.put(vd.name, {});
        },
        .const_decl => |cd| {
            try cap_ctx.outer_vars.put(cd.name, {});
        },
        .assign => |a| {
            if (a.target.* == .name) {
                try cap_ctx.outer_vars.put(a.target.name, {});
            }
        },
        .for_loop => |f| {
            try cap_ctx.outer_vars.put(f.target, {});
            for (f.body) |s| {
                try collectLocalVarsFromStmt(s, cap_ctx);
            }
        },
        .inline_for => |f| {
            try cap_ctx.outer_vars.put(f.target, {});
            for (f.body) |s| {
                try collectLocalVarsFromStmt(s, cap_ctx);
            }
        },
        .if_stmt => |i| {
            for (i.then_body) |s| {
                try collectLocalVarsFromStmt(s, cap_ctx);
            }
            for (i.else_ifs) |elif| {
                for (elif.body) |s| {
                    try collectLocalVarsFromStmt(s, cap_ctx);
                }
            }
            if (i.else_body) |eb| {
                for (eb) |s| {
                    try collectLocalVarsFromStmt(s, cap_ctx);
                }
            }
        },
        .while_loop => |w| {
            for (w.body) |s| {
                try collectLocalVarsFromStmt(s, cap_ctx);
            }
        },
        .block => |b| {
            for (b.body) |s| {
                try collectLocalVarsFromStmt(s, cap_ctx);
            }
        },
        else => {},
    }
}

/// Find nested functions and their captured variables
fn findNestedFunctionCaptures(
    stmt: ZigIR,
    cap_ctx: *CaptureContext,
    result: *AnalysisResult,
    allocator: std.mem.Allocator,
) !void {
    switch (stmt) {
        .function => |nested_func| {
            // This is a nested function - analyze what it captures
            var captures = std.ArrayList([]const u8){};

            // Collect parameter names of nested function (these are NOT captures)
            var nested_params = hashmap_helper.StringHashMap(void).init(allocator);
            defer nested_params.deinit();
            for (nested_func.params) |param| {
                try nested_params.put(param.name, {});
            }

            // Find references to outer scope variables in nested function body
            for (nested_func.body) |body_stmt| {
                try findOuterRefsInStmt(body_stmt, cap_ctx, &nested_params, &captures, result, allocator);
            }

            // If there are captures, record this as a closure
            if (captures.items.len > 0) {
                const captures_slice = try captures.toOwnedSlice(allocator);

                // Mark each captured variable
                for (captures_slice) |cap_name| {
                    if (!result.captured_vars.contains(cap_name)) {
                        try result.captured_vars.put(cap_name, .{
                            .is_mutated = cap_ctx.nested_mutations.contains(cap_name),
                            .capture_type = if (cap_ctx.nested_mutations.contains(cap_name)) .pointer else .value,
                        });
                    }
                }

                // Record the closure
                try result.closure_functions.put(nested_func.name, .{
                    .captures = captures_slice,
                    .has_forward_refs = false, // TODO: detect forward refs
                    .needs_deferred = false,
                });
            } else {
                captures.deinit(allocator);
            }
        },
        .if_stmt => |i| {
            for (i.then_body) |s| {
                try findNestedFunctionCaptures(s, cap_ctx, result, allocator);
            }
            for (i.else_ifs) |elif| {
                for (elif.body) |s| {
                    try findNestedFunctionCaptures(s, cap_ctx, result, allocator);
                }
            }
            if (i.else_body) |eb| {
                for (eb) |s| {
                    try findNestedFunctionCaptures(s, cap_ctx, result, allocator);
                }
            }
        },
        .while_loop => |w| {
            for (w.body) |s| {
                try findNestedFunctionCaptures(s, cap_ctx, result, allocator);
            }
        },
        .for_loop => |f| {
            for (f.body) |s| {
                try findNestedFunctionCaptures(s, cap_ctx, result, allocator);
            }
        },
        .inline_for => |f| {
            for (f.body) |s| {
                try findNestedFunctionCaptures(s, cap_ctx, result, allocator);
            }
        },
        .block => |b| {
            for (b.body) |s| {
                try findNestedFunctionCaptures(s, cap_ctx, result, allocator);
            }
        },
        else => {},
    }
}

/// Find references to outer scope variables in a statement
fn findOuterRefsInStmt(
    stmt: ZigIR,
    cap_ctx: *CaptureContext,
    nested_params: *hashmap_helper.StringHashMap(void),
    captures: *std.ArrayList([]const u8),
    result: *AnalysisResult,
    allocator: std.mem.Allocator,
) !void {
    switch (stmt) {
        .var_decl => |vd| {
            // Add to nested function's locals
            try nested_params.put(vd.name, {});
            try findOuterRefsInExpr(vd.init, cap_ctx, nested_params, captures, allocator);
        },
        .const_decl => |cd| {
            try nested_params.put(cd.name, {});
            try findOuterRefsInExpr(cd.init, cap_ctx, nested_params, captures, allocator);
        },
        .assign => |a| {
            try findOuterRefsInExpr(a.value, cap_ctx, nested_params, captures, allocator);
            if (a.target.* == .name) {
                const var_name = a.target.name;
                // If assigning to an outer var, mark it as mutated
                if (cap_ctx.outer_vars.contains(var_name) and !nested_params.contains(var_name)) {
                    try cap_ctx.nested_mutations.put(var_name, {});
                    try addCapture(var_name, captures, allocator);
                }
            } else {
                try findOuterRefsInExpr(a.target, cap_ctx, nested_params, captures, allocator);
            }
        },
        .aug_assign => |aa| {
            try findOuterRefsInExpr(aa.value, cap_ctx, nested_params, captures, allocator);
            if (aa.target.* == .name) {
                const var_name = aa.target.name;
                if (cap_ctx.outer_vars.contains(var_name) and !nested_params.contains(var_name)) {
                    try cap_ctx.nested_mutations.put(var_name, {});
                    try addCapture(var_name, captures, allocator);
                }
            } else {
                try findOuterRefsInExpr(aa.target, cap_ctx, nested_params, captures, allocator);
            }
        },
        .return_ => |r| {
            if (r.value) |v| {
                try findOuterRefsInExpr(v, cap_ctx, nested_params, captures, allocator);
            }
        },
        .expr_stmt => |e| {
            try findOuterRefsInExpr(e.expr, cap_ctx, nested_params, captures, allocator);
        },
        .if_stmt => |i| {
            try findOuterRefsInExpr(i.condition, cap_ctx, nested_params, captures, allocator);
            for (i.then_body) |s| {
                try findOuterRefsInStmt(s, cap_ctx, nested_params, captures, result, allocator);
            }
            for (i.else_ifs) |elif| {
                try findOuterRefsInExpr(elif.condition, cap_ctx, nested_params, captures, allocator);
                for (elif.body) |s| {
                    try findOuterRefsInStmt(s, cap_ctx, nested_params, captures, result, allocator);
                }
            }
            if (i.else_body) |eb| {
                for (eb) |s| {
                    try findOuterRefsInStmt(s, cap_ctx, nested_params, captures, result, allocator);
                }
            }
        },
        .while_loop => |w| {
            try findOuterRefsInExpr(w.condition, cap_ctx, nested_params, captures, allocator);
            for (w.body) |s| {
                try findOuterRefsInStmt(s, cap_ctx, nested_params, captures, result, allocator);
            }
        },
        .for_loop => |f| {
            try nested_params.put(f.target, {});
            try findOuterRefsInExpr(f.iter, cap_ctx, nested_params, captures, allocator);
            for (f.body) |s| {
                try findOuterRefsInStmt(s, cap_ctx, nested_params, captures, result, allocator);
            }
        },
        .inline_for => |f| {
            try nested_params.put(f.target, {});
            try findOuterRefsInExpr(f.iter, cap_ctx, nested_params, captures, allocator);
            for (f.body) |s| {
                try findOuterRefsInStmt(s, cap_ctx, nested_params, captures, result, allocator);
            }
        },
        .block => |b| {
            for (b.body) |s| {
                try findOuterRefsInStmt(s, cap_ctx, nested_params, captures, result, allocator);
            }
        },
        .defer_ => |d| {
            try findOuterRefsInExpr(d.expr, cap_ctx, nested_params, captures, allocator);
        },
        .errdefer_ => |e| {
            try findOuterRefsInExpr(e.expr, cap_ctx, nested_params, captures, allocator);
        },
        .discard => |d| {
            try findOuterRefsInExpr(d.expr, cap_ctx, nested_params, captures, allocator);
        },
        else => {},
    }
}

/// Find references to outer scope variables in an expression
fn findOuterRefsInExpr(
    expr: *const ZigIRExpr,
    cap_ctx: *CaptureContext,
    nested_params: *hashmap_helper.StringHashMap(void),
    captures: *std.ArrayList([]const u8),
    allocator: std.mem.Allocator,
) !void {
    switch (expr.*) {
        .name => |name| {
            // Check if this is an outer scope variable (not a nested param)
            if (cap_ctx.outer_vars.contains(name) and !nested_params.contains(name)) {
                try addCapture(name, captures, allocator);
            }
        },
        .field_access => |fa| {
            try findOuterRefsInExpr(fa.object, cap_ctx, nested_params, captures, allocator);
        },
        .subscript => |s| {
            try findOuterRefsInExpr(s.object, cap_ctx, nested_params, captures, allocator);
            try findOuterRefsInExpr(s.index, cap_ctx, nested_params, captures, allocator);
        },
        .slice => |s| {
            try findOuterRefsInExpr(s.object, cap_ctx, nested_params, captures, allocator);
            if (s.start) |start| try findOuterRefsInExpr(start, cap_ctx, nested_params, captures, allocator);
            if (s.end) |end| try findOuterRefsInExpr(end, cap_ctx, nested_params, captures, allocator);
        },
        .call => |c| {
            try findOuterRefsInExpr(c.func, cap_ctx, nested_params, captures, allocator);
            for (c.args) |arg| {
                try findOuterRefsInExpr(arg, cap_ctx, nested_params, captures, allocator);
            }
        },
        .binop => |b| {
            try findOuterRefsInExpr(b.left, cap_ctx, nested_params, captures, allocator);
            try findOuterRefsInExpr(b.right, cap_ctx, nested_params, captures, allocator);
        },
        .unaryop => |u| {
            try findOuterRefsInExpr(u.operand, cap_ctx, nested_params, captures, allocator);
        },
        .boolop => |bo| {
            for (bo.operands) |op| {
                try findOuterRefsInExpr(op, cap_ctx, nested_params, captures, allocator);
            }
        },
        .ternary => |t| {
            try findOuterRefsInExpr(t.condition, cap_ctx, nested_params, captures, allocator);
            try findOuterRefsInExpr(t.then_expr, cap_ctx, nested_params, captures, allocator);
            try findOuterRefsInExpr(t.else_expr, cap_ctx, nested_params, captures, allocator);
        },
        .array => |a| {
            for (a.elements) |elem| {
                try findOuterRefsInExpr(elem, cap_ctx, nested_params, captures, allocator);
            }
        },
        .tuple => |t| {
            for (t.elements) |elem| {
                try findOuterRefsInExpr(elem, cap_ctx, nested_params, captures, allocator);
            }
        },
        .struct_init => |si| {
            for (si.fields) |field| {
                try findOuterRefsInExpr(field.value, cap_ctx, nested_params, captures, allocator);
            }
        },
        .cast => |c| {
            try findOuterRefsInExpr(c.value, cap_ctx, nested_params, captures, allocator);
        },
        .builtin => |b| {
            for (b.args) |arg| {
                try findOuterRefsInExpr(arg, cap_ctx, nested_params, captures, allocator);
            }
        },
        .try_ => |t| {
            try findOuterRefsInExpr(t.expr, cap_ctx, nested_params, captures, allocator);
        },
        .catch_ => |c| {
            try findOuterRefsInExpr(c.expr, cap_ctx, nested_params, captures, allocator);
            try findOuterRefsInExpr(c.handler, cap_ctx, nested_params, captures, allocator);
        },
        .orelse_ => |o| {
            try findOuterRefsInExpr(o.expr, cap_ctx, nested_params, captures, allocator);
            try findOuterRefsInExpr(o.default, cap_ctx, nested_params, captures, allocator);
        },
        .address_of => |a| {
            try findOuterRefsInExpr(a.expr, cap_ctx, nested_params, captures, allocator);
        },
        .deref => |d| {
            try findOuterRefsInExpr(d.expr, cap_ctx, nested_params, captures, allocator);
        },
        // Literals don't reference variables
        .int, .float, .bool_, .string, .null_, .undefined, .raw => {},
    }
}

/// Add a capture to the list (avoiding duplicates)
fn addCapture(
    name: []const u8,
    captures: *std.ArrayList([]const u8),
    allocator: std.mem.Allocator,
) !void {
    for (captures.items) |existing| {
        if (std.mem.eql(u8, existing, name)) return;
    }
    try captures.append(allocator, name);
}

// ============================================================================
// Pass 6: Declaration Ordering (Topological Sort)
// ============================================================================

/// Compute safe declaration order using topological sort
fn computeDeclarationOrder(
    statements: []const ZigIR,
    ctx: *AnalysisContext,
    result: *AnalysisResult,
    allocator: std.mem.Allocator,
) !void {
    _ = ctx;

    // Build dependency graph: var -> vars it references in its init expression
    var dependencies = hashmap_helper.StringHashMap(std.ArrayList([]const u8)).init(allocator);
    defer {
        var iter = dependencies.iterator();
        while (iter.next()) |entry| {
            entry.value_ptr.deinit(allocator);
        }
        dependencies.deinit();
    }

    // Collect all declarations and their dependencies
    var all_decls = std.ArrayList([]const u8){};
    defer all_decls.deinit(allocator);

    for (statements) |stmt| {
        try collectDeclDependencies(stmt, &dependencies, &all_decls, allocator);
    }

    // Topological sort using Kahn's algorithm
    var in_degree = hashmap_helper.StringHashMap(usize).init(allocator);
    defer in_degree.deinit();

    // Initialize in-degree for all nodes
    for (all_decls.items) |decl| {
        try in_degree.put(decl, 0);
    }

    // Calculate in-degrees
    var deps_iter = dependencies.iterator();
    while (deps_iter.next()) |entry| {
        for (entry.value_ptr.items) |dep| {
            if (in_degree.getPtr(dep)) |degree| {
                degree.* += 1;
            }
        }
    }

    // Queue for nodes with in-degree 0
    var queue = std.ArrayList([]const u8){};
    defer queue.deinit(allocator);

    var in_deg_iter = in_degree.iterator();
    while (in_deg_iter.next()) |entry| {
        if (entry.value_ptr.* == 0) {
            try queue.append(allocator, entry.key_ptr.*);
        }
    }

    // Process queue
    while (queue.items.len > 0) {
        const node = queue.orderedRemove(0);
        try result.declaration_order.append(allocator, node);

        // For each node that depends on this one, decrease in-degree
        if (dependencies.get(node)) |deps| {
            for (deps.items) |dep| {
                if (in_degree.getPtr(dep)) |degree| {
                    degree.* -= 1;
                    if (degree.* == 0) {
                        try queue.append(allocator, dep);
                    }
                }
            }
        }
    }

    // If not all nodes were processed, there's a cycle
    // Add remaining nodes (they form cycles and need special handling)
    for (all_decls.items) |decl| {
        var found = false;
        for (result.declaration_order.items) |ordered| {
            if (std.mem.eql(u8, ordered, decl)) {
                found = true;
                break;
            }
        }
        if (!found) {
            // Cyclic dependency - add anyway, will need var + undefined
            try result.declaration_order.append(allocator, decl);
            try result.mutated_vars.put(decl, {}); // Mark as needing var
        }
    }
}

/// Collect declaration dependencies from a statement
fn collectDeclDependencies(
    stmt: ZigIR,
    dependencies: *hashmap_helper.StringHashMap(std.ArrayList([]const u8)),
    all_decls: *std.ArrayList([]const u8),
    allocator: std.mem.Allocator,
) !void {
    switch (stmt) {
        .var_decl => |vd| {
            try all_decls.append(allocator, vd.name);
            var deps = std.ArrayList([]const u8){};
            try collectExprDependencies(vd.init, &deps, allocator);
            try dependencies.put(vd.name, deps);
        },
        .const_decl => |cd| {
            try all_decls.append(allocator, cd.name);
            var deps = std.ArrayList([]const u8){};
            try collectExprDependencies(cd.init, &deps, allocator);
            try dependencies.put(cd.name, deps);
        },
        .function => |func| {
            try all_decls.append(allocator, func.name);
            // Function body dependencies are captured separately
            const deps = std.ArrayList([]const u8){};
            try dependencies.put(func.name, deps);
        },
        // Don't recurse into nested scopes for top-level ordering
        else => {},
    }
}

/// Collect dependencies from an expression
fn collectExprDependencies(
    expr: *const ZigIRExpr,
    deps: *std.ArrayList([]const u8),
    allocator: std.mem.Allocator,
) !void {
    switch (expr.*) {
        .name => |name| {
            // Add as dependency (avoid duplicates)
            for (deps.items) |existing| {
                if (std.mem.eql(u8, existing, name)) return;
            }
            try deps.append(allocator, name);
        },
        .field_access => |fa| {
            try collectExprDependencies(fa.object, deps, allocator);
        },
        .subscript => |s| {
            try collectExprDependencies(s.object, deps, allocator);
            try collectExprDependencies(s.index, deps, allocator);
        },
        .slice => |s| {
            try collectExprDependencies(s.object, deps, allocator);
            if (s.start) |start| try collectExprDependencies(start, deps, allocator);
            if (s.end) |end| try collectExprDependencies(end, deps, allocator);
        },
        .call => |c| {
            try collectExprDependencies(c.func, deps, allocator);
            for (c.args) |arg| {
                try collectExprDependencies(arg, deps, allocator);
            }
        },
        .binop => |b| {
            try collectExprDependencies(b.left, deps, allocator);
            try collectExprDependencies(b.right, deps, allocator);
        },
        .unaryop => |u| {
            try collectExprDependencies(u.operand, deps, allocator);
        },
        .boolop => |bo| {
            for (bo.operands) |op| {
                try collectExprDependencies(op, deps, allocator);
            }
        },
        .ternary => |t| {
            try collectExprDependencies(t.condition, deps, allocator);
            try collectExprDependencies(t.then_expr, deps, allocator);
            try collectExprDependencies(t.else_expr, deps, allocator);
        },
        .array => |a| {
            for (a.elements) |elem| {
                try collectExprDependencies(elem, deps, allocator);
            }
        },
        .tuple => |t| {
            for (t.elements) |elem| {
                try collectExprDependencies(elem, deps, allocator);
            }
        },
        .struct_init => |si| {
            for (si.fields) |field| {
                try collectExprDependencies(field.value, deps, allocator);
            }
        },
        .cast => |c| {
            try collectExprDependencies(c.value, deps, allocator);
        },
        .builtin => |b| {
            for (b.args) |arg| {
                try collectExprDependencies(arg, deps, allocator);
            }
        },
        .try_ => |t| {
            try collectExprDependencies(t.expr, deps, allocator);
        },
        .catch_ => |c| {
            try collectExprDependencies(c.expr, deps, allocator);
            try collectExprDependencies(c.handler, deps, allocator);
        },
        .orelse_ => |o| {
            try collectExprDependencies(o.expr, deps, allocator);
            try collectExprDependencies(o.default, deps, allocator);
        },
        .address_of => |a| {
            try collectExprDependencies(a.expr, deps, allocator);
        },
        .deref => |d| {
            try collectExprDependencies(d.expr, deps, allocator);
        },
        // Literals don't have dependencies
        .int, .float, .bool_, .string, .null_, .undefined, .raw => {},
    }
}

// ============================================================================
// Pass 7: Per-Function Scope Analysis
// ============================================================================

/// Analyze a function's internal scope for mutations, aug_assigns, and uses
fn analyzeFunctionScope(stmt: ZigIR, result: *AnalysisResult, allocator: std.mem.Allocator) !void {
    switch (stmt) {
        .function => |func| {
            var scope = FunctionScope.init(allocator);
            errdefer scope.deinit();

            // Track assignments within function body
            var assignment_counts = hashmap_helper.StringHashMap(usize).init(allocator);
            defer assignment_counts.deinit();

            // Analyze function body
            for (func.body) |body_stmt| {
                try analyzeFunctionBodyStmt(body_stmt, &scope, &assignment_counts, allocator);
            }

            // Convert assignment counts to mutations
            var iter = assignment_counts.iterator();
            while (iter.next()) |entry| {
                if (entry.value_ptr.* > 1) {
                    try scope.mutations.put(entry.key_ptr.*, {});
                }
            }

            // Store function scope
            try result.function_scopes.put(func.name, scope);

            // Recursively analyze nested functions
            for (func.body) |body_stmt| {
                try analyzeFunctionScope(body_stmt, result, allocator);
            }
        },
        .if_stmt => |i| {
            for (i.then_body) |s| try analyzeFunctionScope(s, result, allocator);
            for (i.else_ifs) |elif| {
                for (elif.body) |s| try analyzeFunctionScope(s, result, allocator);
            }
            if (i.else_body) |eb| {
                for (eb) |s| try analyzeFunctionScope(s, result, allocator);
            }
        },
        .while_loop => |w| {
            for (w.body) |s| try analyzeFunctionScope(s, result, allocator);
        },
        .for_loop => |f| {
            for (f.body) |s| try analyzeFunctionScope(s, result, allocator);
        },
        .inline_for => |f| {
            for (f.body) |s| try analyzeFunctionScope(s, result, allocator);
        },
        .block => |b| {
            for (b.body) |s| try analyzeFunctionScope(s, result, allocator);
        },
        else => {},
    }
}

/// Analyze a statement within a function body
fn analyzeFunctionBodyStmt(
    stmt: ZigIR,
    scope: *FunctionScope,
    assignment_counts: *hashmap_helper.StringHashMap(usize),
    allocator: std.mem.Allocator,
) !void {
    switch (stmt) {
        .var_decl => |vd| {
            const count = assignment_counts.get(vd.name) orelse 0;
            try assignment_counts.put(vd.name, count + 1);
            try collectFunctionUses(vd.init, scope, allocator);
        },
        .const_decl => |cd| {
            const count = assignment_counts.get(cd.name) orelse 0;
            try assignment_counts.put(cd.name, count + 1);
            try collectFunctionUses(cd.init, scope, allocator);
        },
        .assign => |a| {
            if (a.target.* == .name) {
                const var_name = a.target.name;
                const count = assignment_counts.get(var_name) orelse 0;
                try assignment_counts.put(var_name, count + 1);

                // Check for self mutation
                if (std.mem.eql(u8, var_name, "self")) {
                    scope.mutates_self = true;
                }
            } else {
                // Check for self.field = ... pattern
                if (a.target.* == .field_access) {
                    const fa = a.target.field_access;
                    if (fa.object.* == .name and std.mem.eql(u8, fa.object.name, "self")) {
                        scope.mutates_self = true;
                    }
                }
                try collectFunctionUses(a.target, scope, allocator);
            }
            try collectFunctionUses(a.value, scope, allocator);
        },
        .aug_assign => |aa| {
            if (aa.target.* == .name) {
                const var_name = aa.target.name;
                try scope.aug_assigns.put(var_name, {});
                const count = assignment_counts.get(var_name) orelse 0;
                try assignment_counts.put(var_name, count + 1);
            } else {
                // Check for self.field += ... pattern
                if (aa.target.* == .field_access) {
                    const fa = aa.target.field_access;
                    if (fa.object.* == .name and std.mem.eql(u8, fa.object.name, "self")) {
                        scope.mutates_self = true;
                    }
                }
                try collectFunctionUses(aa.target, scope, allocator);
            }
            try collectFunctionUses(aa.value, scope, allocator);
        },
        .return_ => |r| {
            if (r.value) |v| {
                try collectFunctionUses(v, scope, allocator);
                // Check if returning self
                if (v.* == .name and std.mem.eql(u8, v.name, "self")) {
                    scope.mutates_self = true;
                }
            }
        },
        .expr_stmt => |e| {
            try collectFunctionUses(e.expr, scope, allocator);
        },
        .if_stmt => |i| {
            try collectFunctionUses(i.condition, scope, allocator);
            for (i.then_body) |s| {
                try analyzeFunctionBodyStmt(s, scope, assignment_counts, allocator);
            }
            for (i.else_ifs) |elif| {
                try collectFunctionUses(elif.condition, scope, allocator);
                for (elif.body) |s| {
                    try analyzeFunctionBodyStmt(s, scope, assignment_counts, allocator);
                }
            }
            if (i.else_body) |eb| {
                for (eb) |s| {
                    try analyzeFunctionBodyStmt(s, scope, assignment_counts, allocator);
                }
            }
        },
        .while_loop => |w| {
            try collectFunctionUses(w.condition, scope, allocator);
            for (w.body) |s| {
                try analyzeFunctionBodyStmt(s, scope, assignment_counts, allocator);
            }
        },
        .for_loop => |f| {
            // Loop variable is assigned each iteration
            const count = assignment_counts.get(f.target) orelse 0;
            try assignment_counts.put(f.target, count + 1);
            try collectFunctionUses(f.iter, scope, allocator);
            for (f.body) |s| {
                try analyzeFunctionBodyStmt(s, scope, assignment_counts, allocator);
            }
        },
        .inline_for => |f| {
            const count = assignment_counts.get(f.target) orelse 0;
            try assignment_counts.put(f.target, count + 1);
            try collectFunctionUses(f.iter, scope, allocator);
            for (f.body) |s| {
                try analyzeFunctionBodyStmt(s, scope, assignment_counts, allocator);
            }
        },
        .block => |b| {
            for (b.body) |s| {
                try analyzeFunctionBodyStmt(s, scope, assignment_counts, allocator);
            }
        },
        .defer_ => |d| {
            try collectFunctionUses(d.expr, scope, allocator);
        },
        .errdefer_ => |e| {
            try collectFunctionUses(e.expr, scope, allocator);
        },
        .discard => |d| {
            try collectFunctionUses(d.expr, scope, allocator);
        },
        else => {},
    }
}

/// Collect variable uses in an expression within a function
fn collectFunctionUses(expr: *const ZigIRExpr, scope: *FunctionScope, allocator: std.mem.Allocator) !void {
    switch (expr.*) {
        .name => |name| {
            try scope.uses.put(name, {});
        },
        .field_access => |fa| {
            try collectFunctionUses(fa.object, scope, allocator);
        },
        .subscript => |s| {
            try collectFunctionUses(s.object, scope, allocator);
            try collectFunctionUses(s.index, scope, allocator);
        },
        .slice => |s| {
            try collectFunctionUses(s.object, scope, allocator);
            if (s.start) |start| try collectFunctionUses(start, scope, allocator);
            if (s.end) |end| try collectFunctionUses(end, scope, allocator);
        },
        .call => |c| {
            try collectFunctionUses(c.func, scope, allocator);
            for (c.args) |arg| {
                try collectFunctionUses(arg, scope, allocator);
            }
        },
        .binop => |b| {
            try collectFunctionUses(b.left, scope, allocator);
            try collectFunctionUses(b.right, scope, allocator);
        },
        .unaryop => |u| {
            try collectFunctionUses(u.operand, scope, allocator);
        },
        .boolop => |bo| {
            for (bo.operands) |op| {
                try collectFunctionUses(op, scope, allocator);
            }
        },
        .ternary => |t| {
            try collectFunctionUses(t.condition, scope, allocator);
            try collectFunctionUses(t.then_expr, scope, allocator);
            try collectFunctionUses(t.else_expr, scope, allocator);
        },
        .array => |a| {
            for (a.elements) |elem| {
                try collectFunctionUses(elem, scope, allocator);
            }
        },
        .tuple => |t| {
            for (t.elements) |elem| {
                try collectFunctionUses(elem, scope, allocator);
            }
        },
        .struct_init => |si| {
            for (si.fields) |field| {
                try collectFunctionUses(field.value, scope, allocator);
            }
        },
        .cast => |c| {
            try collectFunctionUses(c.value, scope, allocator);
        },
        .builtin => |b| {
            for (b.args) |arg| {
                try collectFunctionUses(arg, scope, allocator);
            }
        },
        .try_ => |t| {
            try collectFunctionUses(t.expr, scope, allocator);
        },
        .catch_ => |c| {
            try collectFunctionUses(c.expr, scope, allocator);
            try collectFunctionUses(c.handler, scope, allocator);
        },
        .orelse_ => |o| {
            try collectFunctionUses(o.expr, scope, allocator);
            try collectFunctionUses(o.default, scope, allocator);
        },
        .address_of => |a| {
            try collectFunctionUses(a.expr, scope, allocator);
        },
        .deref => |d| {
            try collectFunctionUses(d.expr, scope, allocator);
        },
        // Literals don't reference variables
        .int, .float, .bool_, .string, .null_, .undefined, .raw => {},
    }
}

// ============================================================================
// Tests
// ============================================================================

test "analyze const variable" {
    const allocator = std.testing.allocator;

    // Simulate: x = 1
    const int_expr = try allocator.create(ZigIRExpr);
    defer allocator.destroy(int_expr);
    int_expr.* = .{ .int = 1 };

    const statements = try allocator.alloc(ZigIR, 1);
    defer allocator.free(statements);
    statements[0] = .{ .var_decl = .{
        .name = "x",
        .init = int_expr,
    } };

    var result = try analyze(statements, allocator);
    defer result.deinit();

    // x should be const (assigned once)
    try std.testing.expect(result.shouldBeConst("x"));
}

test "analyze mutated variable" {
    const allocator = std.testing.allocator;

    // Simulate: x = 1; x = 2
    const int_expr1 = try allocator.create(ZigIRExpr);
    defer allocator.destroy(int_expr1);
    int_expr1.* = .{ .int = 1 };

    const int_expr2 = try allocator.create(ZigIRExpr);
    defer allocator.destroy(int_expr2);
    int_expr2.* = .{ .int = 2 };

    const name_expr = try allocator.create(ZigIRExpr);
    defer allocator.destroy(name_expr);
    name_expr.* = .{ .name = "x" };

    const statements = try allocator.alloc(ZigIR, 2);
    defer allocator.free(statements);
    statements[0] = .{ .var_decl = .{
        .name = "x",
        .init = int_expr1,
    } };
    statements[1] = .{ .assign = .{
        .target = name_expr,
        .value = int_expr2,
    } };

    var result = try analyze(statements, allocator);
    defer result.deinit();

    // x should be var (assigned twice)
    try std.testing.expect(!result.shouldBeConst("x"));
}
