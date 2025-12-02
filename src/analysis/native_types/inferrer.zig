const std = @import("std");
const ast = @import("ast");
const core = @import("core.zig");
const statements = @import("statements.zig");
const expressions = @import("expressions.zig");
const hashmap_helper = @import("hashmap_helper");
const closures = @import("closures.zig");
const mutation_analyzer = @import("mutation_analyzer.zig");

pub const NativeType = core.NativeType;
pub const InferError = core.InferError;
pub const ClassInfo = core.ClassInfo;

const FnvHashMap = hashmap_helper.StringHashMap(NativeType);
const FnvClassMap = hashmap_helper.StringHashMap(ClassInfo);
const FnvArgsMap = hashmap_helper.StringHashMap([]const NativeType);

/// Type inferrer - analyzes AST to determine native Zig types
pub const TypeInferrer = struct {
    allocator: std.mem.Allocator,
    arena: *std.heap.ArenaAllocator, // Heap-allocated arena for type allocations
    var_types: FnvHashMap, // Legacy: global var types (still needed for some lookups)
    scoped_var_types: FnvHashMap, // Function-scoped variable types (key: "class.method:varname" or "func:varname")
    current_scope_name: ?[]const u8, // Current function/method scope name (null = global)
    class_fields: FnvClassMap, // class_name -> field types
    func_return_types: FnvHashMap, // function_name -> return type
    class_constructor_args: FnvArgsMap, // class_name -> constructor arg types

    pub fn init(allocator: std.mem.Allocator) InferError!TypeInferrer {
        // Allocate arena on heap to avoid copy issues
        const arena = try allocator.create(std.heap.ArenaAllocator);
        arena.* = std.heap.ArenaAllocator.init(allocator);

        return TypeInferrer{
            .allocator = allocator,
            .arena = arena,
            .var_types = FnvHashMap.init(allocator),
            .scoped_var_types = FnvHashMap.init(allocator),
            .current_scope_name = null,
            .class_fields = FnvClassMap.init(allocator),
            .func_return_types = FnvHashMap.init(allocator),
            .class_constructor_args = FnvArgsMap.init(allocator),
        };
    }

    pub fn deinit(self: *TypeInferrer) void {
        // Free class field and method maps
        for (self.class_fields.values()) |*entry| {
            entry.fields.deinit();
            entry.methods.deinit();
            entry.property_methods.deinit();
            entry.property_getters.deinit();
        }
        self.class_fields.deinit();
        self.var_types.deinit();
        self.scoped_var_types.deinit();
        self.func_return_types.deinit();
        self.class_constructor_args.deinit();

        // Free arena and all type allocations
        const alloc = self.allocator;
        self.arena.deinit();
        alloc.destroy(self.arena);
    }

    /// Enter a named scope (returns old scope name for restoration)
    pub fn enterScope(self: *TypeInferrer, scope_name: []const u8) ?[]const u8 {
        const old = self.current_scope_name;
        self.current_scope_name = scope_name;
        return old;
    }

    /// Exit named scope and restore previous
    pub fn exitScope(self: *TypeInferrer, old_scope: ?[]const u8) void {
        self.current_scope_name = old_scope;
    }

    /// Legacy compatibility shims (for statements.zig that uses old interface)
    pub fn pushScope(_: *TypeInferrer) u32 {
        return 0;
    }
    pub fn popScope(_: *TypeInferrer, _: u32) void {}

    /// Put a variable type in the current scope
    pub fn putScopedVar(self: *TypeInferrer, name: []const u8, var_type: NativeType) !void {
        if (self.current_scope_name) |scope| {
            // Create scoped key: "scope_name:var_name"
            const scoped_key = try std.fmt.allocPrint(self.arena.allocator(), "{s}:{s}", .{ scope, name });
            try self.scoped_var_types.put(scoped_key, var_type);
        }
        // Also update legacy var_types for compatibility
        try self.var_types.put(name, var_type);
    }

    /// Get a variable type from current scope (does NOT fall back to other scopes)
    pub fn getScopedVar(self: *TypeInferrer, name: []const u8) ?NativeType {
        if (self.current_scope_name) |scope| {
            // Create scoped key for current scope
            const scoped_key = std.fmt.allocPrint(self.arena.allocator(), "{s}:{s}", .{ scope, name }) catch return null;
            if (self.scoped_var_types.get(scoped_key)) |var_type| {
                return var_type;
            }
        }
        return null;
    }

    /// Widen a variable type in current scope (for reassignments)
    pub fn widenScopedVar(self: *TypeInferrer, name: []const u8, new_type: NativeType) !void {
        if (self.current_scope_name) |scope| {
            const scoped_key = try std.fmt.allocPrint(self.arena.allocator(), "{s}:{s}", .{ scope, name });
            if (self.scoped_var_types.get(scoped_key)) |existing| {
                const widened = existing.widen(new_type);
                try self.scoped_var_types.put(scoped_key, widened);
                // Also update legacy var_types
                try self.var_types.put(name, widened);
            } else {
                // First assignment in this scope
                try self.putScopedVar(name, new_type);
            }
        } else {
            // Global scope - use legacy var_types with widening
            if (self.var_types.get(name)) |existing| {
                const widened = existing.widen(new_type);
                try self.var_types.put(name, widened);
            } else {
                try self.var_types.put(name, new_type);
            }
        }
    }

    /// Analyze a module to infer all variable types
    pub fn analyze(self: *TypeInferrer, module: ast.Node.Module) InferError!void {
        // Register __name__ as a string constant (for if __name__ == "__main__" support)
        try self.var_types.put("__name__", .{ .string = .literal });

        // Use arena allocator for closure analysis so captured_vars slices get freed with arena
        const arena_alloc = self.arena.allocator();

        // First pass: Analyze closures (detect captured variables)
        const body_mut = module.body;
        try closures.analyzeNestedFunctions(body_mut, null, arena_alloc);

        // Second pass: Register all function return types from annotations
        for (module.body) |stmt| {
            if (stmt == .function_def) {
                const func_def = stmt.function_def;
                const return_type = try core.pythonTypeHintToNative(func_def.return_type, arena_alloc);
                try self.func_return_types.put(func_def.name, return_type);
            }
        }

        // Third pass: Collect constructor call arg types (before processing class definitions)
        for (module.body) |stmt| {
            try self.collectConstructorArgs(stmt, arena_alloc);
        }

        // Fourth pass: Infer return types from return statements (for functions without annotations)
        // IMPORTANT: Must run BEFORE statement analysis so variable assignments from function calls
        // can look up the correct return type.
        // NOTE: We process nested functions first so that outer functions can resolve inner function calls.
        for (module.body) |stmt| {
            if (stmt == .function_def) {
                try self.inferFunctionReturnTypes(stmt.function_def);
            }
        }

        // Fifth pass: Analyze all statements (must run after return type inference)
        for (module.body) |stmt| {
            try self.visitStmt(stmt);
        }

        // Sixth pass: Promote array types to list types for mutated variables
        // This ensures list literals assigned to variables that later have methods
        // like .sort(), .append(), etc. called on them become ArrayLists
        const mutations = mutation_analyzer.analyzeMutations(module, self.allocator) catch null;
        if (mutations) |muts| {
            defer {
                var mut_copy = muts;
                for (mut_copy.values()) |*info| {
                    @constCast(info).mutation_types.deinit(self.allocator);
                }
                mut_copy.deinit();
            }

            // Check each variable - if it's an array and has list mutations, promote to list
            var var_iter = self.var_types.iterator();
            while (var_iter.next()) |entry| {
                const var_name = entry.key_ptr.*;
                const var_type = entry.value_ptr.*;

                if (var_type == .array) {
                    if (mutation_analyzer.hasListMutation(muts, var_name)) {
                        // Promote array to list (ArrayList)
                        entry.value_ptr.* = .{ .list = var_type.array.element_type };
                    }
                }
            }
        }
    }

    /// Collect constructor call argument types from a statement (recursive)
    fn collectConstructorArgs(self: *TypeInferrer, node: ast.Node, arena_alloc: std.mem.Allocator) InferError!void {
        switch (node) {
            .assign => |assign| {
                // Check if value is a class constructor call: g = Greeter("World")
                if (assign.value.* == .call) {
                    try self.checkConstructorCall(assign.value.call, arena_alloc);
                }
            },
            .expr_stmt => |expr| {
                // Check for standalone constructor calls
                if (expr.value.* == .call) {
                    try self.checkConstructorCall(expr.value.call, arena_alloc);
                }
            },
            .if_stmt => |if_stmt| {
                for (if_stmt.body) |s| try self.collectConstructorArgs(s, arena_alloc);
                for (if_stmt.else_body) |s| try self.collectConstructorArgs(s, arena_alloc);
            },
            .while_stmt => |while_stmt| {
                for (while_stmt.body) |s| try self.collectConstructorArgs(s, arena_alloc);
            },
            .for_stmt => |for_stmt| {
                for (for_stmt.body) |s| try self.collectConstructorArgs(s, arena_alloc);
            },
            .function_def => |func_def| {
                for (func_def.body) |s| try self.collectConstructorArgs(s, arena_alloc);
            },
            else => {},
        }
    }

    /// Check if a call is a class constructor and store arg types
    fn checkConstructorCall(self: *TypeInferrer, call: ast.Node.Call, arena_alloc: std.mem.Allocator) InferError!void {
        if (call.func.* == .name) {
            const func_name = call.func.name.id;
            // Class names start with uppercase
            if (func_name.len > 0 and std.ascii.isUpper(func_name[0])) {
                // Infer types of all arguments (positional + keyword)
                const total_args = call.args.len + call.keyword_args.len;
                const arg_types = try arena_alloc.alloc(NativeType, total_args);

                // Positional args first
                for (call.args, 0..) |arg, i| {
                    arg_types[i] = try expressions.inferExpr(
                        arena_alloc,
                        &self.var_types,
                        &self.class_fields,
                        &self.func_return_types,
                        arg,
                    );
                }

                // Keyword args after positional
                for (call.keyword_args, 0..) |kwarg, i| {
                    arg_types[call.args.len + i] = try expressions.inferExpr(
                        arena_alloc,
                        &self.var_types,
                        &self.class_fields,
                        &self.func_return_types,
                        kwarg.value,
                    );
                }

                try self.class_constructor_args.put(func_name, arg_types);

                // Also store keyword arg name -> type mapping for name-based lookup
                // Widen types if there are multiple calls with different types
                for (call.keyword_args) |kwarg| {
                    const kwarg_type = try expressions.inferExpr(
                        arena_alloc,
                        &self.var_types,
                        &self.class_fields,
                        &self.func_return_types,
                        kwarg.value,
                    );
                    // Store as "ClassName.param_name" -> type
                    const key = try std.fmt.allocPrint(arena_alloc, "{s}.{s}", .{ func_name, kwarg.name });
                    // Widen with existing type if present
                    if (self.var_types.get(key)) |existing| {
                        const widened = existing.widen(kwarg_type);
                        try self.var_types.put(key, widened);
                    } else {
                        try self.var_types.put(key, kwarg_type);
                    }
                }
            }
        }
    }

    /// Visit and analyze a statement node with scoped variable tracking
    fn visitStmt(self: *TypeInferrer, node: ast.Node) InferError!void {
        // Use arena allocator for type allocations
        const arena_alloc = self.arena.allocator();
        // Pass self to enable scoped variable tracking
        try statements.visitStmtScoped(
            arena_alloc,
            &self.var_types,
            &self.class_fields,
            &self.func_return_types,
            &self.class_constructor_args,
            &inferExprWrapper,
            node,
            self, // Pass type inferrer for scoped tracking
        );
    }

    /// Infer the native type of an expression node
    pub fn inferExpr(self: *TypeInferrer, node: ast.Node) InferError!NativeType {
        // For name nodes, check scoped variable types first
        // This ensures function-local variables shadow global ones correctly
        if (node == .name) {
            if (self.getScopedVar(node.name.id)) |scoped_type| {
                return scoped_type;
            }
        }

        // Use arena allocator for type allocations
        const arena_alloc = self.arena.allocator();
        return expressions.inferExpr(
            arena_alloc,
            &self.var_types,
            &self.class_fields,
            &self.func_return_types,
            node,
        );
    }

    /// Recursively infer return types for a function and its nested functions.
    /// Nested functions are processed first so outer functions can resolve inner function calls.
    fn inferFunctionReturnTypes(self: *TypeInferrer, func_def: ast.Node.FunctionDef) InferError!void {
        const arena_alloc = self.arena.allocator();

        // Enter named scope for this function
        const old_scope = self.enterScope(func_def.name);
        defer self.exitScope(old_scope);

        // Register function parameters in scoped var_types
        for (func_def.args) |arg| {
            var param_type = try core.pythonTypeHintToNative(arg.type_annotation, arena_alloc);
            // Default to int if no type annotation (most common Python numeric type)
            if (param_type == .unknown) {
                param_type = .{ .int = .bounded };
            }
            try self.putScopedVar(arg.name, param_type);
        }

        // Visit function body to register local variables BEFORE inferring return types
        // This ensures variables like `result` in `return result` are known
        for (func_def.body) |body_stmt| {
            try self.visitStmt(body_stmt);
        }

        // Process nested functions in the body (they can now access outer parameters)
        for (func_def.body) |body_stmt| {
            if (body_stmt == .function_def) {
                try self.inferFunctionReturnTypes(body_stmt.function_def);
            }
        }

        // Now infer this function's return type (nested functions are already registered)
        const current_type = self.func_return_types.get(func_def.name) orelse .unknown;

        // Only infer if no annotation was provided (type is unknown)
        if (current_type == .unknown) {
            // Find return statement in function body
            for (func_def.body) |body_stmt| {
                if (body_stmt == .return_stmt and body_stmt.return_stmt.value != null) {
                    const return_value = body_stmt.return_stmt.value.?.*;
                    const inferred_type = try self.inferExpr(return_value);
                    try self.func_return_types.put(func_def.name, inferred_type);
                    break;
                }
            }
        }
    }
};

/// Wrapper function to adapt expressions.inferExpr signature for statements module
fn inferExprWrapper(
    allocator: std.mem.Allocator,
    var_types: *FnvHashMap,
    class_fields: *FnvClassMap,
    func_return_types: *FnvHashMap,
    node: ast.Node,
) InferError!NativeType {
    return expressions.inferExpr(
        allocator,
        var_types,
        class_fields,
        func_return_types,
        node,
    );
}
