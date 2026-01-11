//! Pass 2.5: Variable Resolution
//!
//! Pre-computes ALL variable names before code generation.
//! Like a real compiler, assigns unique Zig identifiers to every Python variable upfront.
//!
//! Core Principle: Every variable gets a unique Zig name during this pass.
//! Codegen becomes a pure READ operation with no runtime state accumulation.
//!
//! Example:
//!   def outer():
//!       x = 1           # -> __v_outer_x_0
//!       def inner():
//!           x = 2       # -> __v_inner_x_1 (different variable!)
//!           y = x + 1   # -> __v_inner_y_2, references __v_inner_x_1
//!       return x        # -> references __v_outer_x_0
//!
//! This eliminates ALL rename tracking because there are no renames - just unique names.

const std = @import("std");
const ast = @import("analysis.ast");
const hashmap_helper = @import("utils.hashmap_helper");

// ============================================================================
// Public Types
// ============================================================================

/// Unique scope identifier
pub const ScopeId = struct {
    id: u64, // Globally unique numeric ID (counter-based)

    pub const INVALID: ScopeId = .{ .id = std.math.maxInt(u64) };
    pub const MODULE: ScopeId = .{ .id = 0 };

    pub fn eql(self: ScopeId, other: ScopeId) bool {
        return self.id == other.id;
    }

    pub fn isValid(self: ScopeId) bool {
        return self.id != std.math.maxInt(u64);
    }
};

/// Per-variable unique identifier - the CORE data structure
/// Every Python variable gets a unique Zig identifier.
/// This is the SINGLE SOURCE OF TRUTH for variable names.
pub const VariableInfo = struct {
    python_name: []const u8, // Original Python name: "x"
    zig_name: []const u8, // UNIQUE Zig name: "__v_outer_x_0" (ALWAYS set)
    scope_id: ScopeId, // Which scope this belongs to

    // Flags for codegen behavior
    is_captured: bool = false, // Referenced by nested function
    is_hoisted: bool = false, // Needs pre-declaration (try/for escape)
    is_parameter: bool = false, // Function parameter
    is_exception_var: bool = false, // Exception handler variable (e as Exception)
    in_vm_fallback: bool = false, // Used in eval() string

    /// For debugging
    pub fn format(
        self: VariableInfo,
        comptime _: []const u8,
        _: std.fmt.FormatOptions,
        writer: anytype,
    ) !void {
        try writer.print("{s} -> {s} (scope {})", .{ self.python_name, self.zig_name, self.scope_id.id });
    }
};

/// Scope type classification
pub const ScopeType = enum {
    module, // Top-level module scope
    function, // Regular function
    class, // Class body
    lambda, // Lambda expression
    comprehension, // List/dict/set comprehension
};

/// Per-scope variable table
pub const ScopeInfo = struct {
    scope_id: ScopeId,
    parent_scope: ?ScopeId,
    scope_name: []const u8, // "outer", "inner", "module"
    scope_type: ScopeType,

    // Maps Python name -> VariableInfo for vars DECLARED in this scope
    variables: hashmap_helper.StringHashMap(VariableInfo),

    // For nested functions: maps Python name -> parent's VariableInfo
    // These are variables referenced but not declared locally
    captured_from_parent: hashmap_helper.StringHashMap(VariableInfo),

    allocator: std.mem.Allocator,

    pub fn init(allocator: std.mem.Allocator, scope_id: ScopeId, parent: ?ScopeId, name: []const u8, scope_type: ScopeType) ScopeInfo {
        return .{
            .scope_id = scope_id,
            .parent_scope = parent,
            .scope_name = name,
            .scope_type = scope_type,
            .variables = hashmap_helper.StringHashMap(VariableInfo).init(allocator),
            .captured_from_parent = hashmap_helper.StringHashMap(VariableInfo).init(allocator),
            .allocator = allocator,
        };
    }

    pub fn deinit(self: *ScopeInfo) void {
        self.variables.deinit();
        self.captured_from_parent.deinit();
    }

    /// Look up a variable in this scope (local or captured)
    pub fn getVariable(self: *const ScopeInfo, python_name: []const u8) ?VariableInfo {
        // Check local first
        if (self.variables.get(python_name)) |info| {
            return info;
        }
        // Check captured
        if (self.captured_from_parent.get(python_name)) |info| {
            return info;
        }
        return null;
    }
};

