/// Core NativeCodegen struct and basic operations
const std = @import("std");
const ast = @import("ast");
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
const fnv_hash = @import("fnv_hash");
const cleanup = @import("cleanup.zig");

const hashmap_helper = @import("hashmap_helper");
const FnvVoidMap = hashmap_helper.StringHashMap(void);
const FnvStringMap = hashmap_helper.StringHashMap([]const u8);
const FnvFuncDefMap = hashmap_helper.StringHashMap(ast.Node.FunctionDef);

// Function signature info for default parameter handling
const FuncSignature = struct {
    total_params: usize,
    required_params: usize, // params without defaults
};
const FnvFuncSigMap = hashmap_helper.StringHashMap(FuncSignature);

/// Info about a single test method
pub const TestMethodInfo = struct {
    name: []const u8,
    skip_reason: ?[]const u8 = null, // null = not skipped, otherwise the reason
    needs_allocator: bool = false, // true if method needs allocator param (has fallible ops)
};

/// Unittest TestCase class info
pub const TestClassInfo = struct {
    class_name: []const u8,
    test_methods: []const TestMethodInfo,
    has_setUp: bool = false,
    has_tearDown: bool = false,
    has_setup_class: bool = false,
    has_teardown_class: bool = false,
};

/// Code generation mode
pub const CodegenMode = enum {
    script, // Has main(), runs directly
    module, // Exports functions, no main()
};

