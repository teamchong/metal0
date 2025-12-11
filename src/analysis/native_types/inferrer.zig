const std = @import("std");
const ast = @import("analysis.ast");
const core = @import("core.zig");
const statements = @import("statements.zig");
const expressions = @import("expressions.zig");
const hashmap_helper = @import("utils.hashmap_helper");
const closures = @import("closures.zig");
const mutation_analyzer = @import("mutation_analyzer.zig");
const type_traits = @import("../traits/type_traits.zig");

pub const NativeType = core.NativeType;
pub const InferError = core.InferError;
pub const ClassInfo = core.ClassInfo;

const FnvHashMap = hashmap_helper.StringHashMap(NativeType);
const FnvClassMap = hashmap_helper.StringHashMap(ClassInfo);
const FnvArgsMap = hashmap_helper.StringHashMap([]const NativeType);

/// Common Python builtin function names (lowercase) - used to distinguish from class constructors
const CommonBuiltins = std.StaticStringMap(void).initComptime(.{
    // Core builtins that look like function calls
    .{ "print", {} }, .{ "len", {} }, .{ "range", {} }, .{ "str", {} },
    .{ "int", {} }, .{ "float", {} }, .{ "bool", {} }, .{ "list", {} },
    .{ "dict", {} }, .{ "set", {} }, .{ "tuple", {} }, .{ "type", {} },
    .{ "abs", {} }, .{ "min", {} }, .{ "max", {} }, .{ "sum", {} },
    .{ "any", {} }, .{ "all", {} }, .{ "zip", {} }, .{ "map", {} },
    .{ "filter", {} }, .{ "sorted", {} }, .{ "reversed", {} },
    .{ "enumerate", {} }, .{ "open", {} }, .{ "input", {} },
    .{ "repr", {} }, .{ "ord", {} }, .{ "chr", {} }, .{ "hex", {} },
    .{ "bin", {} }, .{ "oct", {} }, .{ "hash", {} }, .{ "id", {} },
    .{ "getattr", {} }, .{ "setattr", {} }, .{ "hasattr", {} }, .{ "delattr", {} },
    .{ "isinstance", {} }, .{ "issubclass", {} }, .{ "callable", {} },
    .{ "iter", {} }, .{ "next", {} }, .{ "super", {} }, .{ "object", {} },
    .{ "round", {} }, .{ "pow", {} }, .{ "divmod", {} }, .{ "format", {} },
    .{ "vars", {} }, .{ "dir", {} }, .{ "globals", {} }, .{ "locals", {} },
    .{ "eval", {} }, .{ "exec", {} }, .{ "compile", {} },
    .{ "bytes", {} }, .{ "bytearray", {} }, .{ "memoryview", {} },
    .{ "frozenset", {} }, .{ "slice", {} }, .{ "property", {} },
    .{ "staticmethod", {} }, .{ "classmethod", {} },
});

fn isCommonBuiltin(name: []const u8) bool {
    return CommonBuiltins.has(name);
}