/// Pass 2.5 output - the main result structure
pub const VariableResolution = struct {
    allocator: std.mem.Allocator,
    next_var_id: u64 = 0,
    next_scope_id: u64 = 0,

    // All scopes indexed by ScopeId
    scopes: std.AutoHashMap(u64, ScopeInfo),

    // Quick lookup: scope_name -> ScopeId (for nested function lookup)
    scope_by_name: hashmap_helper.StringHashMap(ScopeId),

    // Stack of current scope chain during analysis (for resolving captures)
    scope_stack: std.ArrayList(ScopeId),

    pub fn init(allocator: std.mem.Allocator) VariableResolution {
        return .{
            .allocator = allocator,
            .scopes = std.AutoHashMap(u64, ScopeInfo).init(allocator),
            .scope_by_name = hashmap_helper.StringHashMap(ScopeId).init(allocator),
            .scope_stack = std.ArrayList(ScopeId){},
        };
    }

    pub fn deinit(self: *VariableResolution) void {
        var iter = self.scopes.iterator();
        while (iter.next()) |entry| {
            entry.value_ptr.deinit();
        }
        self.scopes.deinit();
        self.scope_by_name.deinit();
        self.scope_stack.deinit(self.allocator);
    }

    // ========================================================================
    // Scope Management
    // ========================================================================

    /// Create a new scope and return its ID
    pub fn createScope(self: *VariableResolution, name: []const u8, parent: ?ScopeId, scope_type: ScopeType) !ScopeId {
        const id = ScopeId{ .id = self.next_scope_id };
        self.next_scope_id += 1;

        const scope = ScopeInfo.init(self.allocator, id, parent, name, scope_type);
        try self.scopes.put(id.id, scope);
        try self.scope_by_name.put(name, id);

        return id;
    }

    /// Get a scope by ID
    pub fn getScope(self: *VariableResolution, scope_id: ScopeId) ?*ScopeInfo {
        return self.scopes.getPtr(scope_id.id);
    }

    /// Get a scope by name
    pub fn getScopeByName(self: *VariableResolution, name: []const u8) ?ScopeId {
        return self.scope_by_name.get(name);
    }

    /// Get a child scope by name from a given parent scope
    /// This handles cases where multiple scopes have the same name (e.g., methods in different classes)
    pub fn getChildScope(self: *VariableResolution, parent_scope_id: ScopeId, child_name: []const u8) ?ScopeId {
        // Iterate through all scopes to find one with matching name and parent
        var iter = self.scopes.iterator();
        while (iter.next()) |entry| {
            const scope = entry.value_ptr;
            if (std.mem.eql(u8, scope.scope_name, child_name)) {
                if (scope.parent_scope) |parent| {
                    if (parent.id == parent_scope_id.id) {
                        return ScopeId{ .id = entry.key_ptr.* };
                    }
                }
            }
        }
        return null;
    }

    /// Push scope onto stack (for nested resolution)
    pub fn pushScope(self: *VariableResolution, scope_id: ScopeId) !void {
        try self.scope_stack.append(self.allocator, scope_id);
    }

    /// Pop scope from stack
    pub fn popScope(self: *VariableResolution) ?ScopeId {
        return self.scope_stack.pop();
    }

    /// Get current scope ID
    pub fn currentScope(self: *VariableResolution) ?ScopeId {
        if (self.scope_stack.items.len == 0) return null;
        return self.scope_stack.items[self.scope_stack.items.len - 1];
    }

    // ========================================================================
    // Variable Registration
    // ========================================================================

    /// Generate unique Zig name: __v_{scope_name}_{python_name}_{id}
    pub fn generateUniqueName(self: *VariableResolution, scope_name: []const u8, python_name: []const u8) ![]const u8 {
        const id = self.next_var_id;
        self.next_var_id += 1;
        return try std.fmt.allocPrint(self.allocator, "__v_{s}_{s}_{d}", .{ scope_name, python_name, id });
    }

    /// Register a variable in a scope with a unique Zig name
    pub fn registerVariable(
        self: *VariableResolution,
        scope_id: ScopeId,
        python_name: []const u8,
        flags: struct {
            is_parameter: bool = false,
            is_exception_var: bool = false,
            is_hoisted: bool = false,
            in_vm_fallback: bool = false,
        },
    ) !VariableInfo {
        const scope = self.getScope(scope_id) orelse return error.ScopeNotFound;

        // Check if already registered
        if (scope.variables.get(python_name)) |existing| {
            return existing;
        }

        // Generate unique name
        const zig_name = try self.generateUniqueName(scope.scope_name, python_name);

        const info = VariableInfo{
            .python_name = python_name,
            .zig_name = zig_name,
            .scope_id = scope_id,
            .is_parameter = flags.is_parameter,
            .is_exception_var = flags.is_exception_var,
            .is_hoisted = flags.is_hoisted,
            .in_vm_fallback = flags.in_vm_fallback,
        };

        try scope.variables.put(python_name, info);
        return info;
    }

    /// Register a captured variable (reference to parent's variable)
    pub fn registerCapture(
        self: *VariableResolution,
        scope_id: ScopeId,
        python_name: []const u8,
        parent_info: VariableInfo,
    ) !void {
        const scope = self.getScope(scope_id) orelse return error.ScopeNotFound;

        // Mark the parent's variable as captured
        if (self.getScope(parent_info.scope_id)) |parent_scope| {
            if (parent_scope.variables.getPtr(python_name)) |parent_var| {
                parent_var.is_captured = true;
            }
        }

        // Store the capture reference with the SAME zig_name as parent
        var capture_info = parent_info;
        capture_info.is_captured = true;
        try scope.captured_from_parent.put(python_name, capture_info);
    }

    // ========================================================================
    // Query Methods (used by codegen)
    // ========================================================================

    /// Quick lookup: (scope_id, python_name) -> zig_name
    /// This is the ONLY function codegen needs to call for variable names
    pub fn getZigName(self: *VariableResolution, scope_id: ScopeId, python_name: []const u8) ?[]const u8 {
        const scope = self.getScope(scope_id) orelse return null;

        // 1. Check if declared in this scope
        if (scope.variables.get(python_name)) |info| {
            return info.zig_name;
        }

        // 2. Check if captured from parent
        if (scope.captured_from_parent.get(python_name)) |info| {
            return info.zig_name;
        }

        return null; // Not found = global or builtin
    }

    /// Get full variable info
    pub fn getVariableInfo(self: *VariableResolution, scope_id: ScopeId, python_name: []const u8) ?VariableInfo {
        const scope = self.getScope(scope_id) orelse return null;
        return scope.getVariable(python_name);
    }

    /// Check if variable is declared in this specific scope (not captured)
    pub fn isDeclaredInScope(self: *VariableResolution, scope_id: ScopeId, python_name: []const u8) bool {
        const scope = self.getScope(scope_id) orelse return false;
        return scope.variables.contains(python_name);
    }

    /// Check if variable is captured (from parent)
    pub fn isCaptured(self: *VariableResolution, scope_id: ScopeId, python_name: []const u8) bool {
        const scope = self.getScope(scope_id) orelse return false;
        return scope.captured_from_parent.contains(python_name);
    }

    /// Check if variable needs hoisting
    pub fn isHoisted(self: *VariableResolution, scope_id: ScopeId, python_name: []const u8) bool {
        const scope = self.getScope(scope_id) orelse return false;
        if (scope.variables.get(python_name)) |info| {
            return info.is_hoisted;
        }
        return false;
    }

    /// Check if variable is a parameter
    pub fn isParameter(self: *VariableResolution, scope_id: ScopeId, python_name: []const u8) bool {
        const scope = self.getScope(scope_id) orelse return false;
        if (scope.variables.get(python_name)) |info| {
            return info.is_parameter;
        }
        return false;
    }

    /// Look up a class name in the module scope
    /// Class names are always declared at module level, so use this for class references
    /// in nested scopes (e.g., closure capture types referencing the enclosing class)
    pub fn getZigNameAtModuleScope(self: *VariableResolution, python_name: []const u8) ?[]const u8 {
        // Module scope is always created first with ID 0
        const module_scope_id = ScopeId{ .id = 0 };
        return self.getZigName(module_scope_id, python_name);
    }

    /// Look up a variable in a child scope of the current scope
    /// Used for method-local classes: when generating a method signature at class scope,
    /// we need to look up classes defined inside the method body
    pub fn getZigNameInChildScope(self: *VariableResolution, parent_scope: ScopeId, child_name: []const u8, python_name: []const u8) ?[]const u8 {
        if (self.getChildScope(parent_scope, child_name)) |child_scope| {
            return self.getZigName(child_scope, python_name);
        }
        return null;
    }

    /// Look up a variable by searching up through ancestor scopes
    /// Used for method return types that reference classes defined at ancestor scope level
    /// (e.g., nested class method returning sibling class)
    const DEBUG_SEARCH_UP = false;
    pub fn getZigNameSearchingUp(self: *VariableResolution, start_scope: ScopeId, python_name: []const u8) ?[]const u8 {
        var current = start_scope;
        var depth: usize = 0;
        while (depth < 20) : (depth += 1) {
            const scope = self.getScope(current) orelse return null;
            if (DEBUG_SEARCH_UP) std.debug.print("[SEARCH_UP] Looking for '{s}' in scope '{s}' (id={d})\n", .{ python_name, scope.scope_name, current.id });
            // Check current scope
            if (self.getZigName(current, python_name)) |zig_name| {
                if (DEBUG_SEARCH_UP) std.debug.print("[SEARCH_UP] Found '{s}' -> '{s}' in scope '{s}'\n", .{ python_name, zig_name, scope.scope_name });
                return zig_name;
            }
            // Move to parent
            current = scope.parent_scope orelse {
                if (DEBUG_SEARCH_UP) std.debug.print("[SEARCH_UP] Reached root scope, '{s}' not found\n", .{python_name});
                return null;
            };
        }
        return null;
    }

    /// Get all variables in a scope
    pub fn getVariablesInScope(self: *VariableResolution, scope_id: ScopeId) ?*const hashmap_helper.StringHashMap(VariableInfo) {
        const scope = self.getScope(scope_id) orelse return null;
        return &scope.variables;
    }

    /// Get all captured variables in a scope
    pub fn getCapturedVariables(self: *VariableResolution, scope_id: ScopeId) ?*const hashmap_helper.StringHashMap(VariableInfo) {
        const scope = self.getScope(scope_id) orelse return null;
        return &scope.captured_from_parent;
    }
};

