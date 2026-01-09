/// Core NativeCodegen struct and basic operations
const std = @import("std");
const ast = @import("analysis.ast");
const zig_keywords = @import("utils.zig_keywords");
const native_types = @import("../../../analysis/native_types.zig");
const NativeType = native_types.NativeType;
const TypeInferrer = native_types.TypeInferrer;
const SemanticInfo = @import("../../../analysis/types.zig").SemanticInfo;
const comptime_eval = @import("../../../analysis/comptime_eval.zig");
const function_traits = @import("analysis.function_traits");
const module_traits = @import("analysis.module_traits");
const symbol_table_mod = @import("../symbol_table.zig");
const SymbolTable = symbol_table_mod.SymbolTable;
const ClassRegistry = symbol_table_mod.ClassRegistry;
const MethodInfo = symbol_table_mod.MethodInfo;
const import_registry = @import("../import_registry.zig");
const fnv_hash = @import("utils.fnv_hash");
const cleanup = @import("cleanup.zig");
const debug_info = @import("debug.debug_info");
const name_gen_mod = @import("codegen.name_gen");
const expr_emitter = @import("../expr_emitter.zig");
const builder_mod = @import("codegen.builder");

// Traits for type checking in exprToValue
const string_traits = @import("../../../analysis/traits/string_traits.zig");
const container_traits = @import("../../../analysis/traits/container_traits.zig");
const type_traits = @import("../../../analysis/traits/type_traits.zig");
const bigint_ops = @import("../expressions/operators/bigint_ops.zig");
const unified_int_ops = @import("../expressions/operators/unified_int_ops.zig");
const shared_maps = @import("../shared_maps.zig");
const method_categories = @import("../dispatch/method_categories.zig");

// Multi-pass analysis system (consolidated const/var, hoisting, capture analysis)
const pass_analysis = @import("../../passes/analysis.zig");
pub const PassAnalysisResult = pass_analysis.AnalysisResult;

// MIGRATED TO ZIGBUILDER
// NOTE: emitConst/emitFmtConst are DEPRECATED - use self.emit()/self.emitFmt() instead
// These file-level wrappers exist only for backward compatibility during migration.

// Helper for simple constant output - DEPRECATED: use self.emit() instead
fn emitConst(self: *NativeCodegen, val: []const u8) CodegenError!void {
    return self.emit(val);
}

// Helper for formatted output - DEPRECATED: use self.emitFmt() instead
fn emitFmtConst(self: *NativeCodegen, comptime fmt: []const u8, args: anytype) CodegenError!void {
    return self.emitFmt(fmt, args);
}

/// Check if all elements are constant literals of the same type (for array optimization)
fn isConstantHomogeneous(elts: []const ast.Node) bool {
    if (elts.len == 0) return false;

    // Get the type of the first element
    const first_type: ?enum { int, float, string, bool } = switch (elts[0]) {
        .constant => |c| switch (c.value) {
            .int => .int,
            .float => .float,
            .string => .string,
            .bool => .bool,
            else => null,
        },
        else => null,
    };

    // If first element is not a simple constant, can't use array optimization
    if (first_type == null) return false;

    // Check all other elements have the same type
    for (elts[1..]) |elem| {
        const elem_type: ?@TypeOf(first_type.?) = switch (elem) {
            .constant => |c| switch (c.value) {
                .int => .int,
                .float => .float,
                .string => .string,
                .bool => .bool,
                else => null,
            },
            else => null,
        };
        if (elem_type == null or elem_type.? != first_type.?) return false;
    }

    return true;
}

/// Emit bytecode VM fallback for uncertain/dynamic expressions
/// Used when native codegen can't handle a construct - falls back to VM execution
pub fn emitVMFallback(self: *NativeCodegen, source: []const u8) CodegenError!void {
    // At module level, we can't use 'try' - use 'catch unreachable' instead
    // Inside defer blocks, we also can't use 'try' - use 'catch unreachable'
    const at_module_level = self.current_function_name == null;
    const cannot_use_try = at_module_level or self.inside_defer;

    if (cannot_use_try) {
        // Generate: runtime.PyValue.from(runtime.eval(...) catch unreachable)
        try emitConst(self, "runtime.PyValue.from(runtime.eval(__global_allocator, \"");
        try escapeZigString(self, source);
        try emitConst(self, "\") catch unreachable)");
    } else {
        // Generate: runtime.PyValue.from(try runtime.eval(...))
        try emitConst(self, "runtime.PyValue.from(try runtime.eval(__global_allocator, \"");
        try escapeZigString(self, source);
        try emitConst(self, "\"))");
    }
}

/// Helper to escape a string for Zig string literal
/// NOTE: This writes through the builder to maintain correct output order.
fn escapeZigString(self: *NativeCodegen, source: []const u8) CodegenError!void {
    // Write to a temp buffer first, then emit through builder
    var buf: [4096]u8 = undefined;
    var fbs = std.io.fixedBufferStream(&buf);
    const writer = fbs.writer();
    for (source) |c| {
        switch (c) {
            '"' => writer.writeAll("\\\"") catch break,
            '\\' => writer.writeAll("\\\\") catch break,
            '\n' => writer.writeAll("\\n") catch break,
            '\r' => writer.writeAll("\\r") catch break,
            '\t' => writer.writeAll("\\t") catch break,
            else => writer.writeByte(c) catch break,
        }
    }
    try self.emit(fbs.getWritten());
}

// Import AST printer for VM fallback
const ast_printer = @import("../ast_printer.zig");

/// Emit VM fallback from AST node (auto-converts to Python source)
/// This is the main entry point for universal VM fallback
pub fn emitVMFallbackFromAST(self: *NativeCodegen, node: ast.Node) CodegenError!void {
    var printer = ast_printer.AstPrinter.init(self.allocator);
    defer printer.deinit();

    const source = printer.print(node) catch {
        // If AST printing fails, emit a panic as last resort
        try emitConst(self, "@panic(\"AST reconstruction failed\")");
        return;
    };
    defer self.allocator.free(source);

    // Collect variable names referenced in this VM fallback expression
    // These will need discards emitted because they appear only in string literals
    collectVMFallbackVars(self, node) catch {};

    try emitVMFallback(self, source);
}

/// Collect variable names from an AST node and register them as VM fallback used
fn collectVMFallbackVars(self: *NativeCodegen, node: ast.Node) !void {
    switch (node) {
        .name => |n| {
            // Skip Python builtins and keywords - these don't need discards
            if (std.mem.eql(u8, n.id, "None") or std.mem.eql(u8, n.id, "True") or
                std.mem.eql(u8, n.id, "False") or std.mem.eql(u8, n.id, "self") or
                std.mem.eql(u8, n.id, "complex") or std.mem.eql(u8, n.id, "operator") or
                std.mem.eql(u8, n.id, "int") or std.mem.eql(u8, n.id, "float") or
                std.mem.eql(u8, n.id, "str") or std.mem.eql(u8, n.id, "list") or
                std.mem.eql(u8, n.id, "dict") or std.mem.eql(u8, n.id, "set") or
                std.mem.eql(u8, n.id, "tuple") or std.mem.eql(u8, n.id, "len") or
                std.mem.eql(u8, n.id, "range") or std.mem.eql(u8, n.id, "print") or
                std.mem.eql(u8, n.id, "type") or std.mem.eql(u8, n.id, "isinstance") or
                std.mem.eql(u8, n.id, "hasattr") or std.mem.eql(u8, n.id, "getattr"))
            {
                return;
            }
            // Track ALL variable names in VM fallback expressions
            // The discard emitter will check if they're actually in scope
            const name_copy = try self.arena.allocator().dupe(u8, n.id);
            try self.vm_fallback_used_vars.put(name_copy, {});
        },
        .call => |call| {
            try collectVMFallbackVars(self, call.func.*);
            for (call.args) |arg| {
                try collectVMFallbackVars(self, arg);
            }
            for (call.keyword_args) |kw| {
                try collectVMFallbackVars(self, kw.value);
            }
        },
        .attribute => |attr| {
            try collectVMFallbackVars(self, attr.value.*);
        },
        .subscript => |sub| {
            try collectVMFallbackVars(self, sub.value.*);
            switch (sub.slice) {
                .index => |idx| try collectVMFallbackVars(self, idx.*),
                .slice => |range| {
                    if (range.lower) |lower| try collectVMFallbackVars(self, lower.*);
                    if (range.upper) |upper| try collectVMFallbackVars(self, upper.*);
                    if (range.step) |step| try collectVMFallbackVars(self, step.*);
                },
            }
        },
        .binop => |binop| {
            try collectVMFallbackVars(self, binop.left.*);
            try collectVMFallbackVars(self, binop.right.*);
        },
        .unaryop => |unary| {
            try collectVMFallbackVars(self, unary.operand.*);
        },
        .compare => |compare| {
            try collectVMFallbackVars(self, compare.left.*);
            for (compare.comparators) |comp| {
                try collectVMFallbackVars(self, comp);
            }
        },
        .if_expr => |if_expr| {
            try collectVMFallbackVars(self, if_expr.condition.*);
            try collectVMFallbackVars(self, if_expr.body.*);
            try collectVMFallbackVars(self, if_expr.orelse_value.*);
        },
        .list => |list| {
            for (list.elts) |elem| {
                try collectVMFallbackVars(self, elem);
            }
        },
        .tuple => |tuple| {
            for (tuple.elts) |elem| {
                try collectVMFallbackVars(self, elem);
            }
        },
        else => {},
    }
}

const hashmap_helper = @import("utils.hashmap_helper");
const scratch_buffer_mod = @import("../../../utils/scratch_buffer.zig");
const ScratchBuffer = scratch_buffer_mod.ScratchBuffer;

const FnvVoidMap = hashmap_helper.StringHashMap(void);
const FnvStringMap = hashmap_helper.StringHashMap([]const u8);
const FnvFuncDefMap = hashmap_helper.StringHashMap(ast.Node.FunctionDef);
const FnvClassDefMap = hashmap_helper.StringHashMap(ast.Node.ClassDef);

// Function signature info for default parameter handling and keyword argument mapping
const FuncSignature = struct {
    total_params: usize,
    required_params: usize, // params without defaults
    param_names: []const []const u8, // parameter names in order (for keyword arg mapping)
};
const FnvFuncSigMap = hashmap_helper.StringHashMap(FuncSignature);

/// ctypes function info (for argtypes/restype tracking)
pub const CTypesFuncInfo = struct {
    library_var: []const u8, // Variable name holding CDLL (e.g., "libc")
    func_name: []const u8, // C function name (e.g., "strlen")
    argtypes: []const []const u8, // ctypes type names (e.g., ["c_char_p", "c_int"])
    restype: []const u8, // Return type (e.g., "c_size_t", "c_int")
};

/// Default parameter for test methods
pub const TestDefaultParam = struct {
    name: []const u8,
    default_code: []const u8, // Zig code for the default value (e.g., "f64" for cls=float)
};

/// Info about a single test method
pub const TestMethodInfo = struct {
    name: []const u8,
    skip_reason: ?[]const u8 = null, // null = not skipped, otherwise the reason
    needs_allocator: bool = false, // true if method needs allocator param (has fallible ops)
    returns_error: bool = true, // true if method returns error union (uses try)
    is_skipped: bool = false, // true if method is skipped for any reason (docstring, refs skipped module, decorator)
    mock_patch_count: usize = 0, // number of @mock.patch.object decorators (each injects a mock param)
    default_params: []const TestDefaultParam = &.{}, // params with default values
};

/// Unittest TestCase class info
pub const TestClassInfo = struct {
    class_name: []const u8,
    test_methods: []const TestMethodInfo,
    has_setUp: bool = false,
    has_tearDown: bool = false,
    has_setup_class: bool = false,
    has_teardown_class: bool = false,
    /// True if this class came from a factory function (tuple unpacking)
    /// Factory-returned classes are PyValue types, requiring runtime dispatch
    is_factory_returned: bool = false,
    /// True if this class is defined inside a conditional block (e.g., if sys.platform == 'win32')
    /// Conditional classes are skipped in test runner generation to avoid undeclared identifier errors
    is_conditional: bool = false,
    /// For factory-returned classes: the original struct name inside the factory function
    /// This is the actual Zig struct with .init() and test methods, as opposed to
    /// class_name which may be the PyValue variable name from tuple unpacking
    original_class_name: ?[]const u8 = null,
    /// For factory-returned classes: the name of the factory function
    /// Used along with original_class_name to construct scoped names for hoisting
    factory_name: ?[]const u8 = null,
};

/// Factory function that returns test classes
/// Maps factory function name -> array of TestClassInfo (in order returned)
pub const TestFactoryInfo = struct {
    returned_classes: []const TestClassInfo,
};

/// Code generation mode
pub const CodegenMode = enum {
    script, // Has main(), runs directly
    module, // Exports functions, no main()
    logic_table_only, // Only emit @logic_table structs (no runtime, for LanceQL)
};

