const std = @import("std");
const ast = @import("../../ast.zig");
const core = @import("core.zig");
const statements = @import("statements.zig");
const expressions = @import("expressions.zig");
const fnv_hash = @import("../../utils/fnv_hash.zig");
const closures = @import("closures.zig");

pub const NativeType = core.NativeType;
pub const InferError = core.InferError;
pub const ClassInfo = core.ClassInfo;

const FnvContext = fnv_hash.FnvHashContext([]const u8);
const FnvHashMap = std.HashMap([]const u8, NativeType, FnvContext, 80);
const FnvClassMap = std.HashMap([]const u8, ClassInfo, FnvContext, 80);
const FnvArgsMap = std.HashMap([]const u8, []const NativeType, FnvContext, 80);

/// Type inferrer - analyzes AST to determine native Zig types
pub const TypeInferrer = struct {
    allocator: std.mem.Allocator,
    arena: *std.heap.ArenaAllocator, // Heap-allocated arena for type allocations
    var_types: FnvHashMap,
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
            .class_fields = FnvClassMap.init(allocator),
            .func_return_types = FnvHashMap.init(allocator),
            .class_constructor_args = FnvArgsMap.init(allocator),
        };
    }

    pub fn deinit(self: *TypeInferrer) void {
        // Free class field and method maps
        var it = self.class_fields.iterator();
        while (it.next()) |entry| {
            entry.value_ptr.fields.deinit();
            entry.value_ptr.methods.deinit();
        }
        self.class_fields.deinit();
        self.var_types.deinit();
        self.func_return_types.deinit();
        self.class_constructor_args.deinit();

        // Free arena and all type allocations
        const alloc = self.allocator;
        self.arena.deinit();
        alloc.destroy(self.arena);
    }

    /// Analyze a module to infer all variable types
    pub fn analyze(self: *TypeInferrer, module: ast.Node.Module) InferError!void {
        // Register __name__ as a string constant (for if __name__ == "__main__" support)
        try self.var_types.put("__name__", .{ .string = .literal });

        // First pass: Analyze closures (detect captured variables)
        const body_mut = module.body;
        try closures.analyzeNestedFunctions(body_mut, null, self.allocator);

        // Second pass: Register all function return types from annotations
        const arena_alloc = self.arena.allocator();
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

        // Fourth pass: Analyze all statements
        for (module.body) |stmt| {
            try self.visitStmt(stmt);
        }

        // Fifth pass: Infer return types from return statements (for functions without annotations)
        for (module.body) |stmt| {
            if (stmt == .function_def) {
                const func_def = stmt.function_def;
                const current_type = self.func_return_types.get(func_def.name) orelse .unknown;

                // Only infer if no annotation was provided (type is .int default)
                if (current_type == .int or current_type == .unknown) {
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
                // Infer types of constructor arguments
                const arg_types = try arena_alloc.alloc(NativeType, call.args.len);
                for (call.args, 0..) |arg, i| {
                    arg_types[i] = try expressions.inferExpr(
                        arena_alloc,
                        &self.var_types,
                        &self.class_fields,
                        &self.func_return_types,
                        arg,
                    );
                }
                try self.class_constructor_args.put(func_name, arg_types);
            }
        }
    }

    /// Visit and analyze a statement node
    fn visitStmt(self: *TypeInferrer, node: ast.Node) InferError!void {
        // Use arena allocator for type allocations
        const arena_alloc = self.arena.allocator();
        try statements.visitStmt(
            arena_alloc,
            &self.var_types,
            &self.class_fields,
            &self.func_return_types,
            &self.class_constructor_args,
            &inferExprWrapper,
            node,
        );
    }

    /// Infer the native type of an expression node
    pub fn inferExpr(self: *TypeInferrer, node: ast.Node) InferError!NativeType {
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