// ============================================================================
// Pass 2.5 Implementation - AST Walking
// ============================================================================

/// Context for variable resolution walk
const ResolutionContext = struct {
    resolution: *VariableResolution,
    allocator: std.mem.Allocator,

    /// Variables assigned in inner scopes (for hoisting detection)
    inner_assignments: hashmap_helper.StringHashMap(void),

    /// Variables used at outer (function) level
    outer_uses: hashmap_helper.StringHashMap(void),

    /// Variables declared as `nonlocal` in the current function scope.
    /// These should NOT be registered as local variables.
    /// Points to a hashmap that's managed by collectDeclarations for each function.
    nonlocal_vars: ?*hashmap_helper.StringHashMap(void) = null,

    pub fn init(allocator: std.mem.Allocator, resolution: *VariableResolution) ResolutionContext {
        return .{
            .resolution = resolution,
            .allocator = allocator,
            .inner_assignments = hashmap_helper.StringHashMap(void).init(allocator),
            .outer_uses = hashmap_helper.StringHashMap(void).init(allocator),
            .nonlocal_vars = null,
        };
    }

    pub fn deinit(self: *ResolutionContext) void {
        self.inner_assignments.deinit();
        self.outer_uses.deinit();
    }

    /// Check if a variable is declared as nonlocal in the current scope
    pub fn isNonlocal(self: *const ResolutionContext, var_name: []const u8) bool {
        if (self.nonlocal_vars) |nonlocals| {
            return nonlocals.contains(var_name);
        }
        return false;
    }
};

