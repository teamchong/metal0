/// Core NativeCodegen struct and basic operations
const std = @import("std");
const ast = @import("../../../ast.zig");
const native_types = @import("../../../analysis/native_types.zig");
const NativeType = native_types.NativeType;
const TypeInferrer = native_types.TypeInferrer;
const SemanticInfo = @import("../../../analysis/types.zig").SemanticInfo;
const comptime_eval = @import("../../../analysis/comptime_eval.zig");
const symbol_table_mod = @import("../symbol_table.zig");
const SymbolTable = symbol_table_mod.SymbolTable;
const ClassRegistry = symbol_table_mod.ClassRegistry;
const MethodInfo = symbol_table_mod.MethodInfo;
const import_registry = @import("../import_registry.zig");

/// Error set for code generation
pub const CodegenError = error{
    OutOfMemory,
} || native_types.InferError;

/// Tracks a function with decorators for later application
pub const DecoratedFunction = struct {
    name: []const u8,
    decorators: []ast.Node,
};

pub const FromImportInfo = struct {
    module: []const u8,
    names: [][]const u8,
    asnames: []?[]const u8,
};

pub const NativeCodegen = struct {
    allocator: std.mem.Allocator,
    output: std.ArrayList(u8),
    type_inferrer: *TypeInferrer,
    semantic_info: *SemanticInfo,
    indent_level: usize,

    // Symbol table for scope-aware variable tracking
    symbol_table: *SymbolTable,

    // Class registry for inheritance support and method lookup
    class_registry: *ClassRegistry,

    // Counter for unique tuple unpacking temporary variables
    unpack_counter: usize,

    // Lambda support - counter for unique names, storage for lambda function definitions
    lambda_counter: usize,
    lambda_functions: std.ArrayList([]const u8),

    // Track which variables hold closures (for .call() generation)
    closure_vars: std.StringHashMap(void),

    // Track which variables are closure factories (return closures)
    closure_factories: std.StringHashMap(void),

    // Track which variables hold simple lambdas (function pointers)
    lambda_vars: std.StringHashMap(void),

    // Variable renames for exception handling (maps original name -> renamed name)
    var_renames: std.StringHashMap([]const u8),

    // Track which variables hold constant arrays (vs ArrayLists)
    array_vars: std.StringHashMap(void),

    // Track which variables hold array slices (result of slicing a constant array)
    array_slice_vars: std.StringHashMap(void),

    // Compile-time evaluator for constant folding
    comptime_evaluator: comptime_eval.ComptimeEvaluator,

    // C library import context (for numpy, etc.)
    import_ctx: ?*const @import("c_interop").ImportContext,

    // Track decorated functions for application in main()
    decorated_functions: std.ArrayList(DecoratedFunction),

    // Import registry for Python→Zig module mapping
    import_registry: *import_registry.ImportRegistry,

    // Track from-imports for symbol re-export generation
    from_imports: std.ArrayList(FromImportInfo),

    // Track from-imported functions that need allocator argument
    // Maps symbol name -> true (e.g., "loads" -> true)
    from_import_needs_allocator: std.StringHashMap(void),

    pub fn init(allocator: std.mem.Allocator, type_inferrer: *TypeInferrer, semantic_info: *SemanticInfo) !*NativeCodegen {
        const self = try allocator.create(NativeCodegen);

        // Create and initialize symbol table
        const sym_table = try allocator.create(SymbolTable);
        sym_table.* = SymbolTable.init(allocator);

        // Create and initialize class registry
        const cls_registry = try allocator.create(ClassRegistry);
        cls_registry.* = ClassRegistry.init(allocator);

        // Create and initialize import registry
        const registry = try allocator.create(import_registry.ImportRegistry);
        registry.* = try import_registry.createDefaultRegistry(allocator);

        self.* = .{
            .allocator = allocator,
            .output = std.ArrayList(u8){},
            .type_inferrer = type_inferrer,
            .semantic_info = semantic_info,
            .indent_level = 0,
            .symbol_table = sym_table,
            .class_registry = cls_registry,
            .unpack_counter = 0,
            .lambda_counter = 0,
            .lambda_functions = std.ArrayList([]const u8){},
            .closure_vars = std.StringHashMap(void).init(allocator),
            .closure_factories = std.StringHashMap(void).init(allocator),
            .lambda_vars = std.StringHashMap(void).init(allocator),
            .var_renames = std.StringHashMap([]const u8).init(allocator),
            .array_vars = std.StringHashMap(void).init(allocator),
            .array_slice_vars = std.StringHashMap(void).init(allocator),
            .comptime_evaluator = comptime_eval.ComptimeEvaluator.init(allocator),
            .import_ctx = null,
            .decorated_functions = std.ArrayList(DecoratedFunction){},
            .import_registry = registry,
            .from_imports = std.ArrayList(FromImportInfo){},
            .from_import_needs_allocator = std.StringHashMap(void).init(allocator),
        };
        return self;
    }

    pub fn setImportContext(self: *NativeCodegen, ctx: *const @import("c_interop").ImportContext) void {
        self.import_ctx = ctx;
    }

    pub fn deinit(self: *NativeCodegen) void {
        self.output.deinit(self.allocator);
        // Clean up symbol table and class registry
        self.symbol_table.deinit();
        self.allocator.destroy(self.symbol_table);
        self.class_registry.deinit();
        self.allocator.destroy(self.class_registry);
        // Clean up lambda functions
        for (self.lambda_functions.items) |lambda_code| {
            self.allocator.free(lambda_code);
        }
        self.lambda_functions.deinit(self.allocator);

        // Clean up closure tracking HashMaps (free keys)
        var closure_iter = self.closure_vars.keyIterator();
        while (closure_iter.next()) |key| {
            self.allocator.free(key.*);
        }
        self.closure_vars.deinit();

        var factory_iter = self.closure_factories.keyIterator();
        while (factory_iter.next()) |key| {
            self.allocator.free(key.*);
        }
        self.closure_factories.deinit();

        var lambda_iter = self.lambda_vars.keyIterator();
        while (lambda_iter.next()) |key| {
            self.allocator.free(key.*);
        }
        self.lambda_vars.deinit();

        // Clean up variable renames
        self.var_renames.deinit();

        // Clean up array vars tracking
        var array_iter = self.array_vars.keyIterator();
        while (array_iter.next()) |key| {
            self.allocator.free(key.*);
        }
        self.array_vars.deinit();

        // Clean up array slice vars tracking
        var slice_iter = self.array_slice_vars.keyIterator();
        while (slice_iter.next()) |key| {
            self.allocator.free(key.*);
        }
        self.array_slice_vars.deinit();

        // Clean up decorated functions tracking
        self.decorated_functions.deinit(self.allocator);

        // Clean up import registry
        self.import_registry.deinit();
        self.allocator.destroy(self.import_registry);

        self.allocator.destroy(self);
    }

    /// Push new scope (call when entering loop/function/block)
    pub fn pushScope(self: *NativeCodegen) !void {
        try self.symbol_table.pushScope();
    }

    /// Pop scope (call when exiting loop/function/block)
    pub fn popScope(self: *NativeCodegen) void {
        self.symbol_table.popScope();
    }

    /// Check if variable declared in any scope (innermost to outermost)
    pub fn isDeclared(self: *NativeCodegen, name: []const u8) bool {
        return self.symbol_table.lookup(name) != null;
    }

    /// Declare variable in current (innermost) scope
    pub fn declareVar(self: *NativeCodegen, name: []const u8) !void {
        // Use unknown type for now - type inference happens separately
        try self.symbol_table.declare(name, NativeType.int, true);
    }

    /// Check if variable holds a constant array (vs ArrayList)
    pub fn isArrayVar(self: *NativeCodegen, name: []const u8) bool {
        return self.array_vars.contains(name);
    }

    /// Check if variable holds an array slice (result of slicing constant array)
    pub fn isArraySliceVar(self: *NativeCodegen, name: []const u8) bool {
        return self.array_slice_vars.contains(name);
    }

    // Helper functions - public for use by statements.zig and expressions.zig
    pub fn emit(self: *NativeCodegen, s: []const u8) CodegenError!void {
        try self.output.appendSlice(self.allocator, s);
    }

    pub fn emitIndent(self: *NativeCodegen) CodegenError!void {
        var i: usize = 0;
        while (i < self.indent_level) : (i += 1) {
            try self.output.appendSlice(self.allocator, "    ");
        }
    }

    pub fn indent(self: *NativeCodegen) void {
        self.indent_level += 1;
    }

    pub fn dedent(self: *NativeCodegen) void {
        self.indent_level -= 1;
    }

    /// Convert NativeType to Zig type string for code generation
    /// Uses type inference results to get concrete types
    pub fn nativeTypeToZigType(self: *NativeCodegen, native_type: NativeType) ![]const u8 {
        var buf = std.ArrayList(u8){};
        try native_type.toZigType(self.allocator, &buf);
        return buf.toOwnedSlice(self.allocator);
    }

    /// Get the inferred type of a variable from type inference
    pub fn getVarType(self: *NativeCodegen, var_name: []const u8) ?NativeType {
        return self.type_inferrer.var_types.get(var_name);
    }

    /// Check if a class has a specific method (e.g., __getitem__, __len__)
    /// Used for magic method dispatch
    pub fn classHasMethod(self: *NativeCodegen, class_name: []const u8, method_name: []const u8) bool {
        return self.class_registry.hasMethod(class_name, method_name);
    }

    /// Get symbol's type from type inferrer
    pub fn getSymbolType(self: *NativeCodegen, name: []const u8) ?NativeType {
        return self.type_inferrer.var_types.get(name);
    }

    /// Find method in class (searches inheritance chain)
    pub fn findMethod(
        self: *NativeCodegen,
        class_name: []const u8,
        method_name: []const u8,
    ) ?MethodInfo {
        return self.class_registry.findMethod(class_name, method_name);
    }

    /// Get the class name from a variable's type
    /// Returns null if the variable is not an instance of a custom class
    fn getVarClassName(self: *NativeCodegen, expr: ast.Node) ?[]const u8 {
        // For name nodes, check if the variable was assigned from a class instantiation
        if (expr == .name) {
            // Try to track back to the class constructor call
            // For simplicity, look for pattern: var_name = ClassName()
            // This is a simplified heuristic - full implementation would need
            // full def-use chain analysis
            _ = self;
            return null; // Simplified for now
        }
        return null;
    }

    /// Check if a Python module should use Zig runtime
    pub fn useZigRuntime(self: *NativeCodegen, python_module: []const u8) bool {
        if (self.import_registry.lookup(python_module)) |info| {
            return info.strategy == .zig_runtime;
        }
        return false;
    }

    /// Check if a Python module uses C library
    pub fn usesCLibrary(self: *NativeCodegen, python_module: []const u8) bool {
        if (self.import_registry.lookup(python_module)) |info| {
            return info.strategy == .c_library;
        }
        return false;
    }

    /// Register a new Python→Zig mapping at runtime
    pub fn registerImport(
        self: *NativeCodegen,
        python_module: []const u8,
        strategy: import_registry.ImportStrategy,
        zig_import: ?[]const u8,
    ) !void {
        try self.import_registry.register(python_module, strategy, zig_import, null);
    }

    // Forward declaration for generateStmt (implemented in generator.zig)
    pub fn generateStmt(self: *NativeCodegen, node: ast.Node) CodegenError!void {
        const generator = @import("generator.zig");
        try generator.generateStmt(self, node);
    }

    // Forward declaration for genExpr (implemented in generator.zig)
    pub fn genExpr(self: *NativeCodegen, node: ast.Node) CodegenError!void {
        const generator = @import("generator.zig");
        try generator.genExpr(self, node);
    }

    // Forward declaration for generate (implemented in generator.zig)
    pub fn generate(self: *NativeCodegen, module: ast.Node.Module) ![]const u8 {
        const generator = @import("generator.zig");
        return generator.generate(self, module);
    }
};