/// ctypes function info for type inference
pub const CTypesFuncInfo = struct {
    library_var: []const u8, // Variable name holding CDLL (e.g., "libc")
    func_name: []const u8, // C function name (e.g., "strlen")
    argtypes: []const []const u8, // ctypes type names (e.g., ["c_char_p", "c_int"])
    restype: []const u8, // Return type (e.g., "c_size_t", "c_int")
};

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
    function_call_args: FnvArgsMap, // function_name -> call arg types (for regular functions)
    ctypes_functions: hashmap_helper.StringHashMap(CTypesFuncInfo), // ctypes function tracking
    from_imports: hashmap_helper.StringHashMap([]const u8), // from-import tracking: symbol -> module (e.g., "datetime" -> "datetime")

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
            .function_call_args = FnvArgsMap.init(allocator),
            .ctypes_functions = hashmap_helper.StringHashMap(CTypesFuncInfo).init(allocator),
            .from_imports = hashmap_helper.StringHashMap([]const u8).init(allocator),
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
        self.function_call_args.deinit();
        self.ctypes_functions.deinit();
        self.from_imports.deinit();

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

    /// Temporarily add a variable type for comprehension/block scope inference
    /// Returns the old type (if any) so caller can restore it after
    /// This does NOT use the scoped_var_types system - it's for temporary overrides during inference
    pub fn putTempVar(self: *TypeInferrer, name: []const u8, var_type: NativeType) !?NativeType {
        const old_type = self.var_types.get(name);
        try self.var_types.put(name, var_type);
        return old_type;
    }

    /// Restore a variable type after temporary override (or remove if old_type is null)
    pub fn restoreTempVar(self: *TypeInferrer, name: []const u8, old_type: ?NativeType) void {
        if (old_type) |old| {
            self.var_types.put(name, old) catch {};
        } else {
            _ = self.var_types.swapRemove(name);
        }
    }

    /// Widen a variable type in current scope (for reassignments)
    /// Special handling for dict types: when value types differ, widen to dict with pyvalue values
    pub fn widenScopedVar(self: *TypeInferrer, name: []const u8, new_type: NativeType) !void {
        const arena_alloc = self.arena.allocator();

        if (self.current_scope_name) |scope| {
            const scoped_key = try std.fmt.allocPrint(arena_alloc, "{s}:{s}", .{ scope, name });
            if (self.scoped_var_types.get(scoped_key)) |existing| {
                const widened = try self.widenDictAware(existing, new_type, arena_alloc);
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
                const widened = try self.widenDictAware(existing, new_type, arena_alloc);
                try self.var_types.put(name, widened);
            } else {
                try self.var_types.put(name, new_type);
            }
        }
    }

    /// Widen types with special handling for dicts
    /// When two dicts have different value types, create a dict with pyvalue values
    /// instead of falling back to .unknown
    fn widenDictAware(self: *TypeInferrer, existing: NativeType, new_type: NativeType, alloc: std.mem.Allocator) !NativeType {
        _ = self;

        // Check if both are dict types
        const existing_tag = @as(std.meta.Tag(NativeType), existing);
        const new_tag = @as(std.meta.Tag(NativeType), new_type);

        if (existing_tag == .dict and new_tag == .dict) {
            const existing_key = existing.dict.key.*;
            const new_key = new_type.dict.key.*;
            const existing_val = existing.dict.value.*;
            const new_val = new_type.dict.value.*;

            // If key types match but value types differ, widen to dict with pyvalue values
            const existing_key_tag = @as(std.meta.Tag(NativeType), existing_key);
            const new_key_tag = @as(std.meta.Tag(NativeType), new_key);
            const existing_val_tag = @as(std.meta.Tag(NativeType), existing_val);
            const new_val_tag = @as(std.meta.Tag(NativeType), new_val);

            if (existing_key_tag == new_key_tag and existing_val_tag != new_val_tag) {
                // Same key type, different value types -> use pyvalue for values
                const pyvalue_type = try alloc.create(NativeType);
                pyvalue_type.* = .pyvalue;
                return NativeType{ .dict = .{
                    .key = existing.dict.key, // Reuse existing key type
                    .value = pyvalue_type,
                } };
            }
        }

        // Fall back to standard widening for non-dict or compatible dict types
        return existing.widen(new_type);
    }

    /// Analyze a module to infer all variable types
    pub fn analyze(self: *TypeInferrer, module: ast.Node.Module) InferError!void {
        // Register __name__ as a string constant (for if __name__ == "__main__" support)
        try self.var_types.put("__name__", .{ .string = .literal });

        // Use arena allocator for closure analysis so captured_vars slices get freed with arena
        const arena_alloc = self.arena.allocator();

        // First pass: Collect from-imports (for type inference of calls like datetime(...))
        // Maps imported symbol name -> module name (e.g., "datetime" -> "datetime")
        for (module.body) |stmt| {
            if (stmt == .import_from) {
                const from_imp = stmt.import_from;
                for (from_imp.names, 0..) |name, i| {
                    // Use asname if provided, otherwise use the original name
                    const symbol_name = if (from_imp.asnames.len > i and from_imp.asnames[i] != null)
                        from_imp.asnames[i].?
                    else
                        name;
                    try self.from_imports.put(symbol_name, from_imp.module);
                }
            }
        }

        // Second pass: Analyze closures (detect captured variables)
        const body_mut = module.body;
        try closures.analyzeNestedFunctions(body_mut, null, arena_alloc);

        // Third pass: Register all function return types from annotations
        for (module.body) |stmt| {
            if (stmt == .function_def) {
                const func_def = stmt.function_def;
                const return_type = try core.pythonTypeHintToNative(func_def.return_type, arena_alloc);
                try self.func_return_types.put(func_def.name, return_type);
            }
        }

        // Fourth pass: Collect constructor call arg types (before processing class definitions)
        for (module.body) |stmt| {
            try self.collectConstructorArgs(stmt, arena_alloc);
        }

        // Fifth pass: Infer return types from return statements (for functions without annotations)
        // IMPORTANT: Must run BEFORE statement analysis so variable assignments from function calls
        // can look up the correct return type.
        // NOTE: We process nested functions first so that outer functions can resolve inner function calls.
        for (module.body) |stmt| {
            if (stmt == .function_def) {
                try self.inferFunctionReturnTypes(stmt.function_def);
            }
        }

        // Sixth pass: Analyze all statements (must run after return type inference)
        for (module.body) |stmt| {
            try self.visitStmt(stmt);
        }

        // Seventh pass: Promote array types to list types for mutated variables
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
            // Also infer element type from .append() calls for empty lists
            var var_iter = self.var_types.iterator();
            while (var_iter.next()) |entry| {
                const var_name = entry.key_ptr.*;
                const var_type = entry.value_ptr.*;

                if (var_type == .array) {
                    if (mutation_analyzer.hasListMutation(muts, var_name)) {
                        // Check if we can infer element type from append calls
                        var elem_type = var_type.array.element_type.*;
                        if (type_traits.isUnknown(elem_type)) {
                            // Empty list - try to infer element type from .append() args
                            if (mutation_analyzer.getAppendedNodes(muts, var_name)) |append_nodes| {
                                for (append_nodes) |node| {
                                    const inferred = self.inferExpr(node) catch .unknown;
                                    if (!type_traits.isUnknown(inferred)) {
                                        elem_type = inferred;
                                        break;
                                    }
                                }
                            }
                        }
                        // Promote array to list (ArrayList) with inferred element type
                        const elem_ptr = arena_alloc.create(NativeType) catch continue;
                        elem_ptr.* = elem_type;
                        entry.value_ptr.* = .{ .list = elem_ptr };
                    }
                }
                // Also handle lists with unknown element type
                else if (var_type == .list) {
                    if (type_traits.isUnknown(var_type.list.*)) {
                        // Empty list - try to infer element type from .append() args
                        if (mutation_analyzer.getAppendedNodes(muts, var_name)) |append_nodes| {
                            for (append_nodes) |node| {
                                const inferred = self.inferExpr(node) catch .unknown;
                                if (!type_traits.isUnknown(inferred)) {
                                    const elem_ptr = arena_alloc.create(NativeType) catch continue;
                                    elem_ptr.* = inferred;
                                    entry.value_ptr.* = .{ .list = elem_ptr };
                                    break;
                                }
                            }
                        }
                    }
                }
            }
        }

        // Eighth pass: Analyze closures that append to captured lists and infer element types from call sites
        // This handles patterns like:
        //   actual_calls = []
        //   def add_call(pos, value):
        //       actual_calls.append((pos, value))
        //   add_call('key', k)  # pos is string, value is u8
        const closure_appends = mutation_analyzer.analyzeClosureAppends(module, self.allocator) catch null;
        const call_sites = mutation_analyzer.analyzeCallSites(module, self.allocator) catch null;

        if (closure_appends != null and call_sites != null) {
            const caps = closure_appends.?;
            const sites = call_sites.?;
            defer {
                // Clean up closure_appends
                var caps_copy = caps;
                for (caps_copy.values()) |*list| {
                    list.deinit(self.allocator);
                }
                caps_copy.deinit();
                // Clean up call_sites
                var sites_copy = sites;
                for (sites_copy.values()) |*list| {
                    list.deinit(self.allocator);
                }
                sites_copy.deinit();
            }

            // For each list variable, check if closures append to it
            var var_iter2 = self.var_types.iterator();
            while (var_iter2.next()) |entry| {
                const var_name = entry.key_ptr.*;
                const var_type = entry.value_ptr.*;

                // Only process lists with unknown element type
                if (var_type != .list) continue;
                if (!type_traits.isUnknown(var_type.list.*)) continue;

                // Check if any closures append to this list
                if (mutation_analyzer.getClosureAppendsForList(caps, var_name)) |closure_infos| {
                    for (closure_infos) |closure_info| {
                        // Check call sites for this closure
                        if (mutation_analyzer.getCallSitesForFunc(sites, closure_info.func_name)) |call_args_list| {
                            // Use the first call site to infer parameter types
                            if (call_args_list.len > 0) {
                                const call_args = call_args_list[0];
                                // Build tuple element types from call site args mapped through append_tuple_indices
                                var tuple_elem_types: std.ArrayListUnmanaged(NativeType) = .{};
                                defer tuple_elem_types.deinit(self.allocator);

                                for (closure_info.append_tuple_indices) |param_idx| {
                                    if (param_idx < call_args.len) {
                                        var arg_type = self.inferExpr(call_args[param_idx]) catch .unknown;
                                        // If the argument is unknown and is a simple name, it might be a comprehension variable
                                        // In that case, fall back to i64/u8 (bounded int) for zip over strings
                                        if (type_traits.isUnknown(arg_type) and call_args[param_idx] == .name) {
                                            // Default to bounded int for comprehension variables (common case)
                                            arg_type = .{ .int = .bounded };
                                        }
                                        try tuple_elem_types.append(self.allocator, arg_type);
                                    }
                                }

                                // If we got tuple element types, create a tuple type
                                if (tuple_elem_types.items.len > 0) {
                                    // Copy tuple element types into arena allocator
                                    const elem_slice = arena_alloc.alloc(NativeType, tuple_elem_types.items.len) catch continue;
                                    for (tuple_elem_types.items, 0..) |elem_type, i| {
                                        elem_slice[i] = elem_type;
                                    }
                                    const tuple_type = NativeType{ .tuple = elem_slice };
                                    const list_elem_ptr = arena_alloc.create(NativeType) catch continue;
                                    list_elem_ptr.* = tuple_type;
                                    entry.value_ptr.* = .{ .list = list_elem_ptr };
                                    break;
                                }
                            }
                        }
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
                // Also scan dict/list comprehensions and literals for function calls
                if (assign.value.* == .dictcomp) {
                    const dc = assign.value.dictcomp;
                    // Set up temp vars for comprehension variables before collecting calls
                    var saved_types: [8]struct { name: []const u8, old_type: ?NativeType } = undefined;
                    var saved_count: usize = 0;
                    for (dc.generators) |gen| {
                        if (gen.target.* == .tuple or gen.target.* == .list) {
                            const target_elts = if (gen.target.* == .tuple) gen.target.tuple.elts else gen.target.list.elts;
                            // Handle zip() unpacking
                            if (gen.iter.* == .call and gen.iter.call.func.* == .name and
                                std.mem.eql(u8, gen.iter.call.func.name.id, "zip"))
                            {
                                for (gen.iter.call.args, 0..) |arg, idx| {
                                    if (idx < target_elts.len and target_elts[idx] == .name) {
                                        const t_var_name = target_elts[idx].name.id;
                                        // Infer element type from the zip argument
                                        const arg_type = expressions.inferExpr(arena_alloc, &self.var_types, &self.class_fields, &self.func_return_types, arg) catch .unknown;
                                        const elem_type: NativeType = switch (arg_type) {
                                            .list => |l| l.*,
                                            .array => |a| a.element_type.*,
                                            .string => .{ .int = .bounded },
                                            .bytes => .{ .int = .bounded },
                                            else => .unknown,
                                        };
                                        if (saved_count < saved_types.len) {
                                            saved_types[saved_count] = .{ .name = t_var_name, .old_type = self.putTempVar(t_var_name, elem_type) catch null };
                                            saved_count += 1;
                                        }
                                    }
                                }
                            }
                        }
                    }
                    defer {
                        for (saved_types[0..saved_count]) |saved| {
                            self.restoreTempVar(saved.name, saved.old_type);
                        }
                    }
                    try self.collectCallsFromExpr(dc.key.*, arena_alloc);
                    try self.collectCallsFromExpr(dc.value.*, arena_alloc);
                }
                if (assign.value.* == .listcomp) {
                    try self.collectCallsFromExpr(assign.value.listcomp.elt.*, arena_alloc);
                }
                if (assign.value.* == .genexp) {
                    try self.collectCallsFromExpr(assign.value.genexp.elt.*, arena_alloc);
                }
                // Dict literals: {key_expr: value_expr, ...}
                if (assign.value.* == .dict) {
                    for (assign.value.dict.keys) |key| {
                        try self.collectCallsFromExpr(key, arena_alloc);
                    }
                    for (assign.value.dict.values) |val| {
                        try self.collectCallsFromExpr(val, arena_alloc);
                    }
                }
                // List literals: [expr, ...]
                if (assign.value.* == .list) {
                    for (assign.value.list.elts) |elt| {
                        try self.collectCallsFromExpr(elt, arena_alloc);
                    }
                }
            },
            .expr_stmt => |expr| {
                // Check for standalone constructor calls
                if (expr.value.* == .call) {
                    try self.checkConstructorCall(expr.value.call, arena_alloc);
                }
            },
            .return_stmt => |ret| {
                // Check for return AbstractInstance(self)
                if (ret.value) |val| {
                    if (val.* == .call) {
                        try self.checkConstructorCall(val.call, arena_alloc);
                    }
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
            .class_def => |class_def| {
                // Set up 'self' as class_instance for method bodies
                const old_self = self.var_types.get("self");
                try self.var_types.put("self", .{ .class_instance = class_def.name });
                defer {
                    if (old_self) |os| {
                        self.var_types.put("self", os) catch {};
                    } else {
                        _ = self.var_types.swapRemove("self");
                    }
                }
                // Traverse all methods in the class
                for (class_def.body) |method_stmt| {
                    if (method_stmt == .function_def) {
                        for (method_stmt.function_def.body) |s| {
                            self.collectConstructorArgs(s, arena_alloc) catch {};
                        }
                    }
                }
            },
            else => {},
        }
    }

    /// Check if a call is a class constructor or function and store arg types
    fn checkConstructorCall(self: *TypeInferrer, call: ast.Node.Call, arena_alloc: std.mem.Allocator) InferError!void {
        if (call.func.* == .name) {
            const func_name = call.func.name.id;
            // Class names start with uppercase (Python convention)
            // Lowercase names are regular functions
            const is_likely_class = func_name.len > 0 and
                std.ascii.isUpper(func_name[0]) and
                !isCommonBuiltin(func_name);

            // Infer types of all arguments (positional + keyword)
            const total_args = call.args.len + call.keyword_args.len;
            if (total_args == 0) return; // No args to track

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

            // Store in appropriate map based on whether it looks like a class
            if (is_likely_class) {
                try self.class_constructor_args.put(func_name, arg_types);
            } else {
                // Regular function call - track for parameter type inference
                try self.function_call_args.put(func_name, arg_types);
            }

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
                // Store as "FuncName.param_name" -> type
                const key = try std.fmt.allocPrint(arena_alloc, "{s}.{s}", .{ func_name, kwarg.name });
                // Widen with existing type if present (use dict-aware widening)
                if (self.var_types.get(key)) |existing| {
                    const widened = try self.widenDictAware(existing, kwarg_type, arena_alloc);
                    try self.var_types.put(key, widened);
                } else {
                    try self.var_types.put(key, kwarg_type);
                }
            }
        }
    }

    /// Recursively collect function calls from an expression (for comprehensions)
    fn collectCallsFromExpr(self: *TypeInferrer, node: ast.Node, arena_alloc: std.mem.Allocator) InferError!void {
        switch (node) {
            .call => |call| {
                try self.checkConstructorCall(call, arena_alloc);
                // Also check arguments for nested calls
                for (call.args) |arg| {
                    try self.collectCallsFromExpr(arg, arena_alloc);
                }
            },
            .binop => |b| {
                try self.collectCallsFromExpr(b.left.*, arena_alloc);
                try self.collectCallsFromExpr(b.right.*, arena_alloc);
            },
            .unaryop => |u| {
                try self.collectCallsFromExpr(u.operand.*, arena_alloc);
            },
            .if_expr => |ie| {
                try self.collectCallsFromExpr(ie.body.*, arena_alloc);
                try self.collectCallsFromExpr(ie.orelse_value.*, arena_alloc);
                try self.collectCallsFromExpr(ie.condition.*, arena_alloc);
            },
            .subscript => |s| {
                try self.collectCallsFromExpr(s.value.*, arena_alloc);
            },
            .attribute => |a| {
                try self.collectCallsFromExpr(a.value.*, arena_alloc);
            },
            else => {},
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
        return expressions.inferExprWithInferrer(
            arena_alloc,
            &self.var_types,
            &self.class_fields,
            &self.func_return_types,
            node,
            self, // Pass TypeInferrer for ctypes tracking
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
        for (func_def.args, 0..) |arg, param_idx| {
            var param_type = try core.pythonTypeHintToNative(arg.type_annotation, arena_alloc);
            // If no type annotation, check call site types from function_call_args
            if (type_traits.isUnknown(param_type)) {
                if (self.function_call_args.get(func_def.name)) |call_arg_types| {
                    if (param_idx < call_arg_types.len) {
                        const call_type = call_arg_types[param_idx];
                        // Use call site type if it's not unknown
                        if (!type_traits.isUnknown(call_type)) {
                            param_type = call_type;
                        }
                    }
                }
            }
            // Default to int if still unknown (most common Python numeric type)
            if (type_traits.isUnknown(param_type)) {
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
        if (type_traits.isUnknown(current_type)) {
            // Find return statement in function body (recursively including match statements)
            if (try self.findReturnTypeInBody(func_def.body)) |inferred_type| {
                try self.func_return_types.put(func_def.name, inferred_type);
            }
        }
    }

    /// Recursively find the first return statement in a body and infer its type
    fn findReturnTypeInBody(self: *TypeInferrer, body: []const ast.Node) InferError!?NativeType {
        for (body) |stmt| {
            if (stmt == .return_stmt and stmt.return_stmt.value != null) {
                return try self.inferExpr(stmt.return_stmt.value.?.*);
            }
            // Check nested statements
            if (stmt == .if_stmt) {
                if (try self.findReturnTypeInBody(stmt.if_stmt.body)) |t| return t;
                if (try self.findReturnTypeInBody(stmt.if_stmt.else_body)) |t| return t;
            }
            if (stmt == .while_stmt) {
                if (try self.findReturnTypeInBody(stmt.while_stmt.body)) |t| return t;
            }
            if (stmt == .for_stmt) {
                if (try self.findReturnTypeInBody(stmt.for_stmt.body)) |t| return t;
            }
            if (stmt == .match_stmt) {
                for (stmt.match_stmt.cases) |case| {
                    if (try self.findReturnTypeInBody(case.body)) |t| return t;
                }
            }
            if (stmt == .try_stmt) {
                if (try self.findReturnTypeInBody(stmt.try_stmt.body)) |t| return t;
                for (stmt.try_stmt.handlers) |handler| {
                    if (try self.findReturnTypeInBody(handler.body)) |t| return t;
                }
            }
        }
        return null;
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