/// Main entry point: Resolve all variables in an AST module
pub fn resolveVariables(stmts: []const ast.Node, allocator: std.mem.Allocator) !VariableResolution {
    var resolution = VariableResolution.init(allocator);
    errdefer resolution.deinit();

    // Create module scope
    const module_scope = try resolution.createScope("module", null, .module);
    try resolution.pushScope(module_scope);

    var ctx = ResolutionContext.init(allocator, &resolution);
    defer ctx.deinit();

    // Phase 1: Collect all declarations
    for (stmts) |stmt| {
        try collectDeclarations(stmt, &ctx, module_scope, false);
    }

    // Phase 2: Resolve captures (link nested function references to parent vars)
    for (stmts) |stmt| {
        try resolveCaptures(stmt, &ctx, module_scope);
    }

    _ = resolution.popScope();
    return resolution;
}

/// Phase 1: Collect all variable declarations in a scope
fn collectDeclarations(node: ast.Node, ctx: *ResolutionContext, scope_id: ScopeId, in_inner_scope: bool) !void {
    switch (node) {
        .function_def => |func| {
            // Register function name in current scope (functions are variables too)
            _ = try ctx.resolution.registerVariable(scope_id, func.name, .{});

            // Create new scope for function body
            const func_scope = try ctx.resolution.createScope(func.name, scope_id, .function);
            try ctx.resolution.pushScope(func_scope);

            // FIRST: Collect nonlocal variables in this function body
            // Nonlocal variables reference the enclosing scope and should NOT be registered
            // as local variables in this scope
            const saved_nonlocals = ctx.nonlocal_vars;
            var nonlocals = hashmap_helper.StringHashMap(void).init(ctx.resolution.allocator);
            collectNonlocalVarsInStmts(func.body, &nonlocals);
            ctx.nonlocal_vars = &nonlocals;
            defer {
                nonlocals.deinit();
                ctx.nonlocal_vars = saved_nonlocals;
            }

            // Register parameters
            for (func.args) |arg| {
                _ = try ctx.resolution.registerVariable(func_scope, arg.name, .{ .is_parameter = true });
            }

            // Process function body
            for (func.body) |stmt| {
                try collectDeclarations(stmt, ctx, func_scope, false);
            }

            _ = ctx.resolution.popScope();
        },

        .class_def => |class| {
            // Register class name
            _ = try ctx.resolution.registerVariable(scope_id, class.name, .{});

            // Create scope for class body
            const class_scope = try ctx.resolution.createScope(class.name, scope_id, .class);
            try ctx.resolution.pushScope(class_scope);

            for (class.body) |stmt| {
                try collectDeclarations(stmt, ctx, class_scope, false);
            }

            _ = ctx.resolution.popScope();
        },

        .assign => |assign| {
            // Collect target names (Assign has targets array, not single target)
            for (assign.targets) |target| {
                try collectAssignTarget(target, ctx, scope_id, in_inner_scope);
            }
        },

        .ann_assign => |ann| {
            if (ann.target.* == .name) {
                const var_name = ann.target.name.id;
                // Skip if declared as nonlocal - nonlocal vars reference enclosing scope
                if (!ctx.isNonlocal(var_name)) {
                    const is_hoisted = in_inner_scope and ctx.outer_uses.contains(var_name);
                    _ = try ctx.resolution.registerVariable(scope_id, var_name, .{ .is_hoisted = is_hoisted });
                    if (in_inner_scope) {
                        try ctx.inner_assignments.put(var_name, {});
                    }
                }
            }
        },

        .aug_assign => |aug| {
            if (aug.target.* == .name) {
                const var_name = aug.target.name.id;
                // Skip if declared as nonlocal - nonlocal vars reference enclosing scope
                if (!ctx.isNonlocal(var_name)) {
                    const is_hoisted = in_inner_scope and ctx.outer_uses.contains(var_name);
                    _ = try ctx.resolution.registerVariable(scope_id, var_name, .{ .is_hoisted = is_hoisted });
                }
            }
        },

        .for_stmt => |for_s| {
            // Register loop variable
            try collectAssignTarget(for_s.target.*, ctx, scope_id, true);

            // Process body
            for (for_s.body) |stmt| {
                try collectDeclarations(stmt, ctx, scope_id, true);
            }
            if (for_s.orelse_body) |orelse_body| {
                for (orelse_body) |stmt| {
                    try collectDeclarations(stmt, ctx, scope_id, true);
                }
            }
        },

        .while_stmt => |while_s| {
            for (while_s.body) |stmt| {
                try collectDeclarations(stmt, ctx, scope_id, true);
            }
            if (while_s.orelse_body) |orelse_body| {
                for (orelse_body) |stmt| {
                    try collectDeclarations(stmt, ctx, scope_id, true);
                }
            }
        },

        .if_stmt => |if_s| {
            for (if_s.body) |stmt| {
                try collectDeclarations(stmt, ctx, scope_id, true);
            }
            // else_body may contain nested if (elif) - recurse into it
            for (if_s.else_body) |stmt| {
                try collectDeclarations(stmt, ctx, scope_id, true);
            }
        },

        .try_stmt => |try_s| {
            for (try_s.body) |stmt| {
                try collectDeclarations(stmt, ctx, scope_id, true);
            }
            for (try_s.handlers) |handler| {
                // Register exception variable
                if (handler.name) |name| {
                    _ = try ctx.resolution.registerVariable(scope_id, name, .{ .is_exception_var = true });
                }
                for (handler.body) |stmt| {
                    try collectDeclarations(stmt, ctx, scope_id, true);
                }
            }
            // else_body is not optional in AST
            for (try_s.else_body) |stmt| {
                try collectDeclarations(stmt, ctx, scope_id, true);
            }
            // finalbody (not finally_body)
            for (try_s.finalbody) |stmt| {
                try collectDeclarations(stmt, ctx, scope_id, true);
            }
        },

        .with_stmt => |with_s| {
            // optional_vars is the "as" target (e.g., "f" in "with open() as f")
            if (with_s.optional_vars) |as_target| {
                try collectAssignTarget(as_target.*, ctx, scope_id, true);
            }
            for (with_s.body) |stmt| {
                try collectDeclarations(stmt, ctx, scope_id, true);
            }
        },

        .match_stmt => |match_s| {
            for (match_s.cases) |case| {
                // Register pattern bindings
                try collectPatternBindings(case.pattern, ctx, scope_id);
                for (case.body) |stmt| {
                    try collectDeclarations(stmt, ctx, scope_id, true);
                }
            }
        },

        .lambda => |lambda| {
            // Lambdas create their own scope
            const lambda_name = try std.fmt.allocPrint(ctx.allocator, "__lambda_{d}", .{ctx.resolution.next_scope_id});
            const lambda_scope = try ctx.resolution.createScope(lambda_name, scope_id, .lambda);
            try ctx.resolution.pushScope(lambda_scope);

            for (lambda.args) |arg| {
                _ = try ctx.resolution.registerVariable(lambda_scope, arg.name, .{ .is_parameter = true });
            }

            _ = ctx.resolution.popScope();
        },

        else => {},
    }
}