/// Error set for code generation
pub const CodegenError = error{
    OutOfMemory,
    UnsupportedModule,
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

    // Codegen mode (script vs module)
    mode: CodegenMode,

    // Module name (for module mode)
    module_name: ?[]const u8,

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
    closure_vars: FnvVoidMap,

    // Track which variables are closure factories (return closures)
    closure_factories: FnvVoidMap,

    // Track which variables hold simple lambdas (function pointers)
    lambda_vars: FnvVoidMap,

    // Variable renames for exception handling (maps original name -> renamed name)
    var_renames: FnvStringMap,

    // Track variables hoisted from try blocks (to skip declaration in assignment)
    hoisted_vars: FnvVoidMap,

    // Track which variables hold constant arrays (vs ArrayLists)
    array_vars: FnvVoidMap,

    // Track which variables hold array slices (result of slicing a constant array)
    array_slice_vars: FnvVoidMap,

    // Track ArrayList variables (for len() -> .items.len)
    arraylist_vars: FnvVoidMap,

    // Track which classes have mutating methods (need var instances, not const)
    mutable_classes: FnvVoidMap,

    // Track unittest TestCase classes and their test methods
    unittest_classes: std.ArrayList(TestClassInfo),

    // Compile-time evaluator for constant folding
    comptime_evaluator: comptime_eval.ComptimeEvaluator,

    // C library import context (for numpy, etc.)
    import_ctx: ?*const @import("c_interop").ImportContext,

    // Source file path (for resolving relative imports)
    source_file_path: ?[]const u8,

    // Track decorated functions for application in main()
    decorated_functions: std.ArrayList(DecoratedFunction),

    // Import registry for Python→Zig module mapping
    import_registry: *import_registry.ImportRegistry,

    // Track from-imports for symbol re-export generation
    from_imports: std.ArrayList(FromImportInfo),

    // Track from-imported functions that need allocator argument
    // Maps symbol name -> true (e.g., "loads" -> true)
    from_import_needs_allocator: FnvVoidMap,

    // Track which user-defined functions need allocator parameter
    // Maps function name -> void (e.g., "greet" -> {})
    functions_needing_allocator: FnvVoidMap,

    // Track async functions (for calling with _async suffix)
    // Maps function name -> void (e.g., "fetch_data" -> {})
    async_functions: FnvVoidMap,

    // Track async function definitions (for complexity analysis)
    // Maps function name -> FunctionDef (e.g., "fetch_data" -> FunctionDef)
    async_function_defs: FnvFuncDefMap,

    // Track functions with varargs (*args)
    // Maps function name -> void (e.g., "func" -> {})
    vararg_functions: FnvVoidMap,

    // Track vararg parameter names (*args parameters)
    // Maps parameter name -> void (e.g., "args" -> {})
    // Used for type inference: iterating over vararg gives i64
    vararg_params: FnvVoidMap,

    // Track functions with kwargs (**kwargs)
    // Maps function name -> void (e.g., "func" -> {})
    kwarg_functions: FnvVoidMap,

    // Track kwarg parameter names (**kwargs parameters)
    // Maps parameter name -> void (e.g., "kwargs" -> {})
    // Used for type inference: len(kwargs) -> runtime.PyDict.len()
    kwarg_params: FnvVoidMap,

    // Track function signatures (param counts for default handling)
    // Maps function name -> FuncSignature (e.g., "foo" -> {total: 2, required: 1})
    function_signatures: FnvFuncSigMap,

    // Track imported module names (for mymath.add() -> needs allocator)
    // Maps module name -> void (e.g., "mymath" -> {})
    imported_modules: FnvVoidMap,

    // Track variable mutations (for list ArrayList vs fixed array decision)
    // Maps variable name -> mutation info
    mutation_info: ?*const @import("../../../analysis/native_types/mutation_analyzer.zig").MutationMap,

    // Track C libraries needed for linking (from C extension imports)
    c_libraries: std.ArrayList([]const u8),

    // Track comptime eval() calls (string literal arguments that can be compiled at comptime)
    // Maps source code string -> void (e.g., "1 + 2" -> {})
    comptime_evals: FnvVoidMap,

    // Track function-local mutated variables (populated before genFunctionBody)
    // Maps variable name -> void for variables that are reassigned within current function
    func_local_mutations: FnvVoidMap,

    // Track variables declared as 'global' in current function scope
    // Maps variable name -> void for variables that reference outer (module) scope
    global_vars: FnvVoidMap,

    // Current class being generated (for super() support)
    // Set during class method generation, null otherwise
    current_class_name: ?[]const u8,

    // Current function being generated (for tail-call optimization)
    // Set during function generation, null otherwise
    current_function_name: ?[]const u8,

    // Track skipped modules (external modules not found in registry)
    // Maps module name -> void (e.g., "pytest" -> {})
    // Used to skip code that references these modules
    skipped_modules: FnvVoidMap,

    // Track skipped functions (functions that reference skipped modules)
    // Maps function name -> void (e.g., "run_code" -> {})
    // Used to skip calls to functions that weren't generated
    skipped_functions: FnvVoidMap,

    // Track local variable types within current function/method scope
    // Maps variable name -> NativeType (e.g., "result" -> .string)
    // Cleared when entering a new function scope, used to avoid type shadowing issues
    local_var_types: hashmap_helper.StringHashMap(NativeType),

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
            .mode = .script,
            .module_name = null,
            .symbol_table = sym_table,
            .class_registry = cls_registry,
            .unpack_counter = 0,
            .lambda_counter = 0,
            .lambda_functions = std.ArrayList([]const u8){},
            .closure_vars = FnvVoidMap.init(allocator),
            .closure_factories = FnvVoidMap.init(allocator),
            .lambda_vars = FnvVoidMap.init(allocator),
            .var_renames = FnvStringMap.init(allocator),
            .hoisted_vars = FnvVoidMap.init(allocator),
            .array_vars = FnvVoidMap.init(allocator),
            .array_slice_vars = FnvVoidMap.init(allocator),
            .arraylist_vars = FnvVoidMap.init(allocator),
            .mutable_classes = FnvVoidMap.init(allocator),
            .unittest_classes = std.ArrayList(TestClassInfo){},
            .comptime_evaluator = comptime_eval.ComptimeEvaluator.init(allocator),
            .import_ctx = null,
            .source_file_path = null,
            .decorated_functions = std.ArrayList(DecoratedFunction){},
            .import_registry = registry,
            .from_imports = std.ArrayList(FromImportInfo){},
            .from_import_needs_allocator = FnvVoidMap.init(allocator),
            .functions_needing_allocator = FnvVoidMap.init(allocator),
            .async_functions = FnvVoidMap.init(allocator),
            .async_function_defs = FnvFuncDefMap.init(allocator),
            .vararg_functions = FnvVoidMap.init(allocator),
            .vararg_params = FnvVoidMap.init(allocator),
            .kwarg_functions = FnvVoidMap.init(allocator),
            .kwarg_params = FnvVoidMap.init(allocator),
            .function_signatures = FnvFuncSigMap.init(allocator),
            .imported_modules = FnvVoidMap.init(allocator),
            .mutation_info = null,
            .c_libraries = std.ArrayList([]const u8){},
            .comptime_evals = FnvVoidMap.init(allocator),
            .func_local_mutations = FnvVoidMap.init(allocator),
            .global_vars = FnvVoidMap.init(allocator),
            .current_class_name = null,
            .current_function_name = null,
            .skipped_modules = FnvVoidMap.init(allocator),
            .skipped_functions = FnvVoidMap.init(allocator),
            .local_var_types = hashmap_helper.StringHashMap(NativeType).init(allocator),
        };
        return self;
    }

    pub fn setImportContext(self: *NativeCodegen, ctx: *const @import("c_interop").ImportContext) void {
        self.import_ctx = ctx;
    }

    pub fn setSourceFilePath(self: *NativeCodegen, path: []const u8) void {
        self.source_file_path = path;
    }

    pub fn deinit(self: *NativeCodegen) void {
        cleanup.deinit(self);
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

    /// Check if variable is an ArrayList (needs .items.len for len())
    pub fn isArrayListVar(self: *NativeCodegen, name: []const u8) bool {
        return self.arraylist_vars.contains(name);
    }

    /// Look up async function definition for complexity analysis
    pub fn lookupAsyncFunction(self: *NativeCodegen, name: []const u8) ?ast.Node.FunctionDef {
        return self.async_function_defs.get(name);
    }

    // Helper functions - public for use by statements.zig and expressions.zig
    pub fn emit(self: *NativeCodegen, s: []const u8) CodegenError!void {
        try self.output.appendSlice(self.allocator, s);
    }

    /// Emit formatted string
    pub fn emitFmt(self: *NativeCodegen, comptime fmt: []const u8, args: anytype) CodegenError!void {
        try self.output.writer(self.allocator).print(fmt, args);
    }

    pub fn emitIndent(self: *NativeCodegen) CodegenError!void {
        var i: usize = 0;
        while (i < self.indent_level) : (i += 1) {
            try self.emit("    ");
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
    /// Checks local scope first (to avoid type shadowing from other methods),
    /// then falls back to global type inference.
    pub fn getVarType(self: *NativeCodegen, var_name: []const u8) ?NativeType {
        // Check local scope first (function/method local variables)
        if (self.local_var_types.get(var_name)) |local_type| {
            return local_type;
        }
        // Fall back to global type inference
        return self.type_inferrer.var_types.get(var_name);
    }

    /// Register a local variable type (for current function/method scope)
    pub fn setLocalVarType(self: *NativeCodegen, var_name: []const u8, var_type: NativeType) !void {
        try self.local_var_types.put(var_name, var_type);
    }

    /// Clear local variable types (call when entering a new function/method)
    pub fn clearLocalVarTypes(self: *NativeCodegen) void {
        self.local_var_types.clearRetainingCapacity();
    }

    /// Check if a variable is mutated (reassigned after first assignment)
    /// Checks both module-level semantic info AND function-local mutations
    pub fn isVarMutated(self: *NativeCodegen, var_name: []const u8) bool {
        // Check function-local mutations first (when inside function body)
        if (self.func_local_mutations.contains(var_name)) {
            return true;
        }
        // Fall back to module-level semantic info
        return self.semantic_info.isMutated(var_name);
    }

    /// Check if a variable is unused (assigned but never read)
    pub fn isVarUnused(self: *NativeCodegen, var_name: []const u8) bool {
        return self.semantic_info.isUnused(var_name);
    }

    /// Check if a variable is referenced in an eval/exec string
    pub fn isEvalStringVar(self: *NativeCodegen, var_name: []const u8) bool {
        return self.semantic_info.isEvalStringVar(var_name);
    }

    /// Check if a variable is declared as 'global' in current function
    pub fn isGlobalVar(self: *NativeCodegen, var_name: []const u8) bool {
        return self.global_vars.contains(var_name);
    }

    /// Mark a variable as 'global' (references outer scope)
    pub fn markGlobalVar(self: *NativeCodegen, var_name: []const u8) !void {
        const name_copy = try self.allocator.dupe(u8, var_name);
        try self.global_vars.put(name_copy, {});
    }

    /// Clear global vars (call when exiting function scope)
    pub fn clearGlobalVars(self: *NativeCodegen) void {
        cleanup.clearGlobalVars(self);
    }

    /// Check if a module was skipped (external module not found)
    pub fn isSkippedModule(self: *NativeCodegen, module_name: []const u8) bool {
        return self.skipped_modules.contains(module_name);
    }

    /// Mark a module as skipped (external module not found)
    pub fn markSkippedModule(self: *NativeCodegen, module_name: []const u8) !void {
        const name_copy = try self.allocator.dupe(u8, module_name);
        try self.skipped_modules.put(name_copy, {});
    }

    /// Check if a function was skipped (references skipped modules)
    pub fn isSkippedFunction(self: *NativeCodegen, func_name: []const u8) bool {
        return self.skipped_functions.contains(func_name);
    }

    /// Mark a function as skipped (references skipped modules)
    pub fn markSkippedFunction(self: *NativeCodegen, func_name: []const u8) !void {
        const name_copy = try self.allocator.dupe(u8, func_name);
        try self.skipped_functions.put(name_copy, {});
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

    /// Get the parent class name for a given class (for super() support)
    pub fn getParentClassName(self: *NativeCodegen, class_name: []const u8) ?[]const u8 {
        return self.class_registry.inheritance.get(class_name);
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
        const gen = @import("generator.zig");
        return gen.generate(self, module);
    }
};