/// Error set for code generation
pub const CodegenError = error{
    OutOfMemory,
    UnsupportedModule,
    UnsupportedSyntax,
    MissingBuiltinModule,
    FormattingError,
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

/// Info for deferred closure instantiation (when captures include forward-referenced variables)
pub const DeferredClosureInfo = struct {
    func_name: []const u8, // Original function name
    closure_var_name: []const u8, // __closure_name_N
    capture_type_name: []const u8, // __CaptureType_name_N
    closure_impl_name: []const u8, // __ClosureImpl_name_N
    impl_fn_name: []const u8, // call_name_N
    captured_vars: [][]const u8, // Variable names to capture
    total_params: usize, // Number of function params (for AnyClosure selection)
    forward_ref_vars: [][]const u8, // Which captures are forward-referenced (need to wait for)
    alias_name: []const u8, // The name to alias (e.g., "check")
};

/// Context for active finally blocks - used for Nuitka-style code duplication
/// When return/break/continue/raise is encountered inside try-finally,
/// the finally code is duplicated inline BEFORE the control flow statement.
pub const FinallyContext = struct {
    id: u32, // Unique ID for this finally block
    finalbody: []const ast.Node, // AST nodes for finally block
    pending_exception_var: []const u8, // Variable name like "__pending_exception_0"
    is_defer_based: bool, // True if using defer approach (skip inline duplication)
};

/// From-import from C extension module (e.g., from numpy.testing import assert_)
pub const CExtFromImport = struct {
    module: []const u8, // Module name (e.g., "numpy.testing")
    attr: []const u8, // Attribute name (e.g., "assert_")
};

pub const NativeCodegen = struct {
    allocator: std.mem.Allocator,
    arena: *std.heap.ArenaAllocator, // Arena for internal string allocations (deinit frees all at once)
    scratch: ScratchBuffer, // Scratch buffer for temporary allocations (2-3x faster than arena for temps)
    output: std.ArrayList(u8),
    type_inferrer: *TypeInferrer,
    semantic_info: *SemanticInfo,
    indent_level: usize,

    // Codegen mode (script vs module)
    mode: CodegenMode,

    // Module name (for module mode)
    module_name: ?[]const u8,

    // Whether this is a dependency module (imported, not main entry)
    // Dependencies don't emit _metal0_module_marker to avoid symbol collisions
    is_dependency: bool,

    // Symbol table for scope-aware variable tracking
    symbol_table: *SymbolTable,

    // Class registry for inheritance support and method lookup
    class_registry: *ClassRegistry,

    // Counter for unique __TryHelper struct names (avoids shadowing in nested try blocks)
    try_helper_counter: usize,

    // Depth of nested TryHelper structs. 0 = not inside any TryHelper, 1+ = inside TryHelper(s)
    // Used to determine if exception variables should be local (inside TryHelper) or hoisted (outside)
    try_helper_depth: usize,

    // Depth of nested if/else conditionals. 0 = not inside any conditional
    // Used to determine if closures need hoisting for Python scope semantics
    conditional_depth: usize,

    // When inside a try helper that contains break/continue, stores the helper ID for special handling
    // null = not in try helper with break/continue, non-null = emit return error.BreakRequested
    try_break_helper_id: ?usize,

    // Lambda support - counter for unique names, storage for lambda function definitions
    lambda_counter: usize,
    lambda_functions: std.ArrayList([]const u8),

    // Counter for unique block labels (avoids nested blk: redefinition)
    // Use nextLabelId() or emitLabeledBlock() to get unique labels
    block_label_counter: usize,

    // Counter for unique shadow variable names (tuple += creates new const)
    shadow_counter: usize,

    // Track which variables hold closures (for .call() generation)
    closure_vars: FnvVoidMap,

    // Track closures hoisted as DynamicClosure (from if/else branches)
    // These are declared as `var name: runtime.DynamicClosure = undefined;`
    // and assigned inside branches, not declared as `const name = ...;`
    hoisted_dynamic_closures: FnvVoidMap,

    // Track closures that return void (no catch needed)
    void_closure_vars: FnvVoidMap,

    // Track closures that are generators (return []PyValue)
    generator_closure_vars: FnvVoidMap,

    // Track which variables hold callables (PyCallable - for .call() generation)
    callable_vars: FnvVoidMap,

    // Track which callable vars return error unions (like OperatorPow)
    // These need (try ...) wrapper when called outside assertRaises
    error_callable_vars: FnvVoidMap,

    // Track recursive closures and their captured variables (for passing captures in calls)
    recursive_closure_vars: hashmap_helper.StringHashMap([][]const u8),

    // Track which variables are closure factories (return closures)
    closure_factories: FnvVoidMap,

    // Track pending closure types for functions that return closures
    // Maps nested function name -> pre-declared closure type name
    pending_closure_types: FnvStringMap,

    // Track closures with forward-referenced captures that need deferred instantiation
    // Maps forward-ref variable name -> list of closures waiting for that variable
    deferred_closure_instantiations: hashmap_helper.StringHashMap(std.ArrayList(DeferredClosureInfo)),

    // Track which class methods return closures (ClassName.method_name -> void)
    closure_returning_methods: FnvVoidMap,

    // Track which variables hold simple lambdas (function pointers)
    lambda_vars: FnvVoidMap,

    // When set, lambda parameters should use this type instead of inference
    // Used when generating lambdas for PyCallable contexts (e.g., list.append with callable list)
    callable_context_param_type: ?[]const u8,

    // Variable renames for exception handling (maps original name -> renamed name)
    var_renames: FnvStringMap,

    // Track variables hoisted from try blocks (to skip declaration in assignment)
    hoisted_vars: FnvVoidMap,

    // Track variables hoisted with PyValue type (need PyValue.from() wrapper on assignment)
    pyvalue_hoisted_vars: FnvVoidMap,

    // Track exception variable names (from "except X as name:") - typed as PyException
    exception_vars: FnvVoidMap,

    // Track variables that hold exception type classes (e.g., context = IndexError)
    // Maps var_name -> exception type name (e.g., "context" -> "IndexError")
    exception_type_vars: FnvStringMap,

    // Track first assignments that may need discards (var_name -> emitted_name)
    // Discards are emitted at end of scope after checking if variable was actually used
    pending_discards: FnvStringMap,

    // Track variables referenced in generated VM fallback expressions
    // These need discards emitted because they appear only in string literals in generated code
    vm_fallback_used_vars: FnvVoidMap,

    // Track which parameters have been discarded in current function scope
    // Prevents duplicate `_ = &param;` emissions from multiple code paths
    // Cleared when entering a new function scope
    discarded_params: FnvVoidMap,

    // Starting position in output buffer for current function
    // Used to limit variable usage search to current function scope only
    function_start_pos: usize,

    // Track which variables hold constant arrays (vs ArrayLists)
    array_vars: FnvVoidMap,

    // Track which variables hold array slices (result of slicing a constant array)
    array_slice_vars: FnvVoidMap,

    // Track which variables hold lists of closures (for x.call() syntax when iterating)
    closure_list_vars: FnvVoidMap,

    // Track lazy class attributes that became getter methods
    // Maps "ClassName.attrName" -> void to indicate C.attr should become (try C.attr(__alloc))
    lazy_class_attrs: FnvVoidMap,

    // Track ArrayList variables (for len() -> .items.len)
    arraylist_vars: FnvVoidMap,

    // Track ArrayList aliases (y = x where x is ArrayList, y points to x)
    // Maps alias name -> original variable name
    arraylist_aliases: FnvStringMap,

    // Track class instance aliases (y = x where x is class instance, y points to x)
    // Maps alias name -> original variable name (for Python reference semantics)
    class_instance_aliases: FnvStringMap,

    // Track dict variables (for subscript access -> .get()/.put())
    dict_vars: FnvVoidMap,

    // Context: When generating a dict literal for assignment to a variable with a widened type,
    // this holds the target value type (e.g., "runtime.PyValue" for dict(key, pyvalue)).
    // Set before genExpr, cleared after. Dict codegen checks this to use the widened type.
    target_dict_value_type: ?[]const u8,

    // Track anytype parameters in current function scope (for comprehension iteration)
    anytype_params: FnvVoidMap,

    // Track type-narrowed anytype params: param_name -> class_name
    // Set inside `if isClassName(param):` blocks, cleared on exit
    // Used to enable direct field access with correct types (vs getAttrDynamic which returns f64)
    narrowed_type_params: FnvStringMap,

    // Track parameters with None defaults (need null comparison, not false literal)
    none_default_params: FnvVoidMap,

    // Track which classes have mutating methods (need var instances, not const)
    mutable_classes: FnvVoidMap,

    // Track which classes have init methods that return error unions (!@This())
    // These classes need `try` when instantiating due to comptime type checks
    error_init_classes: FnvVoidMap,

    // Track unittest TestCase classes and their test methods
    unittest_classes: std.ArrayList(TestClassInfo),

    // Track factory functions that return test classes (for tuple unpacking discovery)
    test_factories: hashmap_helper.StringHashMap(TestFactoryInfo),

    // Compile-time evaluator for constant folding
    comptime_evaluator: comptime_eval.ComptimeEvaluator,

    // C library import context (for ctypes FFI)
    import_ctx: ?*const @import("c_interop").ImportContext,

    // Source file path (for resolving relative imports)
    source_file_path: ?[]const u8,

    // Track decorated functions for application in main()
    decorated_functions: std.ArrayList(DecoratedFunction),

    // Import registry for Python→Zig module mapping
    import_registry: *import_registry.ImportRegistry,

    // Module registry for cross-module function/constant lookup
    module_registry: *module_traits.ModuleRegistry,

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
    // Maps function name -> vararg_start_index (number of regular params before *args)
    // e.g., "op_sequence" -> 1 for def op_sequence(op, *classes)
    vararg_functions: hashmap_helper.StringHashMap(usize),

    // Track vararg parameter names (*args parameters)
    // Maps parameter name -> void (e.g., "args" -> {})
    // Used for type inference: iterating over vararg gives i64
    vararg_params: FnvVoidMap,

    // Track loop variables from vararg iteration (e.g., "c" in "for c in classes" where classes is vararg)
    // These variables may be types at comptime, requiring .init() call instead of direct call
    vararg_loop_vars: FnvVoidMap,

    // Track current vararg source when inside a vararg loop body
    // Used to record which lists are populated from vararg iteration
    current_vararg_source: ?[]const u8,

    // Track lists populated from vararg loops (e.g., "instances" from "for c in classes: instances.append(...)")
    // Maps list name -> vararg source name (e.g., "instances" -> "classes")
    // Used for starred expression unpacking: op(*instances) uses @typeInfo of classes tuple
    vararg_list_sources: hashmap_helper.StringHashMap([]const u8),

    // Track methods with varargs (*args)
    // Maps "ClassName.method_name" -> vararg_start_index (number of regular params before *args, not counting self)
    // e.g., "OperationLogger.log_operation" -> 0 for def log_operation(self, *args)
    vararg_methods: hashmap_helper.StringHashMap(usize),

    // Track functions with kwargs (**kwargs)
    // Maps function name -> void (e.g., "func" -> {})
    kwarg_functions: FnvVoidMap,

    // Track kwarg parameter names (**kwargs parameters)
    // Maps parameter name -> void (e.g., "kwargs" -> {})
    // Used for type inference: len(kwargs) -> runtime.PyDict.len()
    kwarg_params: FnvVoidMap,

    // Track dict builtin variables (for dict comprehension codegen)
    dict_builtin_vars: FnvVoidMap,

    // Track function signatures (param counts for default handling)
    // Maps function name -> FuncSignature (e.g., "foo" -> {total: 2, required: 1})
    function_signatures: FnvFuncSigMap,

    // Track imported module names (for mymath.add() -> needs allocator)
    // Maps module name -> void (e.g., "mymath" -> {})
    imported_modules: FnvVoidMap,

    // Track import aliases (import X as Y)
    // Maps alias name -> module name (e.g., "support" -> "test.support")
    import_aliases: FnvStringMap,

    // Track module alias mappings (Python import name -> Zig implementation name)
    // Maps Python module name -> Zig impl path (e.g., "_io" -> "_pyio", "_collections" -> "_collections._collections")
    // Used during codegen to generate correct runtime.Lib.X references
    module_alias_map: FnvStringMap,

    // Track module-level from-import symbols (from X import Y)
    // Maps symbol name -> void (e.g., "import_helper" -> {})
    // Used to skip duplicate local imports that would shadow module-level ones
    module_level_from_imports: FnvVoidMap,

    // Track variable mutations (for list ArrayList vs fixed array decision)
    // Maps variable name -> mutation info
    mutation_info: ?*const @import("../../../analysis/native_types/mutation_analyzer.zig").MutationMap,

    // Multi-pass analysis results (const/var inference, hoisting, captures, declaration order)
    // Initialized from IR-based analysis in generate(), replaces redundant AST-based systems
    pass_analysis_result: ?*PassAnalysisResult,

    // Track if we're inside a 'with self.assertRaises' context
    // When true, error-producing operations should use catch instead of try
    in_assert_raises_context: bool,

    // Counter for unique assertRaises block labels
    assert_raises_block_id: u32,

    // Current assertRaises block ID (for genRaise to break out of)
    current_assert_raises_block_id: u32,

    // Counter for unique block labels (os.path, etc.)
    general_block_id: u32,

    // Track when control flow has terminated (return/raise)
    // When true, skip generating subsequent statements to avoid unreachable code
    control_flow_terminated: bool,

    // Track C libraries needed for linking (from C extension imports)
    c_libraries: std.ArrayList([]const u8),

    // Track comptime eval() calls (string literal arguments that can be compiled at comptime)
    // Maps source code string -> void (e.g., "1 + 2" -> {})
    comptime_evals: FnvVoidMap,

    // String interning - collect all string literals for O(1) equality comparison
    // Maps string content (without quotes) -> intern index
    interned_strings: hashmap_helper.StringHashMap(usize),
    // Ordered list of interned strings for table generation
    intern_list: std.ArrayList([]const u8),
    // Counter for intern indices
    intern_counter: usize,

    // Track function-local mutated variables (populated before genFunctionBody)
    // Maps variable name -> void for variables that are reassigned within current function
    func_local_mutations: FnvVoidMap,

    // Track function-local aug_assign variables (x += 1, etc.)
    // Used to distinguish true mutations from just type-change reassignments
    func_local_aug_assigns: FnvVoidMap,

    // Track function-local used variables (populated before genFunctionBody)
    // Maps variable name -> void for variables that are read (not just assigned) within current function
    // Used to prevent false "unused variable" detection for local variables
    func_local_uses: FnvVoidMap,

    // Track variables declared as 'global' in current function scope
    // Maps variable name -> void for variables that reference outer (module) scope
    global_vars: FnvVoidMap,

    // Track module-level function names for parameter shadowing detection
    // When a function parameter has the same name as a module-level function,
    // we need to rename the parameter to avoid shadowing errors in Zig
    module_level_funcs: FnvVoidMap,

    // Track module-level variables (assignments at top level of module)
    // These are available at function-start for hoisted var type derivation
    module_level_vars: FnvVoidMap,

    // Track conditionally hoisted variable types (for generating correct empty containers)
    // Maps variable name -> Zig type string (e.g., "SKIP_MODULES" -> "hashmap_helper.StringHashMap(void)")
    conditional_var_types: hashmap_helper.StringHashMap([]const u8),

    // Track variables defined in current function scope (for nested class closure detection)
    // Maps variable name -> void (e.g., "calls" -> {})
    // Populated at start of function generation, used to detect outer scope references
    func_local_vars: FnvVoidMap,

    // Track captured variables for nested classes within current function
    // Maps class name -> list of captured variable names
    // E.g., "Left" -> ["calls", "results"]
    nested_class_captures: hashmap_helper.StringHashMap([][]const u8),

    // Track which captured variables are mutated (via append, extend, etc.)
    // Maps "class_name.var_name" -> {} for mutated vars
    // Used to decide *const vs * pointer type for captured vars
    mutated_captures: FnvVoidMap,

    // Track instances of nested classes (variable name -> class name)
    // E.g., "obj" -> "Inner" when we have `obj = Inner()`
    // Used to pass allocator to method calls on nested class instances
    nested_class_instances: hashmap_helper.StringHashMap([]const u8),

    // Track all nested class names defined in current function/method scope
    // Used to detect class constructor calls for nested classes without captures
    nested_class_names: FnvVoidMap,

    // Track class-body-level nested class aliases (e.g., "Inner" -> "Outer__Inner")
    // These are classes defined directly in a class body (not inside methods)
    // Used to resolve references like self.Inner() or Inner() to the mangled name
    nested_class_aliases: FnvStringMap,

    // Track classes that have been hoisted from method bodies to struct level
    // Maps original class name -> actual generated name (which may be renamed due to collisions)
    // These classes should be skipped during normal body generation
    hoisted_local_classes: FnvStringMap,

    // Track local classes defined in the current method scope (cleared between methods)
    // Used by assertRaises to detect when callable is a local class type
    current_scope_classes: FnvVoidMap,

    // Track factory test classes hoisted to module scope
    // Maps original class name -> module-scope scoped name (e.g., "TestLegacyAPI" -> "test_factory__TestLegacyAPI")
    // Used to skip inline class defs in factory bodies and reference hoisted classes
    factory_hoisted_classes: FnvStringMap,

    // Track variables assigned from BigInt expressions
    // Used to detect when a variable's type is BigInt for subsequent operations
    bigint_vars: FnvVoidMap,

    // Track variables assigned from PyValue expressions (VM fallback, eval)
    // Used to detect when a variable holds a PyValue callable for .call() generation
    pyvalue_vars: FnvVoidMap,

    // Track variables that are imported class types (e.g., Fraction from fractions)
    // These need .init() instantiation instead of .call()
    imported_class_types: FnvVoidMap,

    // Track base class for nested classes (maps class name -> base class name)
    // Used to provide default args when calling BadIndex() where BadIndex(int)
    nested_class_bases: FnvStringMap,

    // Track nested class definitions (maps class name -> ClassDef AST)
    // Used to inherit __init__ signature from parent nested classes
    nested_class_defs: FnvClassDefMap,

    // Track which nested class methods need allocator parameter
    // Maps "ClassName.methodName" -> void for methods that need allocator
    // Used at call sites to determine if allocator should be passed
    nested_class_method_needs_alloc: FnvVoidMap,

    // Track which nested classes are actually referenced in generated Zig code
    // When emitting class references (e.g., ClassName.init(), ClassName.method()),
    // the class name is added here. At function body end, we emit _ = ClassName;
    // only for classes in nested_class_names but NOT in this map
    nested_class_zig_refs: FnvVoidMap,

    // Track class-level callable builtin attributes (e.g., enum = enumerate, int_class = int)
    // Maps "ClassName.attr_name" -> builtin_name for direct invocation via @This().attr_name(...)
    // Includes type constructors (int, str, list) and functions (enumerate, len, range, zip, etc.)
    class_type_attrs: FnvStringMap,

    // Current class being generated (for super() support)
    // Set during class method generation, null otherwise
    current_class_name: ?[]const u8,

    // Current class body (list of statements) - for checking if params shadow sibling methods
    current_class_body: ?[]ast.Node,

    // Current assignment target name (for type-aware empty list generation)
    // Set during assignment generation, null otherwise
    current_assign_target: ?[]const u8,

    // Depth of nested list literal context (> 0 means we're inside a list literal)
    // Used to ensure inner lists generate as ArrayList, not fixed arrays
    inside_list_depth: usize,

    // Captured variables for the current class (from parent scope)
    // Set when entering a class with captured variables, null otherwise
    // Used by expression generator to convert `var_name` to `self.__captured_var_name.*`
    current_class_captures: ?[][]const u8,

    // True when inside __init__ method - captured vars accessed via __cap_* params, not self
    inside_init_method: bool,

    // True when inside __new__ method - captured vars accessed via __cls, not __self
    inside_new_method: bool,

    // True when inside a classmethod (e.g., @classmethod or __init_subclass__)
    // Classmethods don't have self/__self, so captured vars need different access pattern
    inside_classmethod: bool,

    // True when current method has mutable self (*@This() vs *const @This())
    // Used to dereference self when returning from methods that mutate and return self
    method_self_is_mutable: bool,

    // The actual first parameter name of the current method (e.g., "self", "test_self", "cls")
    // Used to recognize unittest method calls like test_self.assertEqual()
    // Python allows any name for the first parameter of a method
    current_method_first_param: ?[]const u8,

    // Current class's parent name (for parent method call resolution)
    // E.g., "array.array" when class inherits from array.array
    current_class_parent: ?[]const u8,

    // Class nesting depth (0 = top-level, 1 = nested inside another class)
    // Used to determine allocator parameter name (__alloc for nested classes)
    class_nesting_depth: u32,

    // Method nesting depth (0 = not in method, 1+ = inside nested class inside method)
    // Used to rename self -> __self in nested struct methods to avoid shadowing
    // Incremented when entering a class while inside_method_with_self is true
    method_nesting_depth: u32,

    // True when we're generating code inside a method that has a 'self' parameter
    // Used to decide whether to increment method_nesting_depth when entering a nested class
    inside_method_with_self: bool,

    // Current scope ID for scope-aware mutation tracking
    // 0 = function scope, unique pointer address = loop/block scope
    // Used to determine if a variable is mutated within the current scope
    current_scope_id: usize,

    // True when generating code inside a defer block
    // In defer blocks, 'try' is not allowed, so we use 'catch {}' instead
    inside_defer: bool,

    // True when generating code inside a const initializer (pub const ... = <expr>)
    // In const initializers, 'try' is not allowed, so we use 'catch unreachable' instead
    inside_const_init: bool,

    // True when generating code inside a finally block that can capture exceptions
    // When true, raise statements break out of the finally block with an error
    inside_finally_block: bool,

    // Current finally block ID for unique label names
    // Used for break :__finally_blk_N error.SomeException
    current_finally_id: u32,

    // Stack of active finally blocks for Nuitka-style code duplication
    // When return/break/continue/raise is inside try-finally, the finally code
    // is duplicated inline BEFORE the control flow statement
    finally_stack: std.ArrayList(FinallyContext),

    // Counter for generating unique finally block IDs
    finally_counter: u32,

    // True when generating code inside a nested function/closure body
    // When true, isDeclared() only checks current scope, not parent function scopes
    // This ensures variables from outer function that weren't captured are treated as undeclared
    inside_nested_function: bool,

    // Base scope level when entering a nested function
    // Used by isDeclared() to check all scopes within the nested function (including block scopes like for loops)
    // Without exceeding into outer function scopes
    nested_function_base_scope: usize,

    // Current function being generated (for tail-call optimization)
    // Set during function generation, null otherwise
    current_function_name: ?[]const u8,

    // Current function/method body being generated
    // Used for lookahead-based type inference (e.g., dict key type from subscript assignments)
    current_function_body: ?[]const ast.Node,

    // Track if we're inside a generator function
    // When true, yield statements append to __gen_result ArrayList
    in_generator_function: bool,

    // Track if we're inside a @logic_table class
    // When true, methods are emitted with 'pub fn' for external linking
    in_logic_table_class: bool,

    // When true, generate C-callable export wrappers for @logic_table methods
    // Used for JIT compilation where functions need to be callable via FFI
    emit_logic_table_exports: bool,

    // Two-Flow: Track if current function returns PyValue (needs boxing at return)
    // Set when function has uncertain params or mixed return types
    current_function_returns_pyvalue: bool,

    // Track if current function can use `try` (returns error union)
    // When false, fallible operations must use `catch unreachable` instead of `try`
    // Set based on return type when generating function signatures
    current_function_can_try: bool,

    // Track if we're inside a try block body
    // When true, error-returning builtins use 'try' instead of 'catch default'
    // This allows errors to propagate to except handlers
    inside_try_body: bool,

    // Track if we're inside a try block that catches NameError (or bare except)
    // When true, undefined variable names emit runtime.exceptions.raiseNameError()
    // instead of bare identifiers that would cause Zig compilation errors
    in_nameerror_context: bool,

    // Track if we're inside a try block that has a finally block (but no exception handlers)
    // When true, raise statements store exception to __pending_exception_N instead of returning
    // This ensures finally block runs before exception propagates
    inside_try_with_finally: bool,

    // Current try-finally helper ID for __pending_exception_N variable name
    current_try_finally_id: u32,

    // True when targeting WASM browser (freestanding) mode
    // Used to skip exports for non-main functions
    target_wasm_browser: bool,

    // Track skipped modules (external modules not found in registry)
    // Maps module name -> void (e.g., "pytest" -> {})
    // Used to skip code that references these modules
    skipped_modules: FnvVoidMap,

    // Track skipped functions (functions that reference skipped modules)
    // Maps function name -> void (e.g., "run_code" -> {})
    // Used to skip calls to functions that weren't generated
    skipped_functions: FnvVoidMap,

    // Track "codegen only" modules (function handlers only, no runtime library)
    // These modules like 'logic_table' are handled purely at compile time via dispatch
    // Maps module name -> void (e.g., "logic_table" -> {})
    codegen_only_modules: FnvVoidMap,

    // Track C extension modules (numpy, pandas, etc.)
    // Maps module name -> alias name (e.g., "numpy" -> "np", "pandas" -> "pd")
    // These are loaded at runtime via PyImport_ImportModule
    c_extension_modules: FnvStringMap,

    // Track if c_interop import is needed (for C extension method calls)
    needs_c_interop: bool,

    // Track root modules that need explicit variables even when aliased
    // e.g., "import numpy as np" + "import numpy._core.include" needs BOTH np AND numpy vars
    // When a submodule is imported, the root module must have its own variable for direct access
    c_extension_root_modules: FnvStringMap,

    // Track from-imports from C extension modules (need runtime initialization)
    // Maps symbol name -> {module, attr} (e.g., "assert_" -> {"numpy.testing", "assert_"})
    c_extension_from_imports: hashmap_helper.StringHashMap(CExtFromImport),

    // Track local variable types within current function/method scope
    // Maps variable name -> NativeType (e.g., "result" -> .string)
    // Cleared when entering a new function scope, used to avoid type shadowing issues
    local_var_types: hashmap_helper.StringHashMap(NativeType),

    // Track local from-imports within function bodies (for inline-codegen modules)
    // Maps symbol name -> module name (e.g., "getrandbits" -> "random")
    // Used to route calls like getrandbits(...) to random.getrandbits dispatch
    local_from_imports: FnvStringMap,

    // Track for-loop capture variables (immutable in Zig, but Python allows reassignment)
    // Maps variable name -> void (e.g., "line" -> {})
    // When assigning to a loop capture, we rename to __loop_<varname> and track in var_renames
    loop_capture_vars: FnvVoidMap,

    // Track heterogeneous loop variables (iterate over mixed-type tuples like ["str", 0.0, None])
    // These are wrapped in runtime.PyValue for type consistency in TryHelper
    // Maps variable name -> void (e.g., "x" -> {})
    heterogeneous_loop_vars: FnvVoidMap,

    // Track forward-declared variables (captured by nested classes before defined)
    // Maps variable name -> void (e.g., "list2" -> {})
    // When assigning to a forward-declared var, don't emit "var" again
    forward_declared_vars: FnvVoidMap,

    // Track variables that are returned from the current function
    // Maps variable name -> void (e.g., "log" -> {})
    // Defer deinit is SKIPPED for these variables because caller takes ownership
    returned_vars: FnvVoidMap,

    // Track callable global variables (function references like float.fromhex)
    // These need to be emitted at module level, not inside main()
    // Maps variable name -> void (e.g., "fromHex" -> {})
    callable_global_vars: FnvVoidMap,

    // Track import_module() assigned variables (e.g., ctypes_test = import_module("ctypes"))
    // These are compile-time type references, not runtime variables
    import_module_vars: FnvVoidMap,

    // Track csv module iterator variables (csv.reader, csv.DictReader, etc.)
    // These need special for-loop handling: while (iter.next()) |row| instead of for (iter) |row|
    csv_iterators: FnvVoidMap,

    // Track type alias variables (e.g., R = fractions.Fraction, D = decimal.Decimal)
    // These are emitted as `const R = type` not pre-declared as variables
    type_alias_vars: FnvVoidMap,

    // Track what type each alias points to (e.g., "R" -> "Fraction", "D" -> "Decimal")
    // Used to resolve starred args handling for specific types like Fraction
    type_alias_targets: hashmap_helper.StringHashMap([]const u8),

    // Track function names that are hoisted from if-else branches
    // These functions are defined in multiple if-else branches but used after the block
    // Maps function name -> void (e.g., "get_output" -> {})
    // When generating closures for these functions, skip var_renames to avoid scoping issues
    hoisted_branch_funcs: FnvVoidMap,

    // Function traits call graph for unified analysis (built lazily on first generate())
    // Query via function_traits.isPure(), .needsAllocator(), .canUseTCO(), etc.
    call_graph: ?function_traits.CallGraph,

    // Track generic type parameters in current scope (for Generic[T, U] classes)
    // Maps type param name -> void (e.g., "T" -> {})
    // Used during codegen to identify when a name refers to a comptime type param
    generic_type_params: FnvVoidMap,

    // Track generic classes (classes that inherit from Generic[T, U, ...])
    // Maps class name -> number of type params (e.g., "Box" -> 1, "Pair" -> 2)
    // Used at instantiation to generate Box(i64).init() instead of Box.init()
    generic_classes: hashmap_helper.StringHashMap(usize),

    // Track ctypes function info (argtypes, restype)
    // Maps variable name -> CTypesFuncInfo (e.g., "strlen" -> { lib: "libc", func: "strlen", argtypes: [...], restype: "c_size_t" })
    ctypes_functions: hashmap_helper.StringHashMap(CTypesFuncInfo),

    // Debug info writer (optional, only set when --debug flag is used)
    // Used to record Python line -> Zig line mappings for stack traces and debugging
    debug_writer: ?*debug_info.DebugInfoWriter,

    // Current Zig line number being generated (tracked for debug info)
    // Incremented each time a newline is emitted
    zig_line_counter: u32,

    // Token array from lexer (optional, for looking up Python line numbers)
    // Used during debug info generation to find source lines for statements
    tokens: ?[]const @import("../../../lexer.zig").Token,

    // Token line lookup map (built lazily when needed for debug info)
    // Maps identifier name -> Python line number
    token_lines: ?hashmap_helper.StringHashMap(u32),

    // Keyword occurrence counters for debug line mapping
    // Track how many times we've processed each keyword type during codegen
    keyword_raise_count: u32,
    keyword_assert_count: u32,

    // Unified name generator for conflict-free naming
    // All generated names use _$prefix which is impossible in Python source
    // This eliminates the need for shadowing detection entirely
    name_gen: name_gen_mod.NameGen,

    // Structured code builder (Phase 1 migration)
    // Provides type-safe, scope-aware code generation API
    // Will gradually replace string-based emit()/emitFmt() calls
    builder: ?*builder_mod.ZigBuilder,

    pub fn init(allocator: std.mem.Allocator, type_inferrer: *TypeInferrer, semantic_info: *SemanticInfo, source_file_path: []const u8) !*NativeCodegen {
        // Create arena for internal string allocations (keys, duped strings)
        // Arena allocator allows O(1) cleanup via single deinit() call
        const arena = try allocator.create(std.heap.ArenaAllocator);
        arena.* = std.heap.ArenaAllocator.init(allocator);
        const aa = arena.allocator();

        const self = try allocator.create(NativeCodegen);

        // Create and initialize symbol table (uses backing allocator - has own cleanup)
        const sym_table = try allocator.create(SymbolTable);
        sym_table.* = try SymbolTable.init(allocator);

        // Create and initialize class registry (uses backing allocator - has own cleanup)
        const cls_registry = try allocator.create(ClassRegistry);
        cls_registry.* = ClassRegistry.init(allocator);

        // Create and initialize import registry (uses backing allocator - has own cleanup)
        const registry = try allocator.create(import_registry.ImportRegistry);
        registry.* = try import_registry.createDefaultRegistry(allocator);

        // Create and initialize module registry (uses backing allocator - has own cleanup)
        const mod_registry = try allocator.create(module_traits.ModuleRegistry);
        mod_registry.* = module_traits.ModuleRegistry.init(allocator);

        self.* = .{
            .allocator = allocator,
            .arena = arena,
            .scratch = ScratchBuffer.init(),
            .output = std.ArrayList(u8){},
            .type_inferrer = type_inferrer,
            .semantic_info = semantic_info,
            .indent_level = 0,
            .mode = .script,
            .module_name = null,
            .is_dependency = false,
            .symbol_table = sym_table,
            .class_registry = cls_registry,
            .try_helper_counter = 0,
            .try_helper_depth = 0,
            .conditional_depth = 0,
            .try_break_helper_id = null,
            .lambda_counter = 0,
            .lambda_functions = std.ArrayList([]const u8){},
            .block_label_counter = 0,
            .shadow_counter = 0,
            // All maps use arena allocator - keys are freed automatically via arena.deinit()
            .closure_vars = FnvVoidMap.init(aa),
            .hoisted_dynamic_closures = FnvVoidMap.init(aa),
            .void_closure_vars = FnvVoidMap.init(aa),
            .generator_closure_vars = FnvVoidMap.init(aa),
            .callable_vars = FnvVoidMap.init(aa),
            .error_callable_vars = FnvVoidMap.init(aa),
            .recursive_closure_vars = hashmap_helper.StringHashMap([][]const u8).init(aa),
            .closure_factories = FnvVoidMap.init(aa),
            .pending_closure_types = FnvStringMap.init(aa),
            .deferred_closure_instantiations = hashmap_helper.StringHashMap(std.ArrayList(DeferredClosureInfo)).init(aa),
            .closure_returning_methods = FnvVoidMap.init(aa),
            .lambda_vars = FnvVoidMap.init(aa),
            .callable_context_param_type = null,
            .var_renames = FnvStringMap.init(aa),
            .hoisted_vars = FnvVoidMap.init(aa),
            .pyvalue_hoisted_vars = FnvVoidMap.init(aa),
            .exception_vars = FnvVoidMap.init(aa),
            .exception_type_vars = FnvStringMap.init(aa),
            .pending_discards = FnvStringMap.init(aa),
            .vm_fallback_used_vars = FnvVoidMap.init(aa),
            .discarded_params = FnvVoidMap.init(aa),
            .function_start_pos = 0,
            .array_vars = FnvVoidMap.init(aa),
            .array_slice_vars = FnvVoidMap.init(aa),
            .closure_list_vars = FnvVoidMap.init(aa),
            .lazy_class_attrs = FnvVoidMap.init(aa),
            .arraylist_vars = FnvVoidMap.init(aa),
            .arraylist_aliases = FnvStringMap.init(aa),
            .class_instance_aliases = FnvStringMap.init(aa),
            .dict_vars = FnvVoidMap.init(aa),
            .target_dict_value_type = null,
            .anytype_params = FnvVoidMap.init(aa),
            .narrowed_type_params = FnvStringMap.init(aa),
            .none_default_params = FnvVoidMap.init(aa),
            .mutable_classes = FnvVoidMap.init(aa),
            .error_init_classes = FnvVoidMap.init(aa),
            .unittest_classes = std.ArrayList(TestClassInfo){},
            .test_factories = hashmap_helper.StringHashMap(TestFactoryInfo).init(aa),
            .comptime_evaluator = comptime_eval.ComptimeEvaluator.init(allocator), // Own cleanup
            .import_ctx = null,
            .source_file_path = source_file_path,
            .decorated_functions = std.ArrayList(DecoratedFunction){},
            .import_registry = registry,
            .module_registry = mod_registry,
            .from_imports = std.ArrayList(FromImportInfo){},
            .from_import_needs_allocator = FnvVoidMap.init(aa),
            .functions_needing_allocator = FnvVoidMap.init(aa),
            .async_functions = FnvVoidMap.init(aa),
            .async_function_defs = FnvFuncDefMap.init(aa),
            .vararg_functions = hashmap_helper.StringHashMap(usize).init(aa),
            .vararg_params = FnvVoidMap.init(aa),
            .vararg_loop_vars = FnvVoidMap.init(aa),
            .current_vararg_source = null,
            .vararg_list_sources = hashmap_helper.StringHashMap([]const u8).init(aa),
            .vararg_methods = hashmap_helper.StringHashMap(usize).init(aa),
            .kwarg_functions = FnvVoidMap.init(aa),
            .kwarg_params = FnvVoidMap.init(aa),
            .dict_builtin_vars = FnvVoidMap.init(aa),
            .function_signatures = FnvFuncSigMap.init(aa),
            .imported_modules = FnvVoidMap.init(aa),
            .import_aliases = FnvStringMap.init(aa),
            .module_alias_map = FnvStringMap.init(aa),
            .module_level_from_imports = FnvVoidMap.init(aa),
            .mutation_info = null,
            .pass_analysis_result = null,
            .in_assert_raises_context = false,
            .assert_raises_block_id = 0,
            .current_assert_raises_block_id = 0,
            .general_block_id = 0,
            .control_flow_terminated = false,
            .c_libraries = std.ArrayList([]const u8){},
            .comptime_evals = FnvVoidMap.init(aa),
            .interned_strings = hashmap_helper.StringHashMap(usize).init(aa),
            .intern_list = std.ArrayList([]const u8){},
            .intern_counter = 0,
            .func_local_mutations = FnvVoidMap.init(aa),
            .func_local_aug_assigns = FnvVoidMap.init(aa),
            .func_local_uses = FnvVoidMap.init(aa),
            .global_vars = FnvVoidMap.init(aa),
            .module_level_funcs = FnvVoidMap.init(aa),
            .module_level_vars = FnvVoidMap.init(aa),
            .conditional_var_types = hashmap_helper.StringHashMap([]const u8).init(aa),
            .func_local_vars = FnvVoidMap.init(aa),
            .nested_class_captures = hashmap_helper.StringHashMap([][]const u8).init(aa),
            .mutated_captures = FnvVoidMap.init(aa),
            .nested_class_instances = hashmap_helper.StringHashMap([]const u8).init(aa),
            .nested_class_names = FnvVoidMap.init(aa),
            .nested_class_aliases = FnvStringMap.init(aa),
            .hoisted_local_classes = FnvStringMap.init(aa),
            .current_scope_classes = FnvVoidMap.init(aa),
            .factory_hoisted_classes = FnvStringMap.init(aa),
            .bigint_vars = FnvVoidMap.init(aa),
            .pyvalue_vars = FnvVoidMap.init(aa),
            .imported_class_types = FnvVoidMap.init(aa),
            .nested_class_bases = FnvStringMap.init(aa),
            .nested_class_defs = FnvClassDefMap.init(aa),
            .nested_class_method_needs_alloc = FnvVoidMap.init(aa),
            .nested_class_zig_refs = FnvVoidMap.init(aa),
            .class_type_attrs = FnvStringMap.init(aa),
            .current_class_name = null,
            .current_class_body = null,
            .current_assign_target = null,
            .inside_list_depth = 0,
            .current_class_captures = null,
            .inside_init_method = false,
            .inside_new_method = false,
            .inside_classmethod = false,
            .method_self_is_mutable = false,
            .current_method_first_param = null,
            .current_class_parent = null,
            .class_nesting_depth = 0,
            .method_nesting_depth = 0,
            .inside_method_with_self = false,
            .current_scope_id = 0,
            .inside_defer = false,
            .inside_const_init = false,
            .inside_finally_block = false,
            .current_finally_id = 0,
            .finally_stack = std.ArrayList(FinallyContext){},
            .finally_counter = 0,
            .inside_nested_function = false,
            .nested_function_base_scope = 0,
            .current_function_name = null,
            .current_function_body = null,
            .in_generator_function = false,
            .in_logic_table_class = false,
            .emit_logic_table_exports = false,
            .current_function_returns_pyvalue = false,
            .current_function_can_try = true, // Default to true for functions with error returns
            .inside_try_body = false,
            .in_nameerror_context = false,
            .inside_try_with_finally = false,
            .current_try_finally_id = 0,
            .target_wasm_browser = false,
            .skipped_modules = FnvVoidMap.init(aa),
            .skipped_functions = FnvVoidMap.init(aa),
            .codegen_only_modules = FnvVoidMap.init(aa),
            .c_extension_modules = FnvStringMap.init(aa),
            .needs_c_interop = false,
            .c_extension_root_modules = FnvStringMap.init(aa),
            .c_extension_from_imports = hashmap_helper.StringHashMap(CExtFromImport).init(aa),
            .local_var_types = hashmap_helper.StringHashMap(NativeType).init(aa),
            .local_from_imports = FnvStringMap.init(aa),
            .loop_capture_vars = FnvVoidMap.init(aa),
            .heterogeneous_loop_vars = FnvVoidMap.init(aa),
            .callable_global_vars = FnvVoidMap.init(aa),
            .import_module_vars = FnvVoidMap.init(aa),
            .csv_iterators = FnvVoidMap.init(aa),
            .type_alias_vars = FnvVoidMap.init(aa),
            .type_alias_targets = hashmap_helper.StringHashMap([]const u8).init(aa),
            .hoisted_branch_funcs = FnvVoidMap.init(aa),
            .forward_declared_vars = FnvVoidMap.init(aa),
            .returned_vars = FnvVoidMap.init(aa),
            .call_graph = null,
            .generic_type_params = FnvVoidMap.init(aa),
            .generic_classes = hashmap_helper.StringHashMap(usize).init(aa),
            .ctypes_functions = hashmap_helper.StringHashMap(CTypesFuncInfo).init(aa),
            .debug_writer = null,
            .zig_line_counter = 1,
            .tokens = null,
            .token_lines = null,
            .keyword_raise_count = 0,
            .keyword_assert_count = 0,
            .name_gen = name_gen_mod.init(allocator),
            // Builder initialized to null - will be lazily created when needed
            // This allows gradual migration without breaking existing codegen
            .builder = null,
        };
        return self;
    }

    /// Emit VM fallback from AST node (auto-converts to Python source)
    /// This method allows direct calls via self.emitVMFallback() without importing core.zig
    pub fn emitVMFallback(self: *NativeCodegen, node: ast.Node) CodegenError!void {
        return emitVMFallbackFromAST(self, node);
    }

    pub fn setImportContext(self: *NativeCodegen, ctx: *const @import("c_interop").ImportContext) void {
        self.import_ctx = ctx;
    }

    /// Set debug info writer for recording Python->Zig line mappings
    pub fn setDebugWriter(self: *NativeCodegen, writer: *debug_info.DebugInfoWriter) void {
        self.debug_writer = writer;
    }

    /// Set tokens array for Python line number lookup during debug info generation
    pub fn setTokens(self: *NativeCodegen, toks: []const @import("../../../lexer.zig").Token) void {
        self.tokens = toks;
    }

    /// Get the Python line number for an identifier by looking it up in tokens
    /// Returns null if not found or if tokens are not available
    pub fn getPythonLineForName(self: *NativeCodegen, name: []const u8) ?u32 {
        // Build token line map lazily on first use
        if (self.token_lines == null) {
            if (self.tokens) |toks| {
                self.token_lines = hashmap_helper.StringHashMap(u32).init(self.allocator);
                const lexer_mod = @import("../../../lexer.zig");
                for (toks) |tok| {
                    // Store all identifiers with their line numbers
                    // (def/class names, variable names, function calls, etc.)
                    if (tok.type == lexer_mod.TokenType.Ident) {
                        // Store first occurrence of each identifier
                        if (!self.token_lines.?.contains(tok.lexeme)) {
                            self.token_lines.?.put(tok.lexeme, @intCast(tok.line)) catch continue;
                        }
                    }
                }
            } else {
                return null;
            }
        }

        return self.token_lines.?.get(name);
    }

    /// Record a Python line -> Zig line mapping (if debug info is enabled)
    pub fn recordLineMapping(self: *NativeCodegen, py_line: u32) void {
        if (self.debug_writer) |dw| {
            dw.recordMapping(py_line, self.zig_line_counter) catch {};
        }
    }

    /// Record a line mapping by looking up the Python line for an identifier
    pub fn recordLineMappingForName(self: *NativeCodegen, name: []const u8) void {
        if (self.debug_writer != null) {
            if (self.getPythonLineForName(name)) |py_line| {
                self.recordLineMapping(py_line);
            }
        }
    }

    /// Get Python line number for a specific keyword token type
    /// Searches through tokens to find the Nth occurrence of a keyword
    /// If occurrence is 0, returns the first occurrence
    pub fn getPythonLineForKeyword(self: *NativeCodegen, comptime keyword: @import("../../../lexer.zig").TokenType, occurrence: usize) ?u32 {
        if (self.tokens) |toks| {
            var count: usize = 0;
            for (toks) |tok| {
                if (tok.type == keyword) {
                    if (count == occurrence) {
                        return @intCast(tok.line);
                    }
                    count += 1;
                }
            }
        }
        return null;
    }

    /// Record line mapping for raise statement and increment counter
    pub fn recordRaiseLineMapping(self: *NativeCodegen) void {
        if (self.debug_writer != null) {
            const lexer = @import("../../../lexer.zig");
            if (self.getPythonLineForKeyword(lexer.TokenType.Raise, self.keyword_raise_count)) |py_line| {
                self.recordLineMapping(py_line);
            }
            self.keyword_raise_count += 1;
        }
    }

    /// Record line mapping for assert statement and increment counter
    pub fn recordAssertLineMapping(self: *NativeCodegen) void {
        if (self.debug_writer != null) {
            const lexer = @import("../../../lexer.zig");
            if (self.getPythonLineForKeyword(lexer.TokenType.Assert, self.keyword_assert_count)) |py_line| {
                self.recordLineMapping(py_line);
            }
            self.keyword_assert_count += 1;
        }
    }

    // ============================================================
    // Finally Stack Methods (Nuitka-style code duplication)
    // ============================================================

    /// Push a finally context onto the stack when entering a try-finally block.
    /// Returns the unique ID for this finally block.
    pub fn pushFinallyContext(self: *NativeCodegen, finalbody: []const ast.Node, is_defer: bool) u32 {
        const id = self.finally_counter;
        self.finally_counter += 1;
        const var_name = std.fmt.allocPrint(self.allocator, "__pending_exception_{d}", .{id}) catch "__pending_exception";
        self.finally_stack.append(self.allocator, .{
            .id = id,
            .finalbody = finalbody,
            .pending_exception_var = var_name,
            .is_defer_based = is_defer,
        }) catch {};
        return id;
    }

    /// Pop the topmost finally context from the stack when exiting a try-finally block.
    pub fn popFinallyContext(self: *NativeCodegen) void {
        _ = self.finally_stack.pop();
    }

    /// Emit finally block code inline (for a single context).
    /// Skip if using defer-based approach (defer handles it automatically).
    pub fn emitFinallyInline(self: *NativeCodegen, ctx: FinallyContext) CodegenError!void {
        if (ctx.is_defer_based) return; // Defer handles it

        try self.emitIndent();
        try emitConst(self, "{ // finally (inline)\n");
        self.indent();
        for (ctx.finalbody) |stmt| {
            try self.generateStmt(stmt);
        }
        self.dedent();
        try self.emitIndent();
        try emitConst(self, "}\n");
    }

    /// Emit ALL active finally blocks inline (from innermost to outermost).
    /// Called before return/break/continue/raise statements.
    pub fn emitAllFinallyBlocks(self: *NativeCodegen) CodegenError!void {
        // Execute from innermost to outermost (reverse order)
        var i = self.finally_stack.items.len;
        while (i > 0) {
            i -= 1;
            try self.emitFinallyInline(self.finally_stack.items[i]);
        }
    }

    /// Check if there are any active non-defer finally blocks.
    pub fn hasActiveFinallyBlocks(self: *NativeCodegen) bool {
        for (self.finally_stack.items) |ctx| {
            if (!ctx.is_defer_based) return true;
        }
        return false;
    }

    /// Intern a string literal and return its index
    /// Returns existing index if already interned, or creates new entry
    pub fn internString(self: *NativeCodegen, content: []const u8) !usize {
        // Check if already interned
        if (self.interned_strings.get(content)) |idx| {
            return idx;
        }

        // Add new interned string
        const idx = self.intern_counter;
        const duped = try self.arena.allocator().dupe(u8, content);
        try self.interned_strings.put(duped, idx);
        try self.intern_list.append(self.allocator, duped);
        self.intern_counter += 1;
        return idx;
    }

    /// Generate the intern table at module level
    /// Called at the start of code generation
    pub fn genInternTable(self: *NativeCodegen) !void {
        if (self.intern_list.items.len == 0) return;

        try emitConst(self, "\n// Interned string literals (O(1) equality via pointer comparison)\n");
        try emitConst(self, "const __intern = struct {\n");

        for (self.intern_list.items, 0..) |str, i| {
            try self.emitFmt("    pub const s{d}: []const u8 = \"{s}\";\n", .{ i, str });
        }

        try emitConst(self, "};\n\n");
    }

    /// Get the reference to an interned string by index
    pub fn getInternRef(self: *NativeCodegen, idx: usize) !void {
        try self.emitFmt("__intern.s{d}", .{idx});
    }

    /// Build call graph from module AST for unified function analysis
    /// Call this once before generate() to enable traits-based codegen decisions
    pub fn buildCallGraph(self: *NativeCodegen, module: ast.Node.Module) !void {
        std.debug.print("buildCallGraph() starting...\n", .{});
        self.call_graph = try function_traits.buildCallGraph(module, self.allocator);
        std.debug.print("buildCallGraph() completed.\n", .{});
    }

    /// Query: Should function use state machine async? (has I/O await)
    pub fn shouldUseStateMachineAsync(self: *const NativeCodegen, name: []const u8) bool {
        if (self.call_graph) |*cg| {
            return function_traits.shouldUseStateMachineAsync(cg, name);
        }
        return false;
    }

    /// Query: Does ANY async function in module have I/O?
    /// Used to ensure all async functions use same interface (for gather compatibility)
    pub fn anyAsyncHasIO(self: *const NativeCodegen) bool {
        if (self.call_graph) |*cg| {
            return function_traits.anyAsyncHasIO(cg);
        }
        return false;
    }

    /// Query: Is parameter mutated? (var vs const)
    pub fn isParamMutated(self: *const NativeCodegen, func_name: []const u8, param_idx: usize) bool {
        if (self.call_graph) |*cg| {
            return function_traits.isParamMutated(cg, func_name, param_idx);
        }
        return false;
    }

    /// Query: Does function need error union return type?
    pub fn funcNeedsErrorUnion(self: *const NativeCodegen, name: []const u8) bool {
        if (self.call_graph) |*cg| {
            return function_traits.needsErrorUnion(cg, name);
        }
        return false;
    }

    /// Query: Does function need allocator parameter?
    pub fn funcNeedsAllocator(self: *const NativeCodegen, name: []const u8) bool {
        if (self.call_graph) |*cg| {
            return function_traits.needsAllocator(cg, name);
        }
        return false;
    }

    /// Query: Is function pure? (can be memoized/comptime evaluated)
    pub fn funcIsPure(self: *const NativeCodegen, name: []const u8) bool {
        if (self.call_graph) |*cg| {
            return function_traits.isPure(cg, name);
        }
        return false;
    }

    /// Query: Can function use tail call optimization?
    pub fn funcCanUseTCO(self: *const NativeCodegen, name: []const u8) bool {
        if (self.call_graph) |*cg| {
            return function_traits.canUseTCO(cg, name);
        }
        return false;
    }

    /// Query: Is function a generator?
    pub fn funcIsGenerator(self: *const NativeCodegen, name: []const u8) bool {
        if (self.call_graph) |*cg| {
            return function_traits.isGenerator(cg, name);
        }
        return false;
    }

    /// Query: Is function dead code? (not reachable from entry points)
    pub fn funcIsDeadCode(self: *const NativeCodegen, name: []const u8) bool {
        if (self.call_graph) |*cg| {
            return function_traits.isDeadCode(cg, name);
        }
        return false;
    }

    /// Query: Get async complexity for optimization decisions
    pub fn funcAsyncComplexity(self: *const NativeCodegen, name: []const u8) function_traits.AsyncComplexity {
        if (self.call_graph) |*cg| {
            return function_traits.getAsyncComplexity(cg, name);
        }
        return .trivial;
    }

    /// Query: Check if a variable needs PyValue type (heterogeneous list)
    pub fn varNeedsPyValue(self: *const NativeCodegen, var_name: []const u8) bool {
        if (self.call_graph) |*cg| {
            // Use current function context
            if (self.current_function_name) |func_name| {
                if (cg.functions.get(func_name)) |traits| {
                    return traits.listNeedsPyValue(var_name);
                }
            }
        }
        return false;
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
    /// When inside_nested_function is true, only checks current scope + var_renames
    /// (nested functions have fresh scope - outer vars only visible if captured)
    pub fn isDeclared(self: *NativeCodegen, name: []const u8) bool {
        // Always check hoisted_vars first - these are function-level hoisted declarations
        if (self.hoisted_vars.contains(name)) return true;

        // Check var_renames - this handles TryHelper captured variables and other renames
        // TryHelper creates parameter copies like __local_x_1 and adds x -> __local_x_1 to var_renames
        // These should count as "declared" to prevent redeclaration during tuple unpacking
        if (self.var_renames.contains(name)) return true;

        if (self.inside_nested_function) {
            // Inside nested function: check all scopes from nested_function_base_scope to current
            // This includes variables declared in block scopes (like for loops) within the function
            // but excludes variables from outer (enclosing) function scopes
            return self.symbol_table.isDeclaredFromScopeLevel(name, self.nested_function_base_scope);
        }
        return self.symbol_table.lookup(name) != null;
    }

    /// Check if a variable is declared in ANY scope (ignoring nested function boundaries)
    /// Used for parameter shadowing checks where we need to know if the name exists anywhere
    /// in enclosing scopes (e.g., for loop variables around nested class definitions)
    /// NOTE: This intentionally does NOT check hoisted_vars because hoisted_vars contains
    /// method-local state that gets cleared at method body start. Since signature generation
    /// happens BEFORE body generation, hoisted_vars would contain stale data from the previous method.
    pub fn isDeclaredInAnyScope(self: *NativeCodegen, name: []const u8) bool {
        // Check all scopes via full lookup (ignores nested function boundaries)
        // Don't check hoisted_vars - it's method-local state that isn't valid during signature generation
        return self.symbol_table.lookup(name) != null;
    }

    // =========================================================================
    // Multi-Pass Analysis Helpers
    // =========================================================================
    // These methods delegate to the IR-based pass analysis results when available,
    // providing a unified interface for const/var decisions, hoisting, and captures.

    /// Check if a variable should be declared as const (single assignment, no hoisting)
    /// Uses IR-based pass analysis when available, otherwise defaults to conservative (var)
    pub fn passAnalysisShouldBeConst(self: *NativeCodegen, name: []const u8) bool {
        if (self.pass_analysis_result) |result| {
            return result.shouldBeConst(name);
        }
        // Fallback: conservative (allow mutation)
        return false;
    }

    /// Check if a variable needs hoisting to function scope (Python->Zig scope conversion)
    /// Variables assigned in inner scopes but used in outer scopes need hoisting
    pub fn passAnalysisNeedsHoisting(self: *NativeCodegen, name: []const u8) bool {
        if (self.pass_analysis_result) |result| {
            return result.needsHoisting(name);
        }
        return false;
    }

    /// Get hoisting info for a variable (target scope, source type, init expression)
    pub fn passAnalysisGetHoistInfo(self: *NativeCodegen, name: []const u8) ?pass_analysis.HoistedInfo {
        if (self.pass_analysis_result) |result| {
            return result.getHoistInfo(name);
        }
        return null;
    }

    /// Check if a function is a closure (captures outer scope variables)
    pub fn passAnalysisIsClosure(self: *NativeCodegen, func_name: []const u8) bool {
        if (self.pass_analysis_result) |result| {
            return result.isClosure(func_name);
        }
        return false;
    }

    /// Get closure info for a function (captured variables, forward refs, deferred needs)
    pub fn passAnalysisGetClosureInfo(self: *NativeCodegen, func_name: []const u8) ?pass_analysis.ClosureInfo {
        if (self.pass_analysis_result) |result| {
            return result.getClosureInfo(func_name);
        }
        return null;
    }

    /// Get capture info for a variable (is_mutated, is_nonlocal, capture_type)
    pub fn passAnalysisGetCaptureInfo(self: *NativeCodegen, name: []const u8) ?pass_analysis.CaptureInfo {
        if (self.pass_analysis_result) |result| {
            return result.getCaptureInfo(name);
        }
        return null;
    }

    /// Get declaration order for safe emission (topologically sorted)
    pub fn passAnalysisGetDeclarationOrder(self: *NativeCodegen) []const []const u8 {
        if (self.pass_analysis_result) |result| {
            return result.getDeclarationOrder();
        }
        return &.{};
    }

    /// Pre-scan all star imports in module body to populate module_level_from_imports
    /// This ensures parameter shadowing is correctly detected even when star imports appear
    /// at the end of a file (after function definitions that use shadowing parameter names)
    pub fn prescanStarImports(self: *NativeCodegen, body: []const ast.Node, source_dir: ?[]const u8) CodegenError!void {
        const from_imports = @import("from_imports.zig");

        for (body) |stmt| {
            if (stmt != .import_from) continue;

            const import_from = stmt.import_from;

            // Check if this is a star import
            var has_star = false;
            for (import_from.names) |name| {
                if (std.mem.eql(u8, name, "*")) {
                    has_star = true;
                    break;
                }
            }
            if (!has_star) continue;

            // Handle both relative imports (.fromnumeric) and potentially absolute ones
            // For relative imports, module starts with "." or is empty (bare ".")
            const is_relative = import_from.module.len == 0 or import_from.module[0] == '.';
            if (!is_relative) continue;

            // Extract submodule name (e.g., ".fromnumeric" -> "fromnumeric")
            const submodule = if (std.mem.indexOfScalar(u8, import_from.module, '.')) |idx|
                if (idx + 1 < import_from.module.len) import_from.module[idx + 1 ..] else continue
            else
                continue;

            if (submodule.len == 0) continue;

            // Try to find __all__ list from the source file
            const sdir = source_dir orelse continue;

            // Try {dir}/{submodule}.py first
            const py_file = std.fmt.allocPrint(self.allocator, "{s}/{s}.py", .{ sdir, submodule }) catch continue;
            defer self.allocator.free(py_file);

            var all_list = from_imports.parseAllList(self.allocator, py_file);

            // If not found, try {dir}/{submodule}/__init__.py
            if (all_list == null) {
                const init_file = std.fmt.allocPrint(self.allocator, "{s}/{s}/__init__.py", .{ sdir, submodule }) catch continue;
                defer self.allocator.free(init_file);
                all_list = from_imports.parseAllList(self.allocator, init_file);
            }

            if (all_list) |*list| {
                defer {
                    for (list.items) |item| {
                        self.allocator.free(item);
                    }
                    list.deinit(self.allocator);
                }

                // Pre-register all exported symbols for shadowing detection
                for (list.items) |symbol| {
                    // Skip if already registered
                    if (self.module_level_from_imports.contains(symbol)) continue;
                    // Dupe the string to ensure it lives beyond the defer
                    const duped_symbol = try self.allocator.dupe(u8, symbol);
                    try self.module_level_from_imports.put(duped_symbol, {});
                }
            }
        }
    }

    /// CONSOLIDATED: Check if a parameter name would shadow any ACTUAL declaration
    /// This is the SINGLE SOURCE OF TRUTH for determining if `__shadow` naming is needed.
    /// All codegen that generates function/method parameters should use this.
    ///
    /// Checks (in order):
    /// 1. Module-level function names (self.module_level_funcs)
    /// 2. Module-level variable names (self.module_level_vars)
    /// 3. Imported module names (self.imported_modules)
    /// 4. From-import symbols (self.module_level_from_imports) - e.g., 'deque' from 'from collections import deque'
    ///
    /// NOTE: Does NOT check wouldShadowMethod/wouldShadowModule - those are handled
    /// by zig_keywords.writeParamName with a simple `_` suffix (e.g., "stop" -> "stop_").
    pub fn wouldParamShadow(self: *const NativeCodegen, param_name: []const u8) bool {
        // Check module-level declarations tracked at codegen time
        // These are ACTUAL variables/functions that would be shadowed
        if (self.module_level_funcs.contains(param_name)) return true;
        if (self.module_level_vars.contains(param_name)) return true;
        if (self.imported_modules.contains(param_name)) return true;
        if (self.module_level_from_imports.contains(param_name)) return true;
        // Check import aliases (e.g., "import numpy._core.numeric as N")
        if (self.import_aliases.contains(param_name)) return true;

        return false;
    }

    /// Check if a local variable name would shadow module-level declarations
    /// Similar to wouldParamShadow but also checks for 'main' (the entry point)
    pub fn wouldLocalShadow(self: *const NativeCodegen, name: []const u8) bool {
        // Check for 'main' - the Zig entry point function
        if (std.mem.eql(u8, name, "main")) return true;

        // Use the same checks as wouldParamShadow
        return self.wouldParamShadow(name);
    }

    /// Get a safe local variable name that won't shadow module-level declarations
    /// If the name would shadow, generates a unique name and registers the rename mapping
    /// Returns the safe name to use (original or renamed)
    pub fn getSafeLocalName(self: *NativeCodegen, name: []const u8) CodegenError![]const u8 {
        // If already renamed, return the existing renamed version
        if (self.var_renames.get(name)) |existing| {
            return existing;
        }
        // Check if this name would shadow
        if (self.wouldLocalShadow(name)) {
            // Generate unique name
            const safe_name = try self.freshName(name);
            // Register the rename so references to 'name' use 'safe_name'
            try self.var_renames.put(name, safe_name);
            return safe_name;
        }
        return name;
    }

    /// Check if a variable is an exception variable (from "except X as name:")
    /// Exception variables are typed as runtime.PyException
    pub fn isExceptionVar(self: *NativeCodegen, name: []const u8) bool {
        return self.exception_vars.contains(name);
    }

    /// Check if a variable is captured by any nested class in the current function scope
    /// Used to determine if a function parameter is "used" indirectly via closure
    pub fn isVarCapturedByAnyNestedClass(self: *NativeCodegen, var_name: []const u8) bool {
        var iter = self.nested_class_captures.iterator();
        while (iter.next()) |entry| {
            const captured_vars = entry.value_ptr.*;
            for (captured_vars) |captured| {
                if (std.mem.eql(u8, captured, var_name)) return true;
            }
        }
        return false;
    }

    /// Declare variable in current (innermost) scope with a specific type
    pub fn declareVarWithType(self: *NativeCodegen, name: []const u8, var_type: NativeType) !void {
        try self.symbol_table.declare(name, var_type, true);
    }

    /// Declare variable in current (innermost) scope (legacy - uses unknown type)
    pub fn declareVar(self: *NativeCodegen, name: []const u8) !void {
        try self.symbol_table.declare(name, NativeType.unknown, true);
    }

    /// Get the locally-declared type for a variable (scope-aware)
    /// Returns null if variable not declared in any scope
    pub fn getLocalVarType(self: *NativeCodegen, name: []const u8) ?NativeType {
        return self.symbol_table.getType(name);
    }

    /// Check if a variable has uncertain type confidence (needs PyValue)
    /// Returns true if the variable's type cannot be proven certain at compile time
    /// Uses the Two-Flow Type System: uncertain = use PyValue, certain = use raw Zig types
    ///
    /// Decision hierarchy:
    /// 1. pyvalue_vars (VM fallback) → always uncertain
    /// 2. Type tag .pyvalue/.unknown → always uncertain (runtime type IS PyValue)
    /// 3. Concrete type + uncertain confidence → uncertain (type widening)
    /// 4. Concrete type + certain/untracked confidence → certain
    pub fn isVarUncertain(self: *NativeCodegen, name: []const u8) bool {
        // Variables assigned from VM fallback are always uncertain (return PyValue)
        if (self.pyvalue_vars.contains(name)) {
            return true;
        }
        // Check renamed name too (e.g., line -> __m56_lv_line)
        const renamed_name = self.var_renames.get(name) orelse name;
        if (self.pyvalue_vars.contains(renamed_name)) {
            return true;
        }

        // Check type tags FIRST - if type is explicitly pyvalue or unknown, always uncertain
        // This takes precedence over confidence because the runtime type IS PyValue
        const var_type = self.type_inferrer.getScopedVar(name) orelse
            self.type_inferrer.var_types.get(name);
        if (var_type) |vt| {
            // Type tag indicates PyValue - must use PyValue operations regardless of confidence
            if (vt == .pyvalue or vt == .unknown) {
                return true;
            }

            // Type is concrete (int, float, string, etc.)
            // NOW check confidence - if explicitly uncertain (from widening), treat as uncertain
            // This handles cases like: x = 1; x = "hello" → type widened, confidence degraded
            if (self.type_inferrer.hasTrackedConfidence(name)) {
                return self.type_inferrer.isUncertain(name);
            }
            if (self.type_inferrer.hasTrackedConfidence(renamed_name)) {
                return self.type_inferrer.isUncertain(renamed_name);
            }

            // Concrete type with no tracked confidence → assume certain
            return false;
        }
        // Variable not in type map - don't assume uncertain
        return false;
    }

    /// Check if a variable has certain type confidence (can use raw Zig types)
    /// Returns true if the variable's type is 100% provable at compile time
    pub fn isVarCertain(self: *NativeCodegen, name: []const u8) bool {
        return self.type_inferrer.isCertain(name);
    }

    /// Check if an expression is uncertain (needs PyValue operations)
    /// DRY: Replaces isStringUncertain, isFloatUncertain, isSetUncertain, etc.
    /// Two-Flow: Routes uncertain expressions to PyValue extraction
    pub fn isExprUncertain(self: *NativeCodegen, expr: ast.Node) bool {
        if (expr == .name) {
            return self.isVarUncertain(expr.name.id);
        }
        return false;
    }

    /// Get the TypedValue (type + confidence) for a variable
    /// Returns null if variable not found
    pub fn getTypedVar(self: *NativeCodegen, name: []const u8) ?native_types.TypedValue {
        return self.type_inferrer.getTypedVar(name);
    }

    /// Check if codegen should emit PyValue for a variable assignment
    /// This is the main entry point for the Two-Flow Type System in codegen
    /// When true, emit: const x: runtime.PyValue = runtime.PyValue.from(...);
    /// When false, emit: const x: i64 = ...; (or let Zig infer)
    pub fn shouldUsePyValue(self: *NativeCodegen, name: []const u8) bool {
        // Check confidence level - uncertain types need PyValue
        if (self.type_inferrer.isUncertain(name)) {
            return true;
        }
        // Check if this is a module-level conditional variable declared as PyValue
        // These are variables assigned in both if/else branches with different types
        if (self.conditional_var_types.get(name)) |zig_type| {
            if (std.mem.eql(u8, zig_type, "runtime.PyValue")) {
                return true;
            }
        }
        // Variable is certain - use raw Zig type for performance
        return false;
    }

    /// Determine if an expression needs VM fallback instead of native codegen
    /// Returns true when native codegen would fail or produce incorrect results
    /// Used for universal catch-all: any unsupported construct → VM execution
    pub fn needsVMFallback(self: *NativeCodegen, node: ast.Node) bool {
        switch (node) {
            // Lambda has proper native codegen in lambda.zig (simple, capturing, inline)
            // Don't use VM fallback for lambdas - they're handled natively
            .lambda => return false,

            // Generator expressions use native codegen in comp_genexp.zig
            // They're treated as eager list comprehensions for AOT compilation
            // Using VM fallback breaks local variable access (e.g., `any(ch in lit for ch in 'xyz')`)
            .genexp => return false,

            // Function calls - check if we can determine the return type
            .call => |call| {
                // Method calls on uncertain receivers need fallback
                if (call.func.* == .attribute) {
                    const attr = call.func.attribute;
                    if (attr.value.* == .name) {
                        const var_name = attr.value.name.id;
                        // Imported modules are always known at compile time - let dispatch handle them
                        if (self.import_aliases.contains(var_name)) {
                            return false;
                        }
                        // Direct imports (import X) are also known - let dispatch handle them
                        if (self.imported_modules.contains(var_name)) {
                            return false;
                        }
                        // From-imports (from X import Y) are also known - let dispatch handle them
                        if (self.module_level_from_imports.contains(var_name)) {
                            return false;
                        }
                        // Local from-imports are also known
                        if (self.local_from_imports.contains(var_name)) {
                            return false;
                        }
                        // Nested class names (classes defined inside functions) are known
                        if (self.nested_class_names.contains(var_name)) {
                            return false;
                        }
                        // Builtin type names are always known - don't fall back for them
                        // This handles bool.from_bytes(), int.from_bytes(), str.encode(), etc.
                        const builtin_type_names = [_][]const u8{
                            "bool", "int", "float", "str", "bytes", "list", "dict", "set", "tuple",
                            "frozenset", "complex", "range", "slice", "object", "type",
                        };
                        for (builtin_type_names) |type_name| {
                            if (std.mem.eql(u8, var_name, type_name)) {
                                return false; // Known builtin type - dispatch handles it
                            }
                        }
                        // User-defined class names (start with uppercase) are typically defined in the same file
                        // This handles module-level classes like "B.register(V)" from ABC metaclass
                        if (var_name.len > 0 and std.ascii.isUpper(var_name[0])) {
                            // Check it's not a known builtin type that looks like a class
                            const builtin_types = [_][]const u8{
                                "TypeError", "ValueError", "RuntimeError", "KeyError",
                                "IndexError", "AttributeError", "ZeroDivisionError",
                                "StopIteration", "NotImplementedError", "AssertionError",
                            };
                            var is_exception = false;
                            for (builtin_types) |bt| {
                                if (std.mem.eql(u8, var_name, bt)) {
                                    is_exception = true;
                                    break;
                                }
                            }
                            if (!is_exception) {
                                return false; // Likely a user-defined class
                            }
                        }
                        // EXCEPTION: unittest assertion methods (self.assertEqual, test_self.assertTrue, etc.)
                        // These should be handled by the native dispatch, not VM fallback
                        // Check if var_name is the current method's first param (Python's "self")
                        if (self.current_method_first_param) |first_param| {
                            if (std.mem.eql(u8, var_name, first_param) or std.mem.eql(u8, var_name, "self")) {
                                // Check if method being called is a unittest assertion
                                if (method_categories.isUnittestAssertion(attr.attr)) {
                                    return false; // Native dispatch handles unittest methods
                                }
                            }
                        }
                        // If receiver type is uncertain, check if method can be handled by PyValue dispatch
                        // String methods on uncertain types are handled via PyValue.from(obj).method()
                        if (self.isVarUncertain(var_name)) {
                            const method_name = attr.attr;
                            if (method_categories.isPyValueStringMethod(method_name)) {
                                return false; // Let dispatch handle via PyValue methods
                            }
                            // Float methods on uncertain types - native dispatch extracts float via .asFloat()
                            const pyvalue_float_methods = [_][]const u8{
                                "is_integer", "as_integer_ratio", "hex", "conjugate",
                                "__truediv__", "__rtruediv__", "__floordiv__", "__mod__",
                                "__floor__", "__ceil__", "__trunc__", "__round__",
                            };
                            for (pyvalue_float_methods) |pyv_method| {
                                if (std.mem.eql(u8, method_name, pyv_method)) {
                                    return false; // Let dispatch handle via float methods with .asFloat()
                                }
                            }
                            return true;
                        }
                    }
                }
                // Direct function calls - check if it's a known builtin
                if (call.func.* == .name) {
                    const func_name = call.func.name.id;
                    // Known builtins that are fully implemented natively
                    const native_builtins = [_][]const u8{
                        "len",     "range",    "print",    "str",      "int",
                        "float",   "bool",     "list",     "dict",     "set",
                        "tuple",   "type",     "abs",      "min",      "max",
                        "sum",     "sorted",   "reversed", "enumerate", "zip",
                        "repr",    "hash",     "id",       "ord",      "chr",
                        "hex",     "oct",      "bin",      "isinstance", "issubclass",
                        "hasattr", "getattr",  "setattr",  "delattr",  "callable",
                        "iter",    "next",     "open",     "input",    "format",
                    };
                    for (native_builtins) |builtin| {
                        if (std.mem.eql(u8, func_name, builtin)) {
                            return false; // Natively supported
                        }
                    }
                    // Check if it's a user-defined function with known signature
                    if (self.function_signatures.get(func_name) != null) {
                        return false; // User function, can compile
                    }
                    // Unknown function - check if it's a class constructor
                    if (func_name.len > 0 and std.ascii.isUpper(func_name[0])) {
                        // Class constructors are handled natively
                        return false;
                    }
                    // Unknown callable - might need fallback
                    // But don't fall back for imported module functions
                    if (self.import_aliases.contains(func_name)) {
                        return false;
                    }
                }
                return false;
            },

            // Subscript on uncertain container
            // IMPORTANT: PyValue variables should NOT fall back to VM eval!
            // VM eval can't access local Zig variables. Instead, subscript.zig
            // handles PyValue subscript/slice natively using .pyAt(), .pySlice(), etc.
            .subscript => |sub| {
                if (sub.value.* == .name) {
                    const var_name = sub.value.name.id;
                    // PyValue variables are handled natively in subscript.zig
                    // Don't fall back - we can generate native PyValue subscript ops
                    if (self.pyvalue_vars.contains(var_name)) {
                        return false; // Native handling via subscript.zig
                    }
                    const renamed_name = self.var_renames.get(var_name) orelse var_name;
                    if (self.pyvalue_vars.contains(renamed_name)) {
                        return false; // Native handling via subscript.zig
                    }
                    // Only fall back for truly uncertain variables that aren't PyValue
                    if (self.isVarUncertain(var_name)) {
                        return true;
                    }
                }
                return false;
            },

            // Attribute access on uncertain object
            .attribute => |attr| {
                if (attr.value.* == .name) {
                    const var_name = attr.value.name.id;
                    // Special cases: 'self' is always certain within a class
                    if (std.mem.eql(u8, var_name, "self")) {
                        return false;
                    }
                    // Renamed variables are being specially handled by codegen
                    // (e.g., other -> other_converted) - let genAttribute use the rename
                    if (self.var_renames.contains(var_name)) {
                        return false;
                    }
                    // Local variables declared in current function are known to exist
                    // (e.g., x = self/other; return x.__num) - use direct access
                    if (self.func_local_vars.contains(var_name)) {
                        return false;
                    }
                    // Imported modules are always known at compile time - let dispatch handle them
                    // This prevents os.curdir, math.pi etc from falling back to VM
                    if (self.imported_modules.contains(var_name)) {
                        return false;
                    }
                    if (self.import_aliases.contains(var_name)) {
                        return false;
                    }
                    // From-imports (from X import Y) are also known - let genAttribute handle them
                    // This handles os_helper.TESTFN when os_helper comes from "from test.support import os_helper"
                    if (self.module_level_from_imports.contains(var_name)) {
                        return false;
                    }
                    if (self.local_from_imports.contains(var_name)) {
                        return false;
                    }
                    // Exception variables (from `except X as e:`) are handled natively
                    // Don't fall back to VM - it can't access local Zig variables
                    if (self.exception_vars.contains(var_name)) {
                        return false;
                    }
                    if (self.isVarUncertain(var_name)) {
                        return true;
                    }
                }
                return false;
            },

            // Named expressions (walrus operator) - generally OK natively
            .named_expr => return false,

            // Match statements need fallback for complex patterns
            .match_stmt => return true,

            // Everything else is handled natively
            else => return false,
        }
    }

    /// Infer expression type with scope-aware variable type lookup
    /// For variables, prefers local scope type over global type inferrer
    /// This prevents cross-function type pollution from widened types
    pub fn inferExprScoped(self: *NativeCodegen, node: ast.Node) !NativeType {
        // For name nodes, check local scope first
        if (node == .name) {
            const original_name = node.name.id;

            // Check for Python singletons first (before any variable lookup)
            if (std.mem.eql(u8, original_name, "True") or std.mem.eql(u8, original_name, "False")) {
                return .@"bool";
            }
            if (std.mem.eql(u8, original_name, "None")) {
                return .none;
            }

            // Check if variable has been renamed (e.g., loop capture line -> __loop_line)
            const renamed_name = self.var_renames.get(original_name) orelse original_name;
            // Check if this variable was assigned from VM fallback (returns PyValue)
            // Must check FIRST since VM fallback reassignment (line = line.strip())
            // overrides the original loop capture type (string -> PyValue)
            if (self.pyvalue_vars.contains(original_name) or self.pyvalue_vars.contains(renamed_name)) {
                return .pyvalue;
            }
            // Check if this variable was assigned from a BigInt expression
            if (self.bigint_vars.contains(renamed_name)) {
                return .bigint;
            }
            // Check symbol table for locally-declared types (e.g., loop vars)
            if (self.symbol_table.getType(renamed_name)) |local_type| {
                // Only use local type if it's not unknown
                if (local_type != .unknown) {
                    return local_type;
                }
            }
            // Check type inferrer's scoped map for the current function scope
            // Use ORIGINAL name since that's what was stored during type inference
            // This prevents type pollution from variables with the same name in other scopes
            if (self.current_function_name) |func_name| {
                if (self.getVarTypeInScope(func_name, original_name)) |scoped_type| {
                    if (scoped_type != .unknown) {
                        return scoped_type;
                    }
                }
            }
            // Also check type inferrer's current scope (for nested functions with scope set)
            // Check RENAMED name first (e.g., __m56_lv_line for reassigned loop capture)
            // This ensures VM fallback variables get their correct PyValue type
            if (self.type_inferrer.getScopedVar(renamed_name)) |scoped_type| {
                if (scoped_type != .unknown) {
                    return scoped_type;
                }
            }
            // Then check original name as fallback
            if (!std.mem.eql(u8, renamed_name, original_name)) {
                if (self.type_inferrer.getScopedVar(original_name)) |scoped_type| {
                    if (scoped_type != .unknown) {
                        return scoped_type;
                    }
                }
            }
            // Check global var_types as final fallback for module-level variables
            // These are truly global (e.g., JUST_SHOW_HASH_RESULTS = False at module level)
            // and should be visible inside functions
            if (self.type_inferrer.var_types.get(original_name)) |var_type| {
                if (var_type != .unknown) {
                    return var_type;
                }
            }
            // Check if this is a nested class instance (e.g., x = X() where X is defined locally)
            // Check both renamed name and original name since register happens before rename
            if (self.nested_class_instances.get(renamed_name)) |class_name| {
                return .{ .class_instance = class_name };
            }
            if (self.nested_class_instances.get(original_name)) |class_name| {
                return .{ .class_instance = class_name };
            }
            // Check if this is "self" inside a class method - refers to current class instance
            if (std.mem.eql(u8, original_name, "self")) {
                if (self.current_class_name) |class_name| {
                    return .{ .class_instance = class_name };
                }
            }
            // If name wasn't found in local scope with a known type, it might be
            // a function parameter generated as anytype - return unknown to be safe
            // This covers both null and .unknown returns from getType()
            return .unknown;
        }

        // For calls to nested classes, return class_instance with the class name
        if (node == .call) {
            if (node.call.func.* == .name) {
                const func_name = node.call.func.name.id;
                if (self.nested_class_names.contains(func_name)) {
                    return .{ .class_instance = func_name };
                }
                // Also check for top-level class constructors (uppercase names)
                if (func_name.len > 0 and std.ascii.isUpper(func_name[0])) {
                    // Check if this is the current class being generated
                    if (self.current_class_name) |ccn| {
                        if (std.mem.eql(u8, func_name, ccn)) {
                            return .{ .class_instance = func_name };
                        }
                    }
                }
            }
            // Check for module function calls (e.g., test_mymodule.add())
            if (node.call.func.* == .attribute) {
                const attr = node.call.func.attribute;
                if (attr.value.* == .name) {
                    const module_name = attr.value.name.id;
                    const func_name = attr.attr;
                    // Check module registry for return type
                    if (self.module_registry.lookupFunction(module_name, func_name)) |traits| {
                        // Convert TypeHint to NativeType
                        if (traits.return_type_hint) |hint| {
                            return typeHintToNativeType(hint);
                        }
                    }
                }
            }
        }

        // For attribute access (e.g., self.__num), look up field type if base is class instance
        if (node == .attribute) {
            const attr = node.attribute;
            if (attr.value.* == .name) {
                const base_name = attr.value.name.id;
                const attr_name = attr.attr;

                // Check if base is "self" inside a class method
                if (std.mem.eql(u8, base_name, "self")) {
                    if (self.current_class_name) |class_name| {
                        // Look up field type in class_fields registry
                        if (self.type_inferrer.class_fields.get(class_name)) |class_info| {
                            if (class_info.fields.get(attr_name)) |field_type| {
                                return field_type;
                            }
                        }
                    }
                }

                // Check if base is a known class instance variable
                const base_type = try self.inferExprScoped(attr.value.*);
                if (base_type == .class_instance) {
                    const class_name = base_type.class_instance;
                    // Look up field type in class_fields registry
                    if (self.type_inferrer.class_fields.get(class_name)) |class_info| {
                        if (class_info.fields.get(attr_name)) |field_type| {
                            return field_type;
                        }
                    }
                }
            }
        }

        // For unary ops, recursively check the operand
        if (node == .unaryop) {
            const operand_type = try self.inferExprScoped(node.unaryop.operand.*);
            // If operand is unknown, result is unknown
            if (operand_type == .unknown) return .unknown;
            // If operand is bigint, result is bigint (for USub/UAdd)
            if (operand_type == .bigint) return .bigint;
        }

        // For binops, check both operands
        if (node == .binop) {
            const left_type = try self.inferExprScoped(node.binop.left.*);
            const right_type = try self.inferExprScoped(node.binop.right.*);
            // If either is unknown, result is unknown
            if (left_type == .unknown or right_type == .unknown) return .unknown;
            // If either is bigint, result is bigint
            if (left_type == .bigint or right_type == .bigint) return .bigint;
        }

        // Fall back to global type inferrer
        return self.type_inferrer.inferExpr(node);
    }

    /// Convert function_traits.TypeHint to NativeType
    /// Note: For container types (list, dict, tuple) we return unknown since
    /// we don't track element types in TypeHint. The key benefit is for
    /// primitive types: int, float, bool, string which are most common.
    fn typeHintToNativeType(hint: function_traits.TypeHint) NativeType {
        return switch (hint) {
            .void => .none,
            .int => .{ .int = .bounded },
            .float => .float,
            .bool => .bool,
            .string => .{ .string = .runtime },
            .none => .none,
            // Container types don't have element type info in TypeHint
            .list, .dict, .tuple, .object, .any => .unknown,
        };
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

    /// Check if variable is an ArrayList alias (pointer to another ArrayList)
    pub fn isArrayListAlias(self: *NativeCodegen, name: []const u8) bool {
        return self.arraylist_aliases.contains(name);
    }

    /// Get the original ArrayList name for an alias, or null if not an alias
    pub fn getArrayListAliasTarget(self: *NativeCodegen, name: []const u8) ?[]const u8 {
        return self.arraylist_aliases.get(name);
    }

    /// Check if variable is a class instance alias (pointer to another class instance)
    pub fn isClassInstanceAlias(self: *NativeCodegen, name: []const u8) bool {
        return self.class_instance_aliases.contains(name);
    }

    /// Get the original class instance name for an alias, or null if not an alias
    pub fn getClassInstanceAliasTarget(self: *NativeCodegen, name: []const u8) ?[]const u8 {
        return self.class_instance_aliases.get(name);
    }

    /// Check if variable is a dict (needs .get()/.put() for subscript access)
    pub fn isDictVar(self: *NativeCodegen, name: []const u8) bool {
        return self.dict_vars.contains(name);
    }

    /// Look up async function definition for complexity analysis
    pub fn lookupAsyncFunction(self: *NativeCodegen, name: []const u8) ?ast.Node.FunctionDef {
        return self.async_function_defs.get(name);
    }

    // DEPRECATED: emit/emitFmt have been removed - use emitConst helper or builder APIs
    // All code should use the ZigBuilder pattern for structured code generation

    /// Get an ExprEmitter for safe expression wrapping
    /// Use for parenthesization, catch handling, and labeled blocks
    pub fn exprEmitter(self: *NativeCodegen) expr_emitter.ExprEmitter {
        return expr_emitter.ExprEmitter{ .codegen = self };
    }

    /// Emit a unique block label (e.g., "os_dirname_blk_0", "os_dirname_blk_1")
    /// Returns the block ID for use in break statements
    pub fn emitUniqueBlockLabel(self: *NativeCodegen, comptime prefix: []const u8) CodegenError!u32 {
        const block_id = self.general_block_id;
        self.general_block_id += 1;
        try emitFmtConst(self, prefix ++ "_blk_{d}", .{block_id});
        return block_id;
    }

    /// Emit a break statement with a unique block ID
    pub fn emitBreakToBlock(self: *NativeCodegen, comptime prefix: []const u8, block_id: u32) CodegenError!void {
        try emitFmtConst(self, "break :" ++ prefix ++ "_blk_{d}", .{block_id});
    }

    /// Generate a fresh unique name using the unified NameGen system
    /// Use this for ALL generated names (variables, labels, temps) to prevent collisions
    /// Example: freshName("set") -> "__m5_set", freshName("item") -> "__m6_item"
    pub fn freshName(self: *NativeCodegen, hint: []const u8) ![]const u8 {
        return self.name_gen.fresh(hint);
    }

    /// Get next unique ID for inline emission (doesn't allocate string)
    /// Use with emitFmt: emitFmt("blk_{d}", .{self.nextNameId()})
    pub fn nextNameId(self: *NativeCodegen) usize {
        return self.name_gen.nextId();
    }

    /// Get or create the structured ZigBuilder (lazy initialization)
    /// Use this during Phase 1 migration to access type-safe codegen APIs
    /// The builder can coexist with existing emit()/emitFmt() calls
    /// NOTE: The builder shares the same NameGen as NativeCodegen for unified ID generation
    pub fn getBuilder(self: *NativeCodegen) CodegenError!*builder_mod.ZigBuilder {
        if (self.builder) |b| {
            // Sync builder's indent level with codegen's indent level
            b.indent_level = self.indent_level;
            return b;
        }

        // Lazy initialization - create builder on first use with shared NameGen
        const b = try self.allocator.create(builder_mod.ZigBuilder);
        b.* = try builder_mod.ZigBuilder.initWithNameGen(self.allocator, &self.name_gen);
        // Initialize builder's indent level to match codegen's current indent level
        b.indent_level = self.indent_level;
        self.builder = b;
        return b;
    }

    /// Get the builder's type pool for creating ZigType references
    /// Returns null if builder hasn't been initialized yet
    pub fn getTypePool(self: *NativeCodegen) ?*builder_mod.TypePool {
        if (self.builder) |b| {
            return b.getTypePool();
        }
        return null;
    }

    // ============================================================
    // exprToValue - Bridge from AST expressions to ZigValue
    // ============================================================
    //
    // This is the key integration point for structured codegen.
    // Converts AST expressions to ZigValues with type confidence,
    // enabling the builder's type-safe comparison/assertion APIs.

    /// Convert an AST expression to a ZigValue with type confidence
    /// This is the bridge between AST-based codegen and structured builder APIs.
    ///
    /// Returns:
    /// - .certain_* variants for known types (literals, annotated variables)
    /// - .uncertain_pyvalue for unknown types (user functions, subscripts)
    /// - .raw_expr for complex expressions that need to be emitted as-is
    ///
    /// Usage:
    ///   const left_val = try self.exprToValue(left_expr);
    ///   const right_val = try self.exprToValue(right_expr);
    ///   try builder.emitComparison(.eq, left_val, right_val);
    pub fn exprToValue(self: *NativeCodegen, node: ast.Node) CodegenError!builder_mod.ZigValue {
        switch (node) {
            .constant => |c| {
                switch (c.value) {
                    .int => |i| return builder_mod.ZigValue.int(i),
                    .float => |f| return builder_mod.ZigValue.float(f),
                    .string => |s| return builder_mod.ZigValue.string(s),
                    .bool => |b| return builder_mod.ZigValue.boolean(b),
                    .none => return builder_mod.ZigValue.null_(),
                    .bytes => |s| return builder_mod.ZigValue.bytes(s),
                    .bigint, .complex => {
                        // For bigint/complex: use captureExpr for proper builder save/restore
                        return try self.captureExpr(node);
                    },
                }
            },
            .name => |n| {
                const orig_name = n.id;

                // Check for Python singletons first (before renaming)
                if (std.mem.eql(u8, orig_name, "True")) {
                    return builder_mod.ZigValue.boolean(true);
                }
                if (std.mem.eql(u8, orig_name, "False")) {
                    return builder_mod.ZigValue.boolean(false);
                }
                if (std.mem.eql(u8, orig_name, "None")) {
                    return builder_mod.ZigValue.null_();
                }
                if (std.mem.eql(u8, orig_name, "NotImplemented")) {
                    return builder_mod.ZigValue.raw("runtime.Lib.types.NotImplemented");
                }
                if (std.mem.eql(u8, orig_name, "Ellipsis")) {
                    return builder_mod.ZigValue.raw("runtime.Lib.types.Ellipsis");
                }

                // Apply var_renames (same logic as expressions.zig)
                // Comprehension/param renames take precedence over func_local_vars
                const name = blk: {
                    if (self.var_renames.get(orig_name)) |renamed| {
                        // Comprehension loop variables (__comp_*) MUST shadow local vars
                        if (std.mem.startsWith(u8, renamed, "__comp_")) break :blk renamed;
                        // Parameter renames (__m*_p_*) MUST apply even for func_local_vars
                        if (std.mem.startsWith(u8, renamed, "__m") and std.mem.indexOf(u8, renamed, "_p_") != null) break :blk renamed;
                        // Mutable param copies (__m*_v_*)
                        if (std.mem.startsWith(u8, renamed, "__m") and std.mem.indexOf(u8, renamed, "_v_") != null) break :blk renamed;
                        // Closure captures (__m*_c_*)
                        if (std.mem.startsWith(u8, renamed, "__m") and std.mem.indexOf(u8, renamed, "_c_") != null) break :blk renamed;
                        // Shadow variables for type-changing assignments (__m*_s_*) - e.g., x /= 2 changes int to float
                        if (std.mem.startsWith(u8, renamed, "__m") and std.mem.indexOf(u8, renamed, "_s_") != null) break :blk renamed;
                        // Local variable renames (__m*_l_*) - e.g., kwargs -> __m41_l_kwargs
                        if (std.mem.startsWith(u8, renamed, "__m") and std.mem.indexOf(u8, renamed, "_l_") != null) break :blk renamed;
                        // Parameter renames with underscore suffix (e.g., stop -> stop_) for method/module shadowing
                        // These MUST apply even for func_local_vars to maintain consistency with signature
                        if (std.mem.endsWith(u8, renamed, "_") and renamed.len == orig_name.len + 1) break :blk renamed;
                        // Parameter renames with _param suffix (e.g., stop -> stop_param) for default params
                        if (std.mem.endsWith(u8, renamed, "_param")) break :blk renamed;
                    }
                    // Local vars/params take precedence - don't rename them
                    if (self.func_local_vars.contains(orig_name)) break :blk orig_name;
                    // Apply other renames
                    if (self.var_renames.get(orig_name)) |renamed| break :blk renamed;
                    break :blk orig_name;
                };

                // Handle nested class self-reference: when inside a class and referencing that class by name
                // The class name maps to @This() because Zig doesn't allow referencing a const before it's defined
                // (same logic as expressions.zig genName)
                if (self.current_class_name) |class_name| {
                    if (std.mem.eql(u8, name, class_name)) {
                        return builder_mod.ZigValue.raw("@This()");
                    }
                }

                // Check type confidence from inferrer
                if (self.type_inferrer.getTypedVar(name)) |typed| {
                    if (typed.confidence == .uncertain or self.pyvalue_vars.contains(name)) {
                        // Uncertain vars: capture name as raw, will be wrapped in PyValue.from() by builder
                        return builder_mod.ZigValue.raw(name);
                    }
                }

                // Check if it's a PyValue variable
                if (self.pyvalue_vars.contains(name)) {
                    // PyValue vars: capture name as raw
                    return builder_mod.ZigValue.raw(name);
                }

                // Check for Python primitive type names first (int, float, bool)
                // These map directly to Zig types and must be emitted raw to avoid escaping
                // (e.g., 'bool' is a Zig keyword, would become @"bool" if not handled)
                const primitive_types = std.StaticStringMap([]const u8).initComptime(.{
                    .{ "int", "i64" },
                    .{ "float", "f64" },
                    .{ "bool", "bool" },
                });
                if (primitive_types.get(orig_name)) |zig_type| {
                    return builder_mod.ZigValue.raw(zig_type);
                }

                // Check for Python builtin type names (list, dict, etc.)
                // These should be emitted as runtime.builtins.* references
                const builtin_types = std.StaticStringMap([]const u8).initComptime(.{
                    .{ "list", "runtime.builtins.list" },
                    .{ "dict", "runtime.builtins.dict" },
                    .{ "set", "runtime.builtins.set" },
                    .{ "tuple", "runtime.builtins.tuple" },
                    .{ "str", "runtime.builtins.str_factory" },
                    .{ "bytes", "runtime.builtins.bytes_factory" },
                    .{ "object", "runtime.builtins.object" },
                });
                if (builtin_types.get(orig_name)) |zig_name| {
                    return builder_mod.ZigValue.raw(zig_name);
                }

                // Check for Python exception types - emit with runtime. prefix
                // e.g., TypeError -> runtime.TypeError
                if (shared_maps.RuntimeExceptions.has(orig_name)) {
                    var buf: [256]u8 = undefined;
                    const full_name = std.fmt.bufPrint(&buf, "runtime.{s}", .{orig_name}) catch orig_name;
                    return builder_mod.ZigValue.raw(try self.arena.allocator().dupe(u8, full_name));
                }

                // Disambiguate module-level references that conflict with module wrapper struct name
                // E.g., in version.py: `version` -> `_version` when module is also named `version`
                const final_name = if (self.current_function_name == null and self.isModuleNameConflict(name))
                    self.getModuleLevelName(name)
                else
                    name;

                // Return named reference (will be emitted as variable name)
                return builder_mod.ZigValue.fromName(final_name);
            },
            // Binary operations - use builder.binOp for type-aware emission
            .binop => |b| {
                // Special cases that need complex handling - fall back to captureExpr
                // String formatting (%), BigInt ops, collection ops, etc.
                if (b.op == .Mod or b.op == .Pow or b.op == .MatMul or
                    b.op == .FloorDiv)
                {
                    return try self.captureExpr(node);
                }

                // Check if operands might need special handling (strings, lists, etc.)
                const left_type = self.inferExprScoped(b.left.*) catch .unknown;
                const right_type = self.inferExprScoped(b.right.*) catch .unknown;

                // String/collection operations need special handling
                if (string_traits.isStringLike(left_type) or string_traits.isStringLike(right_type) or
                    container_traits.isList(left_type) or container_traits.isList(right_type) or
                    container_traits.isTuple(left_type) or container_traits.isTuple(right_type) or
                    container_traits.isDict(left_type) or container_traits.isDict(right_type))
                {
                    return try self.captureExpr(node);
                }

                // BigInt operations - create ZigValue.bigint variant for builder dispatch
                if (bigint_ops.needsBigInt(left_type) or bigint_ops.needsBigInt(right_type)) {
                    // For now, use captureExpr - full migration requires creating BigIntValue
                    // TODO: Create proper ZigValue.bigint variants for full builder dispatch
                    return try self.captureExpr(node);
                }

                // UnifiedInt operations - create ZigValue.unified_int variant for builder dispatch
                if (unified_int_ops.isUnifiedInt(left_type) or unified_int_ops.isUnifiedInt(right_type)) {
                    // For now, use captureExpr - full migration requires creating UnifiedIntValue
                    // TODO: Create proper ZigValue.unified_int variants for full builder dispatch
                    return try self.captureExpr(node);
                }

                // Boolean with bitwise ops need special handling (bool & int requires cast)
                const is_bitwise = (b.op == .BitAnd or b.op == .BitOr or b.op == .BitXor or
                    b.op == .LShift or b.op == .RShift);
                if (is_bitwise and (left_type == .@"bool" or right_type == .@"bool")) {
                    return try self.captureExpr(node);
                }

                // Complex numbers need special handling
                if (left_type == .complex or right_type == .complex) {
                    return try self.captureExpr(node);
                }

                // Class instances need dunder method dispatch (__add__, __radd__, etc.)
                // But NOT for primitive field access like self.__num where the field has a concrete type
                if (type_traits.isClassInstance(left_type) or type_traits.isClassInstance(right_type)) {
                    // Check if this is actually attribute access on a class with known field types
                    // In that case, the field types should be used, not class_instance
                    const left_is_field = if (b.left.* == .attribute) blk: {
                        const attr = b.left.attribute;
                        if (attr.value.* == .name) {
                            const base_name = attr.value.name.id;
                            // Check if base is self or known class instance
                            if (std.mem.eql(u8, base_name, "self")) {
                                if (self.current_class_name) |class_name| {
                                    if (self.type_inferrer.class_fields.get(class_name)) |class_info| {
                                        if (class_info.fields.get(attr.attr)) |field_type| {
                                            // Has known field type - not a class_instance operation
                                            break :blk field_type != .class_instance and field_type != .unknown;
                                        }
                                    }
                                }
                            } else {
                                // Check if base is a known class instance variable
                                const var_type = self.type_inferrer.getScopedVar(base_name) orelse
                                    self.type_inferrer.var_types.get(base_name);
                                if (var_type) |vt| {
                                    if (vt == .class_instance) {
                                        const class_name = vt.class_instance;
                                        if (self.type_inferrer.class_fields.get(class_name)) |class_info| {
                                            if (class_info.fields.get(attr.attr)) |field_type| {
                                                break :blk field_type != .class_instance and field_type != .unknown;
                                            }
                                        }
                                    }
                                }
                            }
                        }
                        break :blk false;
                    } else false;

                    const right_is_field = if (b.right.* == .attribute) blk: {
                        const attr = b.right.attribute;
                        if (attr.value.* == .name) {
                            const base_name = attr.value.name.id;
                            if (std.mem.eql(u8, base_name, "self")) {
                                if (self.current_class_name) |class_name| {
                                    if (self.type_inferrer.class_fields.get(class_name)) |class_info| {
                                        if (class_info.fields.get(attr.attr)) |field_type| {
                                            break :blk field_type != .class_instance and field_type != .unknown;
                                        }
                                    }
                                }
                            } else {
                                const var_type = self.type_inferrer.getScopedVar(base_name) orelse
                                    self.type_inferrer.var_types.get(base_name);
                                if (var_type) |vt| {
                                    if (vt == .class_instance) {
                                        const class_name = vt.class_instance;
                                        if (self.type_inferrer.class_fields.get(class_name)) |class_info| {
                                            if (class_info.fields.get(attr.attr)) |field_type| {
                                                break :blk field_type != .class_instance and field_type != .unknown;
                                            }
                                        }
                                    }
                                }
                            }
                        }
                        break :blk false;
                    } else false;

                    // If BOTH operands are field accesses with primitive types, skip class_instance fallback
                    if (left_is_field and right_is_field) {
                        // Continue to builder path - don't fall back to captureExpr
                    } else if (!type_traits.isClassInstance(left_type) and right_is_field) {
                        // Left is primitive, right is field - continue
                    } else if (left_is_field and !type_traits.isClassInstance(right_type)) {
                        // Left is field, right is primitive - continue
                    } else {
                        return try self.captureExpr(node);
                    }
                }

                // Unknown types need special handling (PyValue ops, class dunders, etc.)
                if (left_type == .unknown or right_type == .unknown) {
                    return try self.captureExpr(node);
                }

                // Simple arithmetic on primitives - use builder
                const left_val = try self.exprToValue(b.left.*);
                const right_val = try self.exprToValue(b.right.*);

                // Convert AST operator to builder BinOp
                const bin_op: builder_mod.BinOp = switch (b.op) {
                    .Add => .add,
                    .Sub => .sub,
                    .Mult => .mul,
                    .Div => .div,
                    .FloorDiv => .floor_div,
                    .Mod => .mod,
                    .Pow => .pow,
                    .BitAnd => .bit_and,
                    .BitOr => .bit_or,
                    .BitXor => .bit_xor,
                    .LShift => .lshift,
                    .RShift => .rshift,
                    .MatMul => .mul,
                };

                // Create binop_result ZigValue with proper confidence tracking
                const builder = try self.getBuilder();
                return try builder.binOp(bin_op, left_val, right_val);
            },

            // Unary operations - use builder.unaryOp for type-aware emission
            .unaryop => |u| {
                // Check operand type for special handling
                const operand_type = self.inferExprScoped(u.operand.*) catch .unknown;

                // Complex, BigInt, UnifiedInt, unknown need special handling via captureExpr
                // These types don't support native Zig operators directly
                if (operand_type == .complex or
                    operand_type == .unknown or
                    bigint_ops.needsBigInt(operand_type) or
                    unified_int_ops.isUnifiedInt(operand_type))
                {
                    return try self.captureExpr(node);
                }

                // Boolean with negation (-), positive (+), or invert (~) needs special handling
                // Python allows -True = -1, ~True = -2, but Zig doesn't allow these on bool
                if (operand_type == .@"bool" and (u.op == .USub or u.op == .UAdd or u.op == .Invert)) {
                    return try self.captureExpr(node);
                }

                // For bitwise not (~), operand must be integer (not comptime_int literal)
                // Check if it's a literal (constant node)
                if (u.op == .Invert) {
                    switch (u.operand.*) {
                        .constant => {
                            // Literals are comptime_int, bitwise not doesn't work on them directly
                            return try self.captureExpr(node);
                        },
                        else => {},
                    }
                }

                const operand_val = try self.exprToValue(u.operand.*);

                const unary_op: builder_mod.UnaryOp = switch (u.op) {
                    .USub => .neg,
                    .UAdd => .pos,
                    .Invert => .bit_not,
                    .Not => .not_,
                };

                const builder = try self.getBuilder();
                return try builder.unaryOp(unary_op, operand_val);
            },

            // Comparisons - return boolean (comparisons always produce bool)
            .compare => |c| {
                // For simple single comparisons, we can track it's a boolean
                // For chained comparisons, still a boolean
                if (c.ops.len == 1) {
                    // Single comparison: left op right -> bool
                    const left_val = try self.exprToValue(c.left.*);
                    const right_val = try self.exprToValue(c.comparators[0]);

                    const comp_op: builder_mod.BinOp = switch (c.ops[0]) {
                        .Eq => .eq,
                        .NotEq => .ne,
                        .Lt => .lt,
                        .LtEq => .le,
                        .Gt => .gt,
                        .GtEq => .ge,
                        .In => .in,
                        .NotIn => .not_in,
                        .Is => .is,
                        .IsNot => .is_not,
                    };

                    const builder = try self.getBuilder();
                    return try builder.binOp(comp_op, left_val, right_val);
                }
                // Chained comparison - fallback to captureExpr for now
                return try self.captureExpr(node);
            },

            // Boolean operations (and/or) - proper BoolOpValue with type tracking
            .boolop => |b| {
                // Handle single value case
                if (b.values.len < 2) {
                    if (b.values.len == 1) {
                        return try self.exprToValue(b.values[0]);
                    }
                    return try self.captureExpr(node);
                }

                // Convert all operand values
                var values = try self.allocator.alloc(builder_mod.ZigValue, b.values.len);
                var has_uncertain = false;
                for (b.values, 0..) |val, i| {
                    values[i] = try self.exprToValue(val);
                    if (values[i].confidence() == .uncertain) {
                        has_uncertain = true;
                    }
                }

                const op_kind: builder_mod.BoolOpValue.BoolOpKind = switch (b.op) {
                    .And => .and_,
                    .Or => .or_,
                };

                return builder_mod.ZigValue{
                    .boolop = .{
                        .op = op_kind,
                        .values = values,
                        .confidence = if (has_uncertain) .uncertain else .certain,
                    },
                };
            },

            // Function calls - infer return type confidence, use captureExprTyped
            .call => |c| {
                // Use inferCallTyped to get return type confidence
                const calls = @import("../../../analysis/native_types/calls.zig");
                const typed_result = calls.inferCallTyped(
                    self.allocator,
                    &self.type_inferrer.var_types,
                    &self.type_inferrer.class_fields,
                    &self.type_inferrer.func_return_types,
                    c,
                    self.type_inferrer,
                ) catch |err| switch (err) {
                    error.OutOfMemory => return error.OutOfMemory,
                };

                // Convert analysis TypeConfidence to builder TypeConfidence
                const confidence: builder_mod.TypeConfidence = switch (typed_result.confidence) {
                    .certain => .certain,
                    .uncertain => .uncertain,
                };

                return try self.captureExprTyped(node, confidence);
            },

            // Attribute access - infer attribute type confidence and type hint
            .attribute => |a| {
                // Check if VM fallback will be used - if so, return uncertain
                // This ensures confidence matches what genExpr will actually generate
                // Without this, type analysis might return .certain but genExpr uses runtime.eval()
                if (self.needsVMFallback(node)) {
                    return try self.captureExprTyped(node, .uncertain);
                }

                // Check if accessing a known type's attribute
                const obj_type = self.inferExprScoped(a.value.*) catch .unknown;

                // Helper to convert NativeType to CertainType
                const nativeTypeToCertainType = struct {
                    fn convert(native_type: NativeType) ?builder_mod.CertainType {
                        return switch (native_type) {
                            .int => .int,
                            .float => .float,
                            .bool => .bool_,
                            .string => .string,
                            .bytes => .bytes,
                            .none => .null_,
                            else => null, // Unknown or complex types
                        };
                    }
                }.convert;

                // Track both confidence and type_hint
                const TypeInfo = struct {
                    confidence: builder_mod.TypeConfidence,
                    type_hint: ?builder_mod.CertainType,
                };
                const type_info: TypeInfo = blk: {
                    // String/bytes/list/dict methods are certain
                    if (string_traits.isStringLike(obj_type)) {
                        break :blk .{ .confidence = .certain, .type_hint = .string };
                    }
                    if (container_traits.isList(obj_type) or
                        container_traits.isDict(obj_type) or
                        container_traits.isTuple(obj_type) or
                        container_traits.isSet(obj_type))
                    {
                        break :blk .{ .confidence = .certain, .type_hint = null };
                    }

                    // Module access (math.sqrt, os.path) - check if obj is a known module name
                    if (a.value.* == .name) {
                        const module_name = a.value.name.id;
                        // Known stdlib modules have certain return types
                        const known_modules = std.StaticStringMap(void).initComptime(.{
                            .{ "math", {} }, .{ "os", {} }, .{ "sys", {} }, .{ "re", {} },
                            .{ "json", {} }, .{ "random", {} }, .{ "time", {} }, .{ "datetime", {} },
                            .{ "collections", {} }, .{ "itertools", {} }, .{ "functools", {} },
                            .{ "pathlib", {} }, .{ "io", {} }, .{ "hashlib", {} }, .{ "struct", {} },
                            .{ "socket", {} }, .{ "sqlite3", {} }, .{ "ctypes", {} },
                        });
                        if (known_modules.has(module_name)) {
                            break :blk .{ .confidence = .certain, .type_hint = null };
                        }
                    }

                    // Special handling for anytype params and _converted suffix variables
                    // In comptime polymorphic dispatch, these should use current class field types
                    if (a.value.* == .name) {
                        const base_name = a.value.name.id;

                        // Check for _converted suffix (e.g., other_converted from other = Rat(...))
                        if (std.mem.endsWith(u8, base_name, "_converted")) {
                            const original_name = base_name[0 .. base_name.len - "_converted".len];
                            if (self.anytype_params.contains(original_name)) {
                                // Check current class fields - _converted is same class type
                                if (self.current_class_name) |class_name| {
                                    if (self.type_inferrer.class_fields.get(class_name)) |class_info| {
                                        if (class_info.fields.get(a.attr)) |field_type| {
                                            if (field_type == .pyvalue or field_type == .unknown) {
                                                break :blk .{ .confidence = .uncertain, .type_hint = null };
                                            }
                                            break :blk .{ .confidence = .certain, .type_hint = nativeTypeToCertainType(field_type) };
                                        }
                                    }
                                }
                            }
                        }

                        // Check for anytype param directly (e.g., other.__den in @This() branch)
                        // Code emission checks (in order): var_renames, narrowed_type_params, anytype_params
                        // If redirected/narrowed, uses direct field access. Otherwise uses getAttrDynamic.
                        if (self.anytype_params.contains(base_name)) {
                            // Check if code emission will use direct field access (not getAttrDynamic)
                            // 1. var_renames redirects (e.g., other -> other_converted in int branch)
                            // 2. narrowed_type_params (inside if isRat(other): uses direct access)
                            const uses_direct_access = self.var_renames.contains(base_name) or
                                self.narrowed_type_params.contains(base_name);

                            if (self.current_class_name) |class_name| {
                                if (self.type_inferrer.class_fields.get(class_name)) |class_info| {
                                    if (class_info.fields.get(a.attr)) |field_type| {
                                        if (field_type == .pyvalue or field_type == .unknown) {
                                            break :blk .{ .confidence = .uncertain, .type_hint = null };
                                        }
                                        if (uses_direct_access) {
                                            // Direct field access: use actual field type
                                            break :blk .{ .confidence = .certain, .type_hint = nativeTypeToCertainType(field_type) };
                                        }
                                        // No redirect/narrow: getAttrDynamic returns f64 for numeric types
                                        const hint: ?builder_mod.CertainType = switch (field_type) {
                                            .int, .float => .float, // getAttrDynamic returns f64
                                            .bool => .bool_,
                                            .string => .string,
                                            else => null,
                                        };
                                        break :blk .{ .confidence = .certain, .type_hint = hint };
                                    }
                                }
                            }
                        }
                    }

                    // Class instance attributes - check field type in registry
                    // Only uncertain if field type is actually pyvalue/unknown
                    if (type_traits.isClassInstance(obj_type)) {
                        const class_name = obj_type.class_instance;
                        if (self.type_inferrer.class_fields.get(class_name)) |class_info| {
                            if (class_info.fields.get(a.attr)) |field_type| {
                                // Field has a known type - only uncertain if pyvalue/unknown
                                if (field_type == .pyvalue or field_type == .unknown) {
                                    break :blk .{ .confidence = .uncertain, .type_hint = null };
                                }
                                // Known primitive field type - mark as certain with type hint
                                break :blk .{ .confidence = .certain, .type_hint = nativeTypeToCertainType(field_type) };
                            }
                            // Field not found in known class - uncertain
                            break :blk .{ .confidence = .uncertain, .type_hint = null };
                        }
                        // Class not in registry (local/nested class) - uncertain
                        break :blk .{ .confidence = .uncertain, .type_hint = null };
                    }

                    // Unknown type -> uncertain
                    if (obj_type == .unknown) {
                        break :blk .{ .confidence = .uncertain, .type_hint = null };
                    }

                    // Default to certain for known primitive types
                    break :blk .{ .confidence = .certain, .type_hint = null };
                };

                return try self.captureExprTypedWithHint(node, type_info.confidence, type_info.type_hint);
            },

            // Subscript access - infer element type confidence
            .subscript => |s| {
                // Check container type for element confidence
                const container_type = self.inferExprScoped(s.value.*) catch .unknown;

                const confidence: builder_mod.TypeConfidence = blk: {
                    // List/tuple/string subscript -> certain element type
                    if (container_traits.isList(container_type) or
                        container_traits.isTuple(container_type) or
                        string_traits.isStringLike(container_type))
                    {
                        break :blk .certain;
                    }

                    // Dict subscript -> element type is uncertain unless typed
                    if (container_traits.isDict(container_type)) {
                        // Could enhance this to check dict value type annotation
                        break :blk .uncertain;
                    }

                    // Unknown container -> uncertain
                    if (container_type == .unknown) {
                        break :blk .uncertain;
                    }

                    // Default to certain for known types
                    break :blk .certain;
                };

                return try self.captureExprTyped(node, confidence);
            },

            // List literal - use builder.list with type inference
            .list => |l| {
                // Infer element type from type inferrer
                const list_type = self.inferExprScoped(node) catch .unknown;
                const element_type: []const u8 = switch (list_type) {
                    .list => |elem_ptr| elem_ptr.*.toSimpleZigType(),
                    else => "runtime.PyValue",
                };

                // Check if array optimization is possible (constant homogeneous)
                const use_array = l.elts.len > 0 and isConstantHomogeneous(l.elts);

                // Convert elements
                var elements = try self.allocator.alloc(builder_mod.ZigValue, l.elts.len);
                for (l.elts, 0..) |elem, i| {
                    elements[i] = try self.exprToValue(elem);
                }

                const builder = try self.getBuilder();
                return try builder.list(elements, element_type, use_array);
            },

            // Tuple literal - use builder.tuple_
            .tuple => |t| {
                var elements = try self.allocator.alloc(builder_mod.ZigValue, t.elts.len);
                for (t.elts, 0..) |elem, i| {
                    elements[i] = try self.exprToValue(elem);
                }

                const builder = try self.getBuilder();
                return try builder.tuple_(elements);
            },

            // Dict and set still need captureExpr for complex handling
            .dict, .set => {
                return try self.captureExpr(node);
            },

            // F-strings - use captureExpr for proper builder save/restore
            .fstring => {
                return try self.captureExpr(node);
            },

            // Conditional expression (ternary) - proper ZigValue with type inference
            .if_expr => |ie| {
                // Convert condition, then, and else to ZigValue
                const cond_val = try self.exprToValue(ie.condition.*);
                const then_val = try self.exprToValue(ie.body.*);
                const else_val = try self.exprToValue(ie.orelse_value.*);

                // Allocate persistent storage for pointers
                const cond_ptr = try self.arena.allocator().create(builder_mod.ZigValue);
                const then_ptr = try self.arena.allocator().create(builder_mod.ZigValue);
                const else_ptr = try self.arena.allocator().create(builder_mod.ZigValue);
                cond_ptr.* = cond_val;
                then_ptr.* = then_val;
                else_ptr.* = else_val;

                // Combine confidence from both branches
                const then_conf = then_val.confidence();
                const else_conf = else_val.confidence();
                const result_conf = if (then_conf == .uncertain or else_conf == .uncertain)
                    builder_mod.TypeConfidence.uncertain
                else
                    builder_mod.TypeConfidence.certain;

                return builder_mod.ZigValue{
                    .ternary = .{
                        .condition = cond_ptr,
                        .then_value = then_ptr,
                        .else_value = else_ptr,
                        .confidence = result_conf,
                    },
                };
            },

            // Comprehensions - use captureExpr for proper builder save/restore
            .listcomp, .dictcomp, .genexp => {
                return try self.captureExpr(node);
            },

            // Lambda - use captureExpr for proper builder save/restore
            .lambda => {
                return try self.captureExpr(node);
            },

            // Starred expression
            .starred => |s| {
                // Recurse into the starred value
                return self.exprToValue(s.value.*);
            },

            // Named expression (walrus operator) - type is the assigned value's type
            .named_expr => |n| {
                return self.exprToValue(n.value.*);
            },

            // Await expression - use captureExpr for proper builder save/restore
            .await_expr => {
                return try self.captureExpr(node);
            },

            // Ellipsis literal
            .ellipsis_literal => {
                return builder_mod.ZigValue.raw("runtime.Ellipsis");
            },

            else => {
                // For remaining nodes: use captureExpr for proper builder save/restore
                return try self.captureExpr(node);
            },
        }
    }

    // ============================================================
    // Centralized Emit Helpers (Phase 1 Consolidation)
    // All codegen modules should use self.emit() and self.emitFmt()
    // instead of defining local emitConst/emitFmtConst functions.
    // ============================================================

    /// Write to output, flushing any pending builder content first.
    /// This ensures proper ordering: builder content -> emit content.
    pub fn emit(self: *NativeCodegen, val: []const u8) CodegenError!void {
        // Flush any pending builder content first to maintain order
        try self.flushBuilder();
        // Then write directly to output
        try self.output.appendSlice(self.allocator, val);
    }

    /// Write formatted to output, flushing builder first.
    pub fn emitFmt(self: *NativeCodegen, comptime fmt: []const u8, args: anytype) CodegenError!void {
        // Flush any pending builder content first
        try self.flushBuilder();
        // Then write formatted directly to output
        var buf: [8192]u8 = undefined;
        const formatted = std.fmt.bufPrint(&buf, fmt, args) catch return error.FormattingError;
        try self.output.appendSlice(self.allocator, formatted);
    }

    /// Emit a Zig type string for a NativeType.
    /// Used for type casts like @as(?i64, ...) in ternary expressions.
    pub fn emitZigTypeFor(self: *NativeCodegen, native_type: NativeType) CodegenError!void {
        const zig_type = switch (native_type) {
            .int => |kind| switch (kind) {
                .bounded => "i64",
                .unbounded => "runtime.BigInt",
            },
            .bigint => "runtime.BigInt",
            .unified_int => "runtime.UnifiedInt",
            .usize => "usize",
            .float => "f64",
            .bool => "bool",
            .string => "[]const u8",
            .bytes => "runtime.builtins.PyBytes",
            .complex => "runtime.PyComplex",
            .none => "void",
            .pyvalue => "runtime.PyValue",
            .class_instance => |name| name,
            else => "runtime.PyValue", // Fallback for complex types
        };
        try self.emit(zig_type);
    }

    /// Flush builder output to the main output buffer.
    /// Use this after calling builder methods that don't auto-flush (like emitAssertEqualStmt).
    /// This is the bridge between ZigBuilder and the main output buffer.
    pub fn flushBuilder(self: *NativeCodegen) CodegenError!void {
        if (self.builder) |b| {
            const output = try b.getBodyDupe();
            if (output.len > 0) {
                try self.output.appendSlice(self.allocator, output);
            }
        }
    }

    /// Emit a variable name with proper escaping for Zig keywords and shadowing.
    /// Use this for variable declarations and references.
    /// NOTE: This writes through the builder to maintain correct output order.
    pub fn emitVarName(self: *NativeCodegen, name: []const u8) CodegenError!void {
        // Write to temp buffer first to go through builder (maintains output order)
        var buf: [512]u8 = undefined;
        var fbs = std.io.fixedBufferStream(&buf);
        zig_keywords.writeLocalVarName(fbs.writer(), name) catch |err| switch (err) {
            error.NoSpaceLeft => {
                // Name too long for fixed buffer, fall back to dynamic allocation
                var list: std.ArrayList(u8) = .{};
                defer list.deinit(self.allocator);
                try zig_keywords.writeLocalVarName(list.writer(self.allocator), name);
                try self.emit(list.items);
                return;
            },
            else => |e| return e,
        };
        try self.emit(fbs.getWritten());
    }

    /// Emit an identifier with proper escaping for Zig keywords (no underscore suffix).
    /// Use this for field names, method names, and type names only.
    /// NOTE: This writes through the builder to maintain correct output order.
    pub fn emitIdent(self: *NativeCodegen, name: []const u8) CodegenError!void {
        // Write to temp buffer first to go through builder (maintains output order)
        var buf: [512]u8 = undefined;
        var fbs = std.io.fixedBufferStream(&buf);
        zig_keywords.writeEscapedIdent(fbs.writer(), name) catch |err| switch (err) {
            error.NoSpaceLeft => {
                // Name too long for fixed buffer, fall back to dynamic allocation
                var list: std.ArrayList(u8) = .{};
                defer list.deinit(self.allocator);
                try zig_keywords.writeEscapedIdent(list.writer(self.allocator), name);
                try self.emit(list.items);
                return;
            },
            else => |e| return e,
        };
        try self.emit(fbs.getWritten());
    }

    /// Emit a struct member name (method or field) with proper renaming/escaping.
    /// Use this for pub fn/pub const declarations inside structs.
    /// Unlike emitIdent which just escapes with @"", this RENAMES "std" to "std_"
    /// to avoid shadowing the module-level std import.
    /// NOTE: This writes through the builder to maintain correct output order.
    pub fn emitStructMemberName(self: *NativeCodegen, name: []const u8) CodegenError!void {
        // Write to temp buffer first to go through builder (maintains output order)
        var buf: [512]u8 = undefined;
        var fbs = std.io.fixedBufferStream(&buf);
        zig_keywords.writeStructMethodName(fbs.writer(), name) catch |err| switch (err) {
            error.NoSpaceLeft => {
                // Name too long for fixed buffer, fall back to dynamic allocation
                var list: std.ArrayList(u8) = .{};
                defer list.deinit(self.allocator);
                try zig_keywords.writeStructMethodName(list.writer(self.allocator), name);
                try self.emit(list.items);
                return;
            },
            else => |e| return e,
        };
        try self.emit(fbs.getWritten());
    }

    /// Check if a name conflicts with the module wrapper struct name.
    /// In module mode, we wrap everything in `pub const <module_name> = struct { ... };`
    /// If a variable inside has the same name as the module, it creates ambiguous reference.
    /// Returns true if the name matches the module name (conflict exists).
    pub fn isModuleNameConflict(self: *NativeCodegen, name: []const u8) bool {
        if (self.mode != .module) return false;
        if (self.module_name) |mod_name| {
            return std.mem.eql(u8, name, mod_name);
        }
        return false;
    }

    /// Get the disambiguated name for a module-level declaration.
    /// If the name conflicts with the module wrapper struct name, prefix with underscore.
    /// E.g., in version.py: `version = "2.3.4"` becomes `_version = "2.3.4"`
    pub fn getModuleLevelName(self: *NativeCodegen, name: []const u8) []const u8 {
        if (self.isModuleNameConflict(name)) {
            // Return prefixed name - allocate in arena so it persists
            const prefixed = std.fmt.allocPrint(self.arena.allocator(), "_{s}", .{name}) catch name;
            return prefixed;
        }
        return name;
    }

    /// Check if a local variable name would shadow a module-level import.
    /// This includes `from X import Y` and `import X as Y` at module level.
    /// When inside a function, we need to detect if a local variable shadows these.
    pub fn shadowsModuleLevelImport(self: *NativeCodegen, name: []const u8) bool {
        // Only applies when we're inside a function
        if (self.current_function_name == null) return false;
        // Check if name matches a module-level from-import symbol
        if (self.module_level_from_imports.contains(name)) return true;
        // Check if name matches an imported module name
        if (self.imported_modules.contains(name)) return true;
        // Check if name matches an import alias
        if (self.import_aliases.contains(name)) return true;
        return false;
    }

    /// Get a disambiguated local variable name that doesn't shadow module-level imports.
    /// If the name shadows a module-level import, prefix with underscore.
    pub fn getLocalVarName(self: *NativeCodegen, name: []const u8) []const u8 {
        if (self.shadowsModuleLevelImport(name)) {
            // Return prefixed name - allocate in arena so it persists
            const prefixed = std.fmt.allocPrint(self.arena.allocator(), "_{s}", .{name}) catch name;
            return prefixed;
        }
        return name;
    }

    /// Emit a dotted identifier with proper escaping (e.g., "test.support" -> "@\"test\".@\"support\"").
    /// Use this for module names with dots.
    /// NOTE: This writes through the builder to maintain correct output order.
    pub fn emitDottedIdent(self: *NativeCodegen, name: []const u8) CodegenError!void {
        // Write to temp buffer first to go through builder (maintains output order)
        var buf: [512]u8 = undefined;
        var fbs = std.io.fixedBufferStream(&buf);
        zig_keywords.writeEscapedDottedIdent(fbs.writer(), name) catch |err| switch (err) {
            error.NoSpaceLeft => {
                // Name too long for fixed buffer, fall back to dynamic allocation
                var list: std.ArrayList(u8) = .{};
                defer list.deinit(self.allocator);
                try zig_keywords.writeEscapedDottedIdent(list.writer(self.allocator), name);
                try self.emit(list.items);
                return;
            },
            else => |e| return e,
        };
        try self.emit(fbs.getWritten());
    }

    /// Emit an import path with proper escaping for Zig keywords.
    /// NOTE: This writes through the builder to maintain correct output order.
    pub fn emitImportPath(self: *NativeCodegen, path: []const u8) CodegenError!void {
        // Write to temp buffer first to go through builder (maintains output order)
        var buf: [512]u8 = undefined;
        var fbs = std.io.fixedBufferStream(&buf);
        zig_keywords.writeEscapedImportPath(fbs.writer(), path) catch |err| switch (err) {
            error.NoSpaceLeft => {
                // Path too long for fixed buffer, fall back to dynamic allocation
                var list: std.ArrayList(u8) = .{};
                defer list.deinit(self.allocator);
                try zig_keywords.writeEscapedImportPath(list.writer(self.allocator), path);
                try self.emit(list.items);
                return;
            },
            else => |e| return e,
        };
        try self.emit(fbs.getWritten());
    }

    /// Emit a parameter discard statement: `_ = &param_name;`
    /// This method tracks which parameters have been discarded in the current function scope.
    /// If the parameter has already been discarded, this is a no-op (prevents duplicates).
    /// Must call clearDiscardedParams() when entering a new function scope.
    ///
    /// The parameter name in the discard must match the signature:
    /// - If param was renamed via var_renames (e.g., __m40_p_types): use that name
    /// - If param shadows class method, module-level, or local scope: {name}__shadow
    /// - Otherwise: use writeLocalVarName (handles Zig keyword escaping)
    pub fn emitParamDiscard(self: *NativeCodegen, param_name: []const u8) CodegenError!void {
        // Check if already discarded in current function scope
        if (self.discarded_params.contains(param_name)) {
            return; // Already discarded, skip duplicate
        }
        // Mark as discarded
        try self.discarded_params.put(param_name, {});

        // First, check if the parameter was renamed via var_renames
        // (e.g., types -> __m40_p_types). If so, use the renamed name directly.
        // Special case: if renamed to "_", the param was made anonymous - skip discard entirely
        if (self.var_renames.get(param_name)) |renamed| {
            if (std.mem.eql(u8, renamed, "_")) {
                // Anonymous parameter - no discard needed
                return;
            }
            try self.emitIndent();
            try self.emit("_ = &");
            try self.emit(renamed);
            try self.emit(";\n");
            return;
        }

        // Check if param was renamed to {name}__shadow in the signature
        // This mirrors the logic in signature.zig:genMethodParam
        const shadows_class_method = if (self.current_class_body) |cb| blk: {
            for (cb) |stmt| {
                if (stmt == .function_def) {
                    const method_name = stmt.function_def.name;
                    // Skip special methods that we're checking params FOR
                    if (std.mem.eql(u8, method_name, "__init__") or std.mem.eql(u8, method_name, "__new__")) {
                        continue;
                    }
                    if (std.mem.eql(u8, param_name, method_name)) {
                        break :blk true;
                    }
                }
            }
            break :blk false;
        } else false;

        const shadows_module_level = self.wouldParamShadow(param_name);
        const shadows_local_scope = self.isDeclaredInAnyScope(param_name);

        // Emit the discard statement
        try self.emitIndent();
        try self.emit("_ = &");

        if (shadows_class_method or shadows_module_level or shadows_local_scope) {
            // Use the __shadow suffix to match signature
            try self.emitFmt("{s}__shadow", .{param_name});
        } else {
            // Use emitVarName for Zig keyword escaping (writes through builder)
            try self.emitVarName(param_name);
        }
        try self.emit(";\n");
    }

    /// Clear the discarded_params set when entering a new function scope.
    /// This ensures discard tracking is isolated per function.
    pub fn clearDiscardedParams(self: *NativeCodegen) void {
        self.discarded_params.clearRetainingCapacity();
    }

    /// Emit inline block with callback pattern - automatically handles labels, braces, and semicolons
    ///
    /// Usage:
    ///   try self.withInlineBlock("hint", args, struct {
    ///       fn emit(c: *NativeCodegen, label: []const u8, a: []ast.Node) !void {
    ///           try c.genExpr(a[0]);
    ///           try c.emitBreak(label, "result");
    ///       }
    ///   }.emit);
    ///
    /// Output: (__m{id}_hint: { <generated_code> break :__m{id}_hint result; })
    ///
    /// Features:
    /// - Automatically adds semicolon only when needed (no double ;;)
    /// - Can't forget to close the block
    /// - Label is managed for you
    pub fn withInlineBlock(self: *NativeCodegen, hint: []const u8, context: anytype, body_fn: anytype) CodegenError!void {
        const id = self.nextNameId();
        const label = try std.fmt.allocPrint(self.arena.allocator(), "__m{d}_{s}", .{ id, hint });

        try emitFmtConst(self, "({s}: {{ ", .{label});
        const start_pos = self.output.items.len;

        // Call body with context
        try body_fn(self, label, context);

        const end_pos = self.output.items.len;
        const had_content = end_pos > start_pos;

        // Add semicolon only if body emitted content and doesn't already end with one
        // Check by trimming trailing whitespace first to handle "break :label value; " pattern
        if (had_content) {
            // Find last non-whitespace character
            var last_non_ws_pos = end_pos;
            while (last_non_ws_pos > start_pos) {
                const ch = self.output.items[last_non_ws_pos - 1];
                if (ch != ' ' and ch != '\t' and ch != '\n' and ch != '\r') {
                    break;
                }
                last_non_ws_pos -= 1;
            }

            // Check if last non-whitespace character is a semicolon
            const needs_semicolon = if (last_non_ws_pos > start_pos)
                self.output.items[last_non_ws_pos - 1] != ';'
            else
                true;

            if (needs_semicolon) {
                try emitConst(self, "; ");
            }
        }

        try emitConst(self, "})");
    }

    /// Helper to emit break statement inside inline block
    pub fn emitBreak(self: *NativeCodegen, label: []const u8, value: []const u8) CodegenError!void {
        try emitFmtConst(self, "break :{s} {s}", .{ label, value });
    }

    /// DEPRECATED: Use emitInlineBlock with callback instead
    /// These are kept for backward compatibility during migration
    pub fn emitInlineBlockStart(self: *NativeCodegen, hint: []const u8) CodegenError![]const u8 {
        const id = self.nextNameId();
        const label = try std.fmt.allocPrint(self.arena.allocator(), "__m{d}_{s}", .{ id, hint });
        try emitFmtConst(self, "({s}: {{ ", .{label});
        return label;
    }

    /// DEPRECATED: Use emitInlineBlock with callback instead
    pub fn emitInlineBlockEnd(self: *NativeCodegen) CodegenError!void {
        try emitConst(self, "})");
    }

    // ============================================================================
    // AUTO-CLOSE HELPERS
    // ============================================================================
    // These helpers guarantee bracket matching by using callbacks.
    // The opening bracket is emitted, callback is executed, closing bracket is emitted.
    // It's impossible to forget or mismatch brackets.
    //
    // Usage pattern:
    //   try self.withParens(struct {
    //       pub fn f(c: *NativeCodegen) !void {
    //           try c.genExpr(expr);
    //       }
    //   }.f);
    //
    // Or with context capture:
    //   try self.withParensCtx(expr, struct {
    //       pub fn f(c: *NativeCodegen, e: ast.Node) !void {
    //           try c.genExpr(e);
    //       }
    //   }.f);
    // ============================================================================

    /// Auto-close parentheses: ( ... )
    pub fn withParens(self: *NativeCodegen, body_fn: anytype) CodegenError!void {
        try emitConst(self, "(");
        try body_fn(self);
        try emitConst(self, ")");
    }

    /// Auto-close parentheses with context: ( ... )
    pub fn withParensCtx(self: *NativeCodegen, ctx: anytype, body_fn: anytype) CodegenError!void {
        try emitConst(self, "(");
        try body_fn(self, ctx);
        try emitConst(self, ")");
    }

    /// Auto-close braces: { ... }
    pub fn withBraces(self: *NativeCodegen, body_fn: anytype) CodegenError!void {
        try emitConst(self, "{ ");
        try body_fn(self);
        try emitConst(self, " }");
    }

    /// Auto-close braces with context: { ... }
    pub fn withBracesCtx(self: *NativeCodegen, ctx: anytype, body_fn: anytype) CodegenError!void {
        try emitConst(self, "{ ");
        try body_fn(self, ctx);
        try emitConst(self, " }");
    }

    /// Auto-close brackets: [ ... ]
    pub fn withBrackets(self: *NativeCodegen, body_fn: anytype) CodegenError!void {
        try emitConst(self, "[");
        try body_fn(self);
        try emitConst(self, "]");
    }

    /// Auto-close brackets with context: [ ... ]
    pub fn withBracketsCtx(self: *NativeCodegen, ctx: anytype, body_fn: anytype) CodegenError!void {
        try emitConst(self, "[");
        try body_fn(self, ctx);
        try emitConst(self, "]");
    }

    /// Emit expression wrapped in parentheses: (expr)
    /// Convenience helper for the common case of wrapping a single expression
    pub fn emitParens(self: *NativeCodegen, expr: ast.Node) CodegenError!void {
        try emitConst(self, "(");
        try self.genExpr(expr);
        try emitConst(self, ")");
    }

    /// Emit binary operation: (left op right)
    /// Auto-wraps in parentheses to ensure correct precedence
    pub fn emitBinOp(self: *NativeCodegen, left: ast.Node, op: []const u8, right: ast.Node) CodegenError!void {
        try emitConst(self, "(");
        try self.genExpr(left);
        try emitConst(self, op);
        try self.genExpr(right);
        try emitConst(self, ")");
    }

    /// Emit function/method call: name(args_body)
    /// The body_fn should emit the arguments
    pub fn emitCall(self: *NativeCodegen, name: []const u8, body_fn: anytype) CodegenError!void {
        try emitConst(self, name);
        try emitConst(self, "(");
        try body_fn(self);
        try emitConst(self, ")");
    }

    /// Emit function/method call with context: name(args_body)
    pub fn emitCallCtx(self: *NativeCodegen, name: []const u8, ctx: anytype, body_fn: anytype) CodegenError!void {
        try emitConst(self, name);
        try emitConst(self, "(");
        try body_fn(self, ctx);
        try emitConst(self, ")");
    }

    /// Emit struct literal: .{ ... }
    pub fn withStructLit(self: *NativeCodegen, body_fn: anytype) CodegenError!void {
        try emitConst(self, ".{ ");
        try body_fn(self);
        try emitConst(self, " }");
    }

    /// Emit struct literal with context: .{ ... }
    pub fn withStructLitCtx(self: *NativeCodegen, ctx: anytype, body_fn: anytype) CodegenError!void {
        try emitConst(self, ".{ ");
        try body_fn(self, ctx);
        try emitConst(self, " }");
    }

    /// Emit if expression: if (cond) then_expr else else_expr
    pub fn emitIfExpr(self: *NativeCodegen, cond: ast.Node, then_expr: ast.Node, else_expr: ast.Node) CodegenError!void {
        try emitConst(self, "if (");
        try self.genExpr(cond);
        try emitConst(self, ") ");
        try self.genExpr(then_expr);
        try emitConst(self, " else ");
        try self.genExpr(else_expr);
    }

    /// Emit try expression: try expr
    pub fn emitTry(self: *NativeCodegen, expr: ast.Node) CodegenError!void {
        try emitConst(self, "try ");
        try self.genExpr(expr);
    }

    /// Emit orelse expression: expr orelse default
    pub fn emitOrelse(self: *NativeCodegen, expr: ast.Node, default: []const u8) CodegenError!void {
        try self.genExpr(expr);
        try emitConst(self, " orelse ");
        try emitConst(self, default);
    }

    /// Emit catch expression: expr catch default
    pub fn emitCatch(self: *NativeCodegen, expr: ast.Node, default: []const u8) CodegenError!void {
        try self.genExpr(expr);
        try emitConst(self, " catch ");
        try emitConst(self, default);
    }

    /// Emit slice expression: value[start..end]
    pub fn emitSlice(self: *NativeCodegen, value: ast.Node, start: ?ast.Node, end: ?ast.Node) CodegenError!void {
        try self.genExpr(value);
        try emitConst(self, "[");
        if (start) |s| try self.genExpr(s);
        try emitConst(self, "..");
        if (end) |e| try self.genExpr(e);
        try emitConst(self, "]");
    }

    /// Emit subscript expression: value[index]
    pub fn emitSubscript(self: *NativeCodegen, value: ast.Node, index: ast.Node) CodegenError!void {
        try self.genExpr(value);
        try emitConst(self, "[");
        try self.genExpr(index);
        try emitConst(self, "]");
    }

    /// Emit field access: value.field
    pub fn emitField(self: *NativeCodegen, value: ast.Node, field: []const u8) CodegenError!void {
        try self.genExpr(value);
        try emitConst(self, ".");
        try emitConst(self, field);
    }

    /// Emit comma-separated list of expressions
    pub fn emitExprList(self: *NativeCodegen, exprs: []const ast.Node) CodegenError!void {
        for (exprs, 0..) |expr, i| {
            if (i > 0) try emitConst(self, ", ");
            try self.genExpr(expr);
        }
    }

    /// Capture an AST expression as a raw ZigValue
    /// This is the bridge between existing emit-based codegen and the new builder API
    /// Usage: const val = try self.captureExpr(expr);
    /// The returned ZigValue.raw() contains the emitted Zig code for the expression
    /// IMPORTANT: Saves and restores builder state to prevent nested genExpr
    /// calls from flushing accumulated builder content from parent scopes.
    pub fn captureExpr(self: *NativeCodegen, expr: ast.Node) CodegenError!builder_mod.ZigValue {
        const expressions = @import("../expressions.zig");

        // Save builder state - nested code may use builder and flush
        // Copy to arena to avoid aliasing issues when restoring
        const builder_save: ?[]const u8 = if (self.builder) |b| blk: {
            const content = try b.getBodyDupe();
            if (content.len > 0) {
                break :blk try self.arena.allocator().dupe(u8, content);
            }
            break :blk null;
        } else null;

        // Save current output position
        const start_pos = self.output.items.len;

        // Generate the expression into the output buffer
        try expressions.genExpr(self, expr);

        // Flush builder to ensure any pending output (from modules using builder)
        // gets written to self.output before we capture the result
        try self.flushBuilder();

        // Extract the generated code
        const generated = self.output.items[start_pos..];

        // Copy to arena so it persists (output may be modified later)
        const code = try self.arena.allocator().dupe(u8, generated);

        // Remove the generated code from output (we're capturing it, not emitting it)
        self.output.shrinkRetainingCapacity(start_pos);

        // Restore builder state
        if (builder_save) |saved| {
            if (self.builder) |b| {
                try b.emitRaw(saved);
            }
        }

        return builder_mod.ZigValue.raw(code);
    }

    /// Capture an expression with type confidence tracking
    /// Like captureExpr but returns typed_raw with confidence info
    pub fn captureExprTyped(self: *NativeCodegen, expr: ast.Node, typed_confidence: builder_mod.TypeConfidence) CodegenError!builder_mod.ZigValue {
        const expressions = @import("../expressions.zig");

        // Save builder state - nested code may use builder and flush
        const builder_save: ?[]const u8 = if (self.builder) |b| blk: {
            const content = try b.getBodyDupe();
            if (content.len > 0) {
                break :blk try self.arena.allocator().dupe(u8, content);
            }
            break :blk null;
        } else null;

        // Save current output position
        const start_pos = self.output.items.len;

        // Generate the expression into the output buffer
        try expressions.genExpr(self, expr);

        // Flush builder to ensure any pending output gets written
        try self.flushBuilder();

        // Extract the generated code
        const generated = self.output.items[start_pos..];

        // Copy to arena so it persists
        const code = try self.arena.allocator().dupe(u8, generated);

        // Remove the generated code from output (we're capturing it)
        self.output.shrinkRetainingCapacity(start_pos);

        // Restore builder state
        if (builder_save) |saved| {
            if (self.builder) |b| {
                try b.emitRaw(saved);
            }
        }

        return builder_mod.ZigValue{ .typed_raw = .{
            .raw = code,
            .confidence = typed_confidence,
        } };
    }

    /// Capture an expression with type confidence and type hint tracking
    /// Like captureExprTyped but also stores the CertainType for better dispatch
    pub fn captureExprTypedWithHint(self: *NativeCodegen, expr: ast.Node, typed_confidence: builder_mod.TypeConfidence, type_hint: ?builder_mod.CertainType) CodegenError!builder_mod.ZigValue {
        const expressions = @import("../expressions.zig");

        // Save builder state - nested code may use builder and flush
        const builder_save: ?[]const u8 = if (self.builder) |b| blk: {
            const content = try b.getBodyDupe();
            if (content.len > 0) {
                break :blk try self.arena.allocator().dupe(u8, content);
            }
            break :blk null;
        } else null;

        // Save current output position
        const start_pos = self.output.items.len;

        // Generate the expression into the output buffer
        try expressions.genExpr(self, expr);

        // Flush builder to ensure any pending output gets written
        try self.flushBuilder();

        // Extract the generated code
        const generated = self.output.items[start_pos..];

        // Copy to arena so it persists
        const code = try self.arena.allocator().dupe(u8, generated);

        // Remove the generated code from output (we're capturing it)
        self.output.shrinkRetainingCapacity(start_pos);

        // Restore builder state
        if (builder_save) |saved| {
            if (self.builder) |b| {
                try b.emitRaw(saved);
            }
        }

        return builder_mod.ZigValue{ .typed_raw = .{
            .raw = code,
            .confidence = typed_confidence,
            .type_hint = type_hint,
        } };
    }

    /// Capture a statement's generated code (for builder integration)
    /// Similar to captureExpr but for statements
    /// IMPORTANT: Saves and restores builder state to prevent nested generateStmt
    /// calls from flushing accumulated builder content from parent scopes.
    pub fn captureStmt(self: *NativeCodegen, stmt: ast.Node) CodegenError![]const u8 {
        // Save builder state - nested code may use builder and flush
        // Copy to arena to avoid aliasing issues when restoring
        const builder_save: ?[]const u8 = if (self.builder) |b| blk: {
            const content = try b.getBodyDupe();
            if (content.len > 0) {
                break :blk try self.arena.allocator().dupe(u8, content);
            }
            break :blk null;
        } else null;

        const start_pos = self.output.items.len;
        try self.generateStmt(stmt);

        // Defensive check: nested captureStmt() may have shrunk the buffer
        // If start_pos > current length, the code went to builder instead
        const current_len = self.output.items.len;
        const generated = if (start_pos <= current_len)
            self.output.items[start_pos..]
        else
            &[_]u8{}; // Empty slice - code is in builder buffer

        const code = try self.arena.allocator().dupe(u8, generated);

        // Only shrink if we have content in output buffer
        if (start_pos <= self.output.items.len) {
            self.output.shrinkRetainingCapacity(start_pos);
        }

        // Restore builder state
        if (builder_save) |saved| {
            if (self.builder) |b| {
                try b.emitRaw(saved);
            }
        }

        return code;
    }

    /// Capture scope discards (for builder integration)
    pub fn captureScopedDiscards(self: *NativeCodegen) CodegenError![]const u8 {
        const start_pos = self.output.items.len;
        try self.emitScopedDiscards();
        const generated = self.output.items[start_pos..];
        const code = try self.arena.allocator().dupe(u8, generated);
        self.output.shrinkRetainingCapacity(start_pos);
        return code;
    }

    /// Emit a ZigValue to the builder.
    /// NOTE: Does NOT flush - caller must call flushBuilder() when done.
    /// This allows builder content to accumulate for operations that mix
    /// emitRaw() and emitZigValue() calls.
    pub fn emitZigValue(self: *NativeCodegen, value: builder_mod.ZigValue) CodegenError!void {
        const b = try self.getBuilder();
        try b.emitValue(value, builder_mod.EmitConfig.forExpression());
    }

    /// Static indent strings for O(1) lookup instead of O(n) loop
    /// Supports up to 20 levels of nesting (80 spaces)
    const INDENT_STRINGS = [_][]const u8{
        "",
        "    ",
        "        ",
        "            ",
        "                ",
        "                    ",
        "                        ",
        "                            ",
        "                                ",
        "                                    ",
        "                                        ",
        "                                            ",
        "                                                ",
        "                                                    ",
        "                                                        ",
        "                                                            ",
        "                                                                ",
        "                                                                    ",
        "                                                                        ",
        "                                                                            ",
    };

    pub fn emitIndent(self: *NativeCodegen) CodegenError!void {
        const level = @min(self.indent_level, INDENT_STRINGS.len - 1);
        try emitConst(self, INDENT_STRINGS[level]);
    }

    pub fn indent(self: *NativeCodegen) void {
        self.indent_level += 1;
    }

    pub fn dedent(self: *NativeCodegen) void {
        self.indent_level -= 1;
    }

    /// Get next unique block label ID and increment the counter
    /// This is the core API - returns the numeric ID for use in formatted emit calls
    /// Usage pattern (existing code uses this):
    ///   const id = self.nextLabelId();
    ///   try self.emitFmt("blk_{d}: {{\n", .{id});
    ///   // ... block body ...
    ///   try self.emitFmt("break :blk_{d} result;\n", .{id});
    ///   try emitConst(self, "}");
    pub fn nextLabelId(self: *NativeCodegen) usize {
        const id = self.block_label_counter;
        self.block_label_counter += 1;
        return id;
    }

    /// Emit a labeled block start with unique ID
    /// Returns the label ID for use in break statements
    /// Usage: const id = try self.emitLabeledBlock("blk"); ... try self.emitBreakLabel("blk", id);
    pub fn emitLabeledBlock(self: *NativeCodegen, prefix: []const u8) CodegenError!usize {
        const id = self.nextLabelId();
        try emitFmtConst(self, "{s}_{d}: {{\n", .{ prefix, id });
        return id;
    }

    /// Emit a break statement for a labeled block
    pub fn emitBreakLabel(self: *NativeCodegen, prefix: []const u8, id: usize) CodegenError!void {
        try emitFmtConst(self, "break :{s}_{d}", .{ prefix, id });
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
    /// then scoped vars (for loop-local variables), then falls back to global type inference.
    pub fn getVarType(self: *NativeCodegen, var_name: []const u8) ?NativeType {
        // Check local scope first (function/method local variables)
        if (self.local_var_types.get(var_name)) |local_type| {
            return local_type;
        }
        // Check scoped vars (loop-local variables like for-loop targets and body vars)
        if (self.type_inferrer.getScopedVar(var_name)) |scoped_type| {
            return scoped_type;
        }
        // Fall back to global type inference
        return self.type_inferrer.var_types.get(var_name);
    }

    /// Get the inferred type of a parameter within a specific function scope
    /// This avoids pollution from variables with the same name in other scopes
    pub fn getVarTypeInScope(self: *NativeCodegen, scope_name: []const u8, var_name: []const u8) ?NativeType {
        // Create scoped key: "scope_name:var_name"
        const scoped_key = std.fmt.allocPrint(self.allocator, "{s}:{s}", .{ scope_name, var_name }) catch return null;
        defer self.allocator.free(scoped_key);
        return self.type_inferrer.scoped_var_types.get(scoped_key);
    }

    /// Register a local variable type (for current function/method scope)
    pub fn setLocalVarType(self: *NativeCodegen, var_name: []const u8, var_type: NativeType) !void {
        try self.local_var_types.put(var_name, var_type);
    }

    /// Clear local variable types (call when entering a new function/method)
    pub fn clearLocalVarTypes(self: *NativeCodegen) void {
        self.local_var_types.clearRetainingCapacity();
        // NOTE: We no longer clear var_renames here.
        // Parameter renames are set up in generators.zig BEFORE signature generation
        // and must persist through to body generation. The clear happens at the start
        // of each function in generators.zig, not here.
    }

    /// Check if a variable is mutated (reassigned after first assignment)
    /// Uses BOTH IR-based pass analysis AND function-local mutations (conservative OR)
    pub fn isVarMutated(self: *NativeCodegen, var_name: []const u8) bool {
        // Check pass analysis result first - if it says mutated, return true immediately
        if (self.pass_analysis_result) |result| {
            if (!result.shouldBeConst(var_name)) {
                return true;
            }
        }

        // Also check function-local mutations (fallback/supplement)
        // This catches cases the IR analysis might miss

        // When inside a non-function scope (loop body), check scope-specific mutations first
        // Variables declared inside loops are fresh each iteration, so they're not mutated
        // unless there's a mutation (aug_assign or multiple assignments) in the SAME scope
        if (self.current_scope_id != 0) {
            // Check for scope-specific mutation: "varname:scope_id"
            var scoped_key_buf: [256]u8 = undefined;
            const scoped_key = std.fmt.bufPrint(&scoped_key_buf, "{s}:{d}", .{ var_name, self.current_scope_id }) catch var_name;
            if (self.func_local_mutations.contains(scoped_key)) {
                return true;
            }
            // Also check if variable has aug_assign (stored without scope suffix)
            // because aug_assign always means mutation regardless of where we declare
            if (self.func_local_mutations.contains(var_name)) {
                // But only if the mutation is from aug_assign, not from multi-assign at different scope
                // Check if there's a scoped entry at function scope (scope 0)
                var func_scope_key_buf: [256]u8 = undefined;
                const func_scope_key = std.fmt.bufPrint(&func_scope_key_buf, "{s}:0", .{var_name}) catch var_name;
                if (self.func_local_mutations.contains(func_scope_key)) {
                    // Multi-assign at function scope - doesn't affect loop-scope vars
                    return false;
                }
                // Must be aug_assign - applies to all scopes
                return true;
            }
            return false;
        }

        // At function scope (current_scope_id == 0), check both bare name and scoped key
        // Bare name: aug_assign variables are stored with just var_name
        // Scoped key: multi-assign variables are stored as "var_name:0"
        if (self.func_local_mutations.contains(var_name)) {
            return true;
        }
        // Also check scoped key for function-level multi-assigns
        var scoped_key_buf: [256]u8 = undefined;
        const scoped_key = std.fmt.bufPrint(&scoped_key_buf, "{s}:0", .{var_name}) catch var_name;
        if (self.func_local_mutations.contains(scoped_key)) {
            return true;
        }
        // If we're inside a function/method (func_local_uses has been populated),
        // don't trust module-level semantic info for mutation detection.
        // Module-level analysis doesn't distinguish between same-named variables
        // in different scopes (e.g., class A's `int_class` vs class B's `int_class`).
        if (self.func_local_uses.count() > 0) {
            // We're in a function context - only trust func_local_mutations
            return false;
        }
        // Fall back to module-level semantic info (for module-level variables)
        return self.semantic_info.isMutated(var_name);
    }

    /// Check if a variable has aug_assign (x += 1, etc.)
    /// This indicates the variable itself is modified, not just type-changed
    pub fn isVarAugAssigned(self: *NativeCodegen, var_name: []const u8) bool {
        return self.func_local_aug_assigns.contains(var_name);
    }

    /// Check if a variable is unused (assigned but never read)
    /// For function-local variables, check func_local_uses first (if populated)
    /// This prevents false "unused" detection for variables used within function bodies
    pub fn isVarUnused(self: *NativeCodegen, var_name: []const u8) bool {
        // If we're inside a function/method (func_local_uses is populated),
        // use that to determine if the variable is used
        if (self.func_local_uses.count() > 0) {
            // Variable is unused if it's NOT in the local uses map
            return !self.func_local_uses.contains(var_name);
        }
        // At module level, use semantic info
        return self.semantic_info.isUnused(var_name);
    }

    /// Emit discards for variables declared in current scope only
    /// Used when exiting loops/blocks where variables go out of scope before function ends
    /// Unlike emitPendingDiscards, this only processes variables in the current scope
    pub fn emitScopedDiscards(self: *NativeCodegen) CodegenError!void {
        const output_str = self.output.items;
        const search_start = self.function_start_pos;

        // Collect keys to remove (can't modify during iteration)
        var to_remove: std.ArrayList([]const u8) = .empty;
        defer to_remove.deinit(self.allocator);

        var it = self.pending_discards.iterator();
        while (it.next()) |entry| {
            const var_name = entry.key_ptr.*;
            const emit_name = entry.value_ptr.*;

            // Only process variables declared in current scope
            if (!self.symbol_table.isDeclaredInCurrentScope(var_name)) continue;

            // Count occurrences of the variable name as a complete identifier
            // Skip occurrences inside string literals (e.g., VM fallback strings like "lhs.split()")
            var occurrence_count: usize = 0;
            var pos: usize = search_start;
            while (std.mem.indexOfPos(u8, output_str, pos, emit_name)) |idx| {
                const end = idx + emit_name.len;
                const valid_start = idx == 0 or (!std.ascii.isAlphanumeric(output_str[idx - 1]) and output_str[idx - 1] != '_');
                const valid_end = end >= output_str.len or (!std.ascii.isAlphanumeric(output_str[end]) and output_str[end] != '_');

                if (valid_start and valid_end) {
                    // Skip occurrences inside string literals
                    if (!isInsideStringLiteral(output_str, idx)) {
                        occurrence_count += 1;
                        if (occurrence_count > 1) break;
                    }
                }
                pos = end;
            }

            // If variable only appears once (or not at all), it's unused
            if (occurrence_count <= 1) {
                try self.emitIndent();
                try emitConst(self, "_ = &");
                try self.emitVarName(emit_name);
                try emitConst(self, ";\n");
            }

            // Mark for removal from pending_discards
            try to_remove.append(self.allocator, var_name);
        }

        // Remove processed entries
        for (to_remove.items) |key| {
            _ = self.pending_discards.swapRemove(key);
        }

        // NOTE: VM fallback variable discards are now emitted immediately after assignment
        // in assign.zig (lines 1675-1682) using vm_fallback_analysis pre-pass.
        // This prevents scope issues where discards were emitted outside the variable's scope.
    }

    /// Check if a position in the output is inside a string literal
    /// Scans backward to count unescaped quotes - odd count means inside string
    fn isInsideStringLiteral(output_str: []const u8, pos: usize) bool {
        // Simple heuristic: scan backward from pos to the last newline or semicolon
        // and count unescaped double quotes. Odd count = inside string.
        var quote_count: usize = 0;
        var i = pos;
        while (i > 0) {
            i -= 1;
            const c = output_str[i];
            if (c == '\n' or c == ';') break; // Stop at statement boundary
            if (c == '"') {
                // Check if escaped (preceded by \)
                if (i > 0 and output_str[i - 1] == '\\') {
                    // Could be escaped, but we'd need to count consecutive backslashes
                    // For simplicity, just check one level
                    if (i < 2 or output_str[i - 2] != '\\') continue; // escaped quote, skip
                }
                quote_count += 1;
            }
        }
        return (quote_count % 2) == 1; // Odd count = inside string
    }

    /// Emit discards for variables that were assigned but never used in the generated code
    /// This checks the actual output buffer to count how many times the variable name appears
    /// If it only appears once (in the assignment), it's unused and needs a discard
    /// Should be called at end of function body generation
    pub fn emitPendingDiscards(self: *NativeCodegen) CodegenError!void {
        const output_str = self.output.items;
        // Only search within current function scope (from function_start_pos to end)
        const search_start = self.function_start_pos;
        var it = self.pending_discards.iterator();
        while (it.next()) |entry| {
            const var_name = entry.key_ptr.*;
            const emit_name = entry.value_ptr.*;

            // Skip variables that are not in the current scope
            // This prevents emitting `_ = &exc;` for variables declared inside loops
            // when we're at function level (outside the loop)
            if (!self.symbol_table.isDeclaredInCurrentScope(var_name)) continue;

            // Skip variables that were DISCARDED during tuple unpacking
            // These variables are in pending_discards but were never actually declared
            // Example: `r, w = os.pipe()` where `r` is unused → discarded, not declared
            if (!self.isDeclared(emit_name)) continue;

            // Count occurrences of the variable name as a complete identifier
            // If count <= 1, variable is only used in its own assignment (unused)
            // Skip occurrences inside string literals (e.g., VM fallback strings like "lhs.split()")
            var occurrence_count: usize = 0;
            var pos: usize = search_start;
            while (std.mem.indexOfPos(u8, output_str, pos, emit_name)) |idx| {
                const end = idx + emit_name.len;
                // Check boundaries for complete identifier match
                const valid_start = idx == 0 or (!std.ascii.isAlphanumeric(output_str[idx - 1]) and output_str[idx - 1] != '_');
                const valid_end = end >= output_str.len or (!std.ascii.isAlphanumeric(output_str[end]) and output_str[end] != '_');

                if (valid_start and valid_end) {
                    // Skip occurrences inside string literals
                    if (!isInsideStringLiteral(output_str, idx)) {
                        occurrence_count += 1;
                        if (occurrence_count > 1) break; // Found more than one use, variable is used
                    }
                }
                pos = end;
            }

            // If variable only appears once (or not at all), it's unused
            if (occurrence_count <= 1) {
                try self.emitIndent();
                try emitConst(self, "_ = &");
                try self.emitVarName(emit_name);
                try emitConst(self, ";\n");
            }
        }
        // Clear pending discards after emitting
        self.pending_discards.clearRetainingCapacity();
    }

    /// Post-process output to fix `_ = varname;` patterns that cause "pointless discard" errors
    /// This converts `_ = identifier;` to `_ = &identifier;` which is always valid in Zig.
    /// Only applies to simple identifiers (not expressions like `_ = foo.bar;` or `_ = func();`)
    pub fn fixPointlessDiscards(self: *NativeCodegen) !void {
        const discard_prefix = "_ = ";
        var search_pos: usize = 0;

        // Process each occurrence - need to re-read items each iteration since we modify buffer
        while (true) {
            const output_slice = self.output.items[search_pos..];
            const rel_idx = std.mem.indexOf(u8, output_slice, discard_prefix) orelse break;
            const abs_idx = search_pos + rel_idx;
            const after_prefix = abs_idx + discard_prefix.len;

            // Check if this is already `_ = &` (correct pattern)
            if (after_prefix < self.output.items.len and self.output.items[after_prefix] == '&') {
                search_pos = after_prefix + 1; // Skip past `_ = &`
                continue;
            }

            // Find the semicolon that ends this statement
            var end_pos = after_prefix;
            while (end_pos < self.output.items.len and self.output.items[end_pos] != ';' and self.output.items[end_pos] != '\n') {
                end_pos += 1;
            }

            if (end_pos >= self.output.items.len or self.output.items[end_pos] != ';') {
                search_pos = after_prefix;
                continue;
            }

            // Extract the content between `_ = ` and `;`
            const content = self.output.items[after_prefix..end_pos];

            // Check if content is a simple identifier (only alphanumeric + underscore, no dots/parens/operators)
            // and not an empty string
            if (content.len == 0) {
                search_pos = after_prefix;
                continue;
            }

            var is_simple_ident = true;
            for (content) |c| {
                if (!std.ascii.isAlphanumeric(c) and c != '_') {
                    is_simple_ident = false;
                    break;
                }
            }

            // Also check that it starts with a letter or underscore (valid identifier start)
            if (is_simple_ident and !std.ascii.isAlphabetic(content[0]) and content[0] != '_') {
                is_simple_ident = false;
            }

            if (is_simple_ident) {
                // This is `_ = identifier;` - insert `&` after `_ = `
                try self.output.insertSlice(self.allocator, after_prefix, "&");
                search_pos = after_prefix + 2; // Skip past the `&` we just inserted plus one more
            } else {
                search_pos = after_prefix;
            }
        }
    }

    /// Check if a local variable name would shadow an imported module
    /// In Python, this is fine (local scopes shadow module scope), but in Zig
    /// module imports are file-scope constants that can't be shadowed
    pub fn wouldShadowImport(self: *NativeCodegen, var_name: []const u8) bool {
        return self.imported_modules.contains(var_name);
    }

    /// Get the renamed variable name for DECLARATIONS (const/var statements)
    /// This filters out lazy class attribute patterns "(try X(__alloc))" which are
    /// only for READS (expressions), not for declaring new local variables.
    /// Lazy attribute patterns would produce invalid Zig: `const (try MIN(__alloc)) = ...`
    pub fn getVarDeclName(self: *NativeCodegen, var_name: []const u8) []const u8 {
        if (self.var_renames.get(var_name)) |renamed| {
            // Lazy attribute patterns start with "(try " - don't use for declarations
            if (std.mem.startsWith(u8, renamed, "(try ")) {
                return var_name;
            }
            return renamed;
        }
        return var_name;
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
        const name_copy = try self.arena.allocator().dupe(u8, var_name);
        try self.global_vars.put(name_copy, {});
    }

    /// Clear global vars (call when exiting function scope)
    pub fn clearGlobalVars(self: *NativeCodegen) void {
        cleanup.clearGlobalVars(self);
    }

    /// Clear deferred closure instantiations (call at function boundaries)
    pub fn clearDeferredClosureInstantiations(self: *NativeCodegen) void {
        cleanup.clearDeferredClosureInstantiations(self);
    }

    /// Check if a module was skipped (external module not found)
    pub fn isSkippedModule(self: *NativeCodegen, module_name: []const u8) bool {
        return self.skipped_modules.contains(module_name);
    }

    /// Mark a module as skipped (external module not found)
    pub fn markSkippedModule(self: *NativeCodegen, module_name: []const u8) !void {
        const name_copy = try self.arena.allocator().dupe(u8, module_name);
        try self.skipped_modules.put(name_copy, {});
    }

    /// Check if a module is "codegen only" (has function handlers but no runtime library)
    /// These modules like 'logic_table' are handled purely at compile time via dispatch
    pub fn isCodegenOnlyModule(self: *NativeCodegen, module_name: []const u8) bool {
        return self.codegen_only_modules.contains(module_name);
    }

    /// Mark a module as "codegen only" (function handlers only, no runtime library)
    /// Also tracks in imported_modules so needsVMFallback returns false for these modules
    pub fn markCodegenOnlyModule(self: *NativeCodegen, module_name: []const u8) !void {
        const name_copy = try self.arena.allocator().dupe(u8, module_name);
        try self.codegen_only_modules.put(name_copy, {});
        // Also track as imported so needsVMFallback() returns false for module.func() calls
        try self.imported_modules.put(name_copy, {});
    }

    /// Check if a function was skipped (references skipped modules)
    pub fn isSkippedFunction(self: *NativeCodegen, func_name: []const u8) bool {
        return self.skipped_functions.contains(func_name);
    }

    /// Mark a function as skipped (references skipped modules)
    pub fn markSkippedFunction(self: *NativeCodegen, func_name: []const u8) !void {
        const name_copy = try self.arena.allocator().dupe(u8, func_name);
        try self.skipped_functions.put(name_copy, {});
    }

    /// Known pure Python subpackages of C extension modules
    /// These should NOT be treated as C extensions even though their root module is
    const pure_python_subpackages = std.StaticStringMap(void).initComptime(.{
        // numpy pure Python subpackages
        .{ "numpy.testing", {} },
        .{ "numpy.distutils", {} },
        .{ "numpy.f2py", {} },
        .{ "numpy.doc", {} },
        .{ "numpy.lib", {} },
        .{ "numpy.typing", {} },
        .{ "numpy.ma", {} },
        .{ "numpy.polynomial", {} },
        .{ "numpy.matrixlib", {} },
        // pandas pure Python subpackages
        .{ "pandas.testing", {} },
        .{ "pandas.io", {} },
        // scipy pure Python subpackages
        .{ "scipy.testing", {} },
    });

    /// Check if a module is a C extension (numpy, pandas, etc.)
    /// Also returns true for submodules of C extensions (e.g., numpy.exceptions when numpy is C ext)
    /// BUT returns false for known pure Python subpackages (e.g., numpy.testing)
    pub fn isCExtensionModule(self: *NativeCodegen, module_name: []const u8) bool {
        // Check if it's a known pure Python subpackage - these are NOT C extensions
        if (pure_python_subpackages.has(module_name)) return false;

        // Direct match
        if (self.c_extension_modules.contains(module_name)) return true;

        // Check root module for dotted names (numpy.exceptions -> check numpy)
        if (std.mem.indexOfScalar(u8, module_name, '.')) |dot_idx| {
            const root = module_name[0..dot_idx];
            // Double check - if full path starts with a known pure Python subpackage, skip
            for (pure_python_subpackages.keys()) |pkg| {
                if (std.mem.startsWith(u8, module_name, pkg)) return false;
            }
            return self.c_extension_modules.contains(root);
        }

        return false;
    }

    /// Mark a module as C extension (loaded via PyImport_ImportModule at runtime)
    /// Maps both module_name -> module_name and alias -> module_name
    pub fn markCExtensionModule(self: *NativeCodegen, module_name: []const u8, alias: []const u8) !void {
        const name_copy = try self.arena.allocator().dupe(u8, module_name);
        // Map module_name -> module_name
        try self.c_extension_modules.put(name_copy, name_copy);
        // Also map alias -> module_name (e.g., np -> numpy)
        if (!std.mem.eql(u8, module_name, alias)) {
            const alias_copy = try self.arena.allocator().dupe(u8, alias);
            const name_copy2 = try self.arena.allocator().dupe(u8, module_name);
            try self.c_extension_modules.put(alias_copy, name_copy2);
        }
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
    /// Only returns parent if it's a known class in the registry (not external modules)
    pub fn getParentClassName(self: *NativeCodegen, class_name: []const u8) ?[]const u8 {
        const parent = self.class_registry.inheritance.get(class_name) orelse return null;
        // Only return parent if it's actually in the class registry (locally defined)
        // External parents like "unittest.TestCase" or "string_tests.StringLikeTest"
        // won't have methods we can call, so they're treated as having no known parent
        if (self.class_registry.classes.contains(parent)) {
            return parent;
        }
        return null;
    }

    /// Check if a class is a metaclass (inherits from type)
    /// Used for handling super().__new__() in metaclass __new__ methods
    pub fn isClassMetaclass(self: *NativeCodegen, class_name: []const u8) bool {
        return self.isClassMetaclassWithDepth(class_name, 0);
    }

    fn isClassMetaclassWithDepth(self: *NativeCodegen, class_name: []const u8, depth: usize) bool {
        // Cycle detection: if we've traversed too deep, assume not a metaclass
        if (depth >= MAX_INHERITANCE_DEPTH) {
            return false;
        }

        // Get the parent class from inheritance registry
        const parent = self.class_registry.inheritance.get(class_name) orelse return false;

        // Direct inheritance from type
        if (std.mem.eql(u8, parent, "type")) {
            return true;
        }

        // Check if parent is also a metaclass (recursive with depth tracking)
        return self.isClassMetaclassWithDepth(parent, depth + 1);
    }

    /// Check if a class name inherits from unittest.TestCase (directly or indirectly)
    /// This traverses the inheritance chain through imported modules and local classes
    pub fn isTestCaseSubclass(self: *NativeCodegen, class_name: []const u8) bool {
        return self.isTestCaseSubclassWithDepth(class_name, 0);
    }

    /// Maximum inheritance depth to prevent infinite loops in circular inheritance chains
    const MAX_INHERITANCE_DEPTH = 32;

    fn isTestCaseSubclassWithDepth(self: *NativeCodegen, class_name: []const u8, depth: usize) bool {
        // Cycle detection: if we've traversed too deep, assume not a TestCase subclass
        if (depth >= MAX_INHERITANCE_DEPTH) {
            return false;
        }

        // Direct check for unittest.TestCase
        if (std.mem.eql(u8, class_name, "unittest.TestCase")) {
            return true;
        }

        // Check if this is a known TestCase subclass from imported modules
        // Common test base classes from CPython's test module
        const known_test_bases = [_][]const u8{
            "unittest.TestCase",
            "list_tests.CommonTest",
            "string_tests.CommonTest",
            "string_tests.BaseTest",
            "string_tests.MixinStrUnicodeUserStringTest",
            "mapping_tests.BasicTestMappingProtocol",
            "mapping_tests.TestHashMappingProtocol",
            "seq_tests.CommonTest",
            "support.TestCase",
            "test.support.TestCase",
        };

        for (known_test_bases) |base| {
            if (std.mem.eql(u8, class_name, base)) {
                return true;
            }
        }

        // Check class registry for local class definitions
        if (self.class_registry.getClass(class_name)) |parent_class| {
            if (parent_class.bases.len > 0) {
                // Recursively check parent's base with incremented depth
                return self.isTestCaseSubclassWithDepth(parent_class.bases[0], depth + 1);
            }
        }

        // Check nested class definitions
        if (self.nested_class_defs.get(class_name)) |parent_class| {
            if (parent_class.bases.len > 0) {
                return self.isTestCaseSubclassWithDepth(parent_class.bases[0], depth + 1);
            }
        }

        return false;
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

    // Forward declaration for genSubscriptLHS - generates subscript LHS without block wrapping
    pub fn genSubscriptLHS(self: *NativeCodegen, subscript: ast.Node.Subscript) CodegenError!void {
        const expressions = @import("../expressions.zig");
        try expressions.genSubscriptLHS(self, subscript);
    }

    // Forward declaration for generate (implemented in generator.zig)
    pub fn generate(self: *NativeCodegen, module: ast.Node.Module) ![]const u8 {
        const gen = @import("generator.zig");
        return gen.generate(self, module);
    }
};