/// Collect assignment target names
fn collectAssignTarget(target: ast.Node, ctx: *ResolutionContext, scope_id: ScopeId, in_inner_scope: bool) !void {
    switch (target) {
        .name => |name| {
            const var_name = name.id;
            // Skip discard
            if (var_name.len == 1 and var_name[0] == '_') return;
            // Skip if declared as nonlocal - nonlocal vars reference enclosing scope
            if (ctx.isNonlocal(var_name)) return;

            const is_hoisted = in_inner_scope and ctx.outer_uses.contains(var_name);
            _ = try ctx.resolution.registerVariable(scope_id, var_name, .{ .is_hoisted = is_hoisted });
            if (in_inner_scope) {
                try ctx.inner_assignments.put(var_name, {});
            }
        },
        .tuple => |tuple| {
            for (tuple.elts) |elem| {
                try collectAssignTarget(elem, ctx, scope_id, in_inner_scope);
            }
        },
        .list => |list| {
            for (list.elts) |elem| {
                try collectAssignTarget(elem, ctx, scope_id, in_inner_scope);
            }
        },
        .starred => |starred| {
            try collectAssignTarget(starred.value.*, ctx, scope_id, in_inner_scope);
        },
        else => {},
    }
}

/// Collect pattern bindings from match statements
fn collectPatternBindings(pattern: ast.Node.MatchPattern, ctx: *ResolutionContext, scope_id: ScopeId) !void {
    switch (pattern) {
        .capture => |name| {
            // case x -> captures x
            if (name.len > 0 and name[0] != '_') {
                _ = try ctx.resolution.registerVariable(scope_id, name, .{});
            }
        },
        .as_pattern => |as_pat| {
            // case pattern as name
            _ = try ctx.resolution.registerVariable(scope_id, as_pat.name, .{});
            try collectPatternBindings(as_pat.pattern.*, ctx, scope_id);
        },
        .or_pattern => |patterns| {
            // case 1 | 2 | 3
            for (patterns) |p| {
                try collectPatternBindings(p, ctx, scope_id);
            }
        },
        .sequence => |patterns| {
            // case [a, b, c]
            for (patterns) |p| {
                try collectPatternBindings(p, ctx, scope_id);
            }
        },
        .mapping => |entries| {
            // case {"key": value}
            for (entries) |entry| {
                try collectPatternBindings(entry.pattern, ctx, scope_id);
            }
        },
        .class_pattern => |cp| {
            // case Point(x=0, y=0)
            for (cp.positional) |p| {
                try collectPatternBindings(p, ctx, scope_id);
            }
            for (cp.keyword) |kw| {
                try collectPatternBindings(kw.pattern, ctx, scope_id);
            }
        },
        // literal, wildcard, value don't bind variables
        else => {},
    }
}

/// Phase 2: Resolve captures (link nested function variable uses to parent declarations)
fn resolveCaptures(node: ast.Node, ctx: *ResolutionContext, scope_id: ScopeId) !void {
    switch (node) {
        .function_def => |func| {
            // Get the function's own scope
            if (ctx.resolution.getScopeByName(func.name)) |func_scope_id| {
                try ctx.resolution.pushScope(func_scope_id);

                // Process body - look for variable references
                for (func.body) |stmt| {
                    try resolveReferences(stmt, ctx, func_scope_id);
                    try resolveCaptures(stmt, ctx, func_scope_id);
                }

                _ = ctx.resolution.popScope();
            }
        },

        .class_def => |class| {
            if (ctx.resolution.getScopeByName(class.name)) |class_scope_id| {
                try ctx.resolution.pushScope(class_scope_id);

                for (class.body) |stmt| {
                    try resolveReferences(stmt, ctx, class_scope_id);
                    try resolveCaptures(stmt, ctx, class_scope_id);
                }

                _ = ctx.resolution.popScope();
            }
        },

        // For other statements, just recurse
        .for_stmt => |for_s| {
            for (for_s.body) |stmt| {
                try resolveCaptures(stmt, ctx, scope_id);
            }
            if (for_s.orelse_body) |orelse_body| {
                for (orelse_body) |stmt| {
                    try resolveCaptures(stmt, ctx, scope_id);
                }
            }
        },

        .while_stmt => |while_s| {
            for (while_s.body) |stmt| {
                try resolveCaptures(stmt, ctx, scope_id);
            }
            if (while_s.orelse_body) |orelse_body| {
                for (orelse_body) |stmt| {
                    try resolveCaptures(stmt, ctx, scope_id);
                }
            }
        },

        .if_stmt => |if_s| {
            for (if_s.body) |stmt| {
                try resolveCaptures(stmt, ctx, scope_id);
            }
            // else_body may contain nested if (elif)
            for (if_s.else_body) |stmt| {
                try resolveCaptures(stmt, ctx, scope_id);
            }
        },

        .try_stmt => |try_s| {
            for (try_s.body) |stmt| {
                try resolveCaptures(stmt, ctx, scope_id);
            }
            for (try_s.handlers) |handler| {
                for (handler.body) |stmt| {
                    try resolveCaptures(stmt, ctx, scope_id);
                }
            }
            for (try_s.else_body) |stmt| {
                try resolveCaptures(stmt, ctx, scope_id);
            }
            for (try_s.finalbody) |stmt| {
                try resolveCaptures(stmt, ctx, scope_id);
            }
        },

        .with_stmt => |with_s| {
            for (with_s.body) |stmt| {
                try resolveCaptures(stmt, ctx, scope_id);
            }
        },

        else => {},
    }
}

/// Resolve variable references - check if they need to be captured from parent
fn resolveReferences(node: ast.Node, ctx: *ResolutionContext, scope_id: ScopeId) !void {
    switch (node) {
        .name => |name| {
            const var_name = name.id;

            // Check if already declared or captured in this scope
            if (ctx.resolution.isDeclaredInScope(scope_id, var_name)) return;
            if (ctx.resolution.isCaptured(scope_id, var_name)) return;

            // Look up parent scope chain for the variable
            if (try findInParentScopes(ctx.resolution, scope_id, var_name)) |parent_info| {
                try ctx.resolution.registerCapture(scope_id, var_name, parent_info);
            }
        },

        // Recurse into expressions
        .binop => |binop| {
            try resolveReferences(binop.left.*, ctx, scope_id);
            try resolveReferences(binop.right.*, ctx, scope_id);
        },

        .unaryop => |unary| {
            try resolveReferences(unary.operand.*, ctx, scope_id);
        },

        .call => |call| {
            try resolveReferences(call.func.*, ctx, scope_id);
            for (call.args) |arg| {
                try resolveReferences(arg, ctx, scope_id);
            }
            for (call.keyword_args) |kw| {
                try resolveReferences(kw.value, ctx, scope_id);
            }
        },

        .attribute => |attr| {
            try resolveReferences(attr.value.*, ctx, scope_id);
        },

        .subscript => |sub| {
            try resolveReferences(sub.value.*, ctx, scope_id);
            // Slice is a union: .index or .slice
            switch (sub.slice) {
                .index => |idx| try resolveReferences(idx.*, ctx, scope_id),
                .slice => |range| {
                    if (range.lower) |lower| try resolveReferences(lower.*, ctx, scope_id);
                    if (range.upper) |upper| try resolveReferences(upper.*, ctx, scope_id);
                    if (range.step) |step| try resolveReferences(step.*, ctx, scope_id);
                },
            }
        },

        .if_expr => |ifexp| {
            // IfExpr uses condition, body, orelse_value
            try resolveReferences(ifexp.condition.*, ctx, scope_id);
            try resolveReferences(ifexp.body.*, ctx, scope_id);
            try resolveReferences(ifexp.orelse_value.*, ctx, scope_id);
        },

        .tuple => |tuple| {
            for (tuple.elts) |elem| {
                try resolveReferences(elem, ctx, scope_id);
            }
        },

        .list => |list| {
            for (list.elts) |elem| {
                try resolveReferences(elem, ctx, scope_id);
            }
        },

        .dict => |dict| {
            for (dict.keys) |key| {
                try resolveReferences(key, ctx, scope_id);
            }
            for (dict.values) |val| {
                try resolveReferences(val, ctx, scope_id);
            }
        },

        .set => |set_node| {
            for (set_node.elts) |elem| {
                try resolveReferences(elem, ctx, scope_id);
            }
        },

        // Statement resolution
        .assign => |assign| {
            try resolveReferences(assign.value.*, ctx, scope_id);
        },

        .aug_assign => |aug| {
            try resolveReferences(aug.target.*, ctx, scope_id);
            try resolveReferences(aug.value.*, ctx, scope_id);
        },

        .return_stmt => |ret| {
            if (ret.value) |val| {
                try resolveReferences(val.*, ctx, scope_id);
            }
        },

        .expr_stmt => |expr| {
            try resolveReferences(expr.value.*, ctx, scope_id);
        },

        .for_stmt => |for_s| {
            try resolveReferences(for_s.iter.*, ctx, scope_id);
            for (for_s.body) |stmt| {
                try resolveReferences(stmt, ctx, scope_id);
            }
        },

        .while_stmt => |while_s| {
            try resolveReferences(while_s.condition.*, ctx, scope_id);
            for (while_s.body) |stmt| {
                try resolveReferences(stmt, ctx, scope_id);
            }
        },

        .if_stmt => |if_s| {
            try resolveReferences(if_s.condition.*, ctx, scope_id);
            for (if_s.body) |stmt| {
                try resolveReferences(stmt, ctx, scope_id);
            }
            // else_body may contain nested if (elif)
            for (if_s.else_body) |stmt| {
                try resolveReferences(stmt, ctx, scope_id);
            }
        },

        else => {},
    }
}

/// Look up variable in parent scopes
fn findInParentScopes(resolution: *VariableResolution, scope_id: ScopeId, var_name: []const u8) !?VariableInfo {
    const scope = resolution.getScope(scope_id) orelse return null;

    var current_parent = scope.parent_scope;
    while (current_parent) |parent_id| {
        const parent_scope = resolution.getScope(parent_id) orelse break;

        // Check if declared in parent
        if (parent_scope.variables.get(var_name)) |info| {
            return info;
        }

        // Check if captured from grandparent
        if (parent_scope.captured_from_parent.get(var_name)) |info| {
            return info;
        }

        current_parent = parent_scope.parent_scope;
    }

    return null;
}

// ============================================================================
// Nonlocal Variable Collection
// ============================================================================

/// Collect all `nonlocal` variable names from statements.
/// These variables reference the enclosing scope and should NOT be registered as local.
fn collectNonlocalVarsInStmts(stmts: []const ast.Node, nonlocals: *hashmap_helper.StringHashMap(void)) void {
    for (stmts) |stmt| {
        collectNonlocalVarsInNode(stmt, nonlocals);
    }
}

fn collectNonlocalVarsInNode(node: ast.Node, nonlocals: *hashmap_helper.StringHashMap(void)) void {
    switch (node) {
        .nonlocal_stmt => |n| {
            for (n.names) |name| {
                nonlocals.put(name, {}) catch {};
            }
        },
        // Recurse into compound statements (but NOT nested functions - they have their own scope)
        .if_stmt => |i| {
            for (i.body) |s| collectNonlocalVarsInNode(s, nonlocals);
            for (i.else_body) |s| collectNonlocalVarsInNode(s, nonlocals);
        },
        .for_stmt => |f| {
            for (f.body) |s| collectNonlocalVarsInNode(s, nonlocals);
            if (f.orelse_body) |ob| for (ob) |s| collectNonlocalVarsInNode(s, nonlocals);
        },
        .while_stmt => |w| {
            for (w.body) |s| collectNonlocalVarsInNode(s, nonlocals);
            if (w.orelse_body) |ob| for (ob) |s| collectNonlocalVarsInNode(s, nonlocals);
        },
        .try_stmt => |t| {
            for (t.body) |s| collectNonlocalVarsInNode(s, nonlocals);
            for (t.handlers) |h| for (h.body) |s| collectNonlocalVarsInNode(s, nonlocals);
            for (t.else_body) |s| collectNonlocalVarsInNode(s, nonlocals);
            for (t.finalbody) |s| collectNonlocalVarsInNode(s, nonlocals);
        },
        .with_stmt => |w| {
            for (w.body) |s| collectNonlocalVarsInNode(s, nonlocals);
        },
        .match_stmt => |m| {
            for (m.cases) |c| for (c.body) |s| collectNonlocalVarsInNode(s, nonlocals);
        },
        else => {},
    }
}

// ============================================================================
// Tests
// ============================================================================

test "basic variable resolution" {
    const allocator = std.testing.allocator;

    var resolution = VariableResolution.init(allocator);
    defer resolution.deinit();

    // Create module scope
    const module_scope = try resolution.createScope("module", null, .module);

    // Register a variable
    const x_info = try resolution.registerVariable(module_scope, "x", .{});

    // Verify unique name was generated
    try std.testing.expect(std.mem.startsWith(u8, x_info.zig_name, "__v_module_x_"));

    // Lookup should work
    const zig_name = resolution.getZigName(module_scope, "x");
    try std.testing.expect(zig_name != null);
    try std.testing.expectEqualStrings(x_info.zig_name, zig_name.?);
}

test "nested function variable resolution" {
    const allocator = std.testing.allocator;

    var resolution = VariableResolution.init(allocator);
    defer resolution.deinit();

    // Create scopes
    const module_scope = try resolution.createScope("module", null, .module);
    const outer_scope = try resolution.createScope("outer", module_scope, .function);
    const inner_scope = try resolution.createScope("inner", outer_scope, .function);

    // Register variables
    const outer_x = try resolution.registerVariable(outer_scope, "x", .{});
    const inner_x = try resolution.registerVariable(inner_scope, "x", .{}); // Shadow!

    // Verify different unique names
    try std.testing.expect(!std.mem.eql(u8, outer_x.zig_name, inner_x.zig_name));

    // Lookup should return correct scope's variable
    const outer_zig = resolution.getZigName(outer_scope, "x");
    const inner_zig = resolution.getZigName(inner_scope, "x");

    try std.testing.expectEqualStrings(outer_x.zig_name, outer_zig.?);
    try std.testing.expectEqualStrings(inner_x.zig_name, inner_zig.?);
}

test "capture resolution" {
    const allocator = std.testing.allocator;

    var resolution = VariableResolution.init(allocator);
    defer resolution.deinit();

    // Create scopes
    const outer_scope = try resolution.createScope("outer", null, .function);
    const inner_scope = try resolution.createScope("inner", outer_scope, .function);

    // Register in outer
    const outer_x = try resolution.registerVariable(outer_scope, "x", .{});

    // Capture in inner
    try resolution.registerCapture(inner_scope, "x", outer_x);

    // Inner should see outer's zig_name
    const inner_zig = resolution.getZigName(inner_scope, "x");
    try std.testing.expectEqualStrings(outer_x.zig_name, inner_zig.?);

    // Check capture flag
    try std.testing.expect(resolution.isCaptured(inner_scope, "x"));
    try std.testing.expect(!resolution.isDeclaredInScope(inner_scope, "x"));
}
