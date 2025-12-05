/// Core NativeCodegen struct and basic operations
const std = @import("std");
const ast = @import("ast");
const zig_keywords = @import("zig_keywords");
const native_types = @import("../../../analysis/native_types.zig");
const NativeType = native_types.NativeType;
const TypeInferrer = native_types.TypeInferrer;
const SemanticInfo = @import("../../../analysis/types.zig").SemanticInfo;
const comptime_eval = @import("../../../analysis/comptime_eval.zig");
const function_traits = @import("function_traits");
const symbol_table_mod = @import("../symbol_table.zig");
const SymbolTable = symbol_table_mod.SymbolTable;
const ClassRegistry = symbol_table_mod.ClassRegistry;
const MethodInfo = symbol_table_mod.MethodInfo;
const import_registry = @import("../import_registry.zig");
const fnv_hash = @import("fnv_hash");
const cleanup = @import("cleanup.zig");
const debug_info = @import("debug_info");

const hashmap_helper = @import("hashmap_helper");
const FnvVoidMap = hashmap_helper.StringHashMap(void);
const FnvStringMap = hashmap_helper.StringHashMap([]const u8);
const FnvFuncDefMap = hashmap_helper.StringHashMap(ast.Node.FunctionDef);
const FnvClassDefMap = hashmap_helper.StringHashMap(ast.Node.ClassDef);

// Function signature info for default parameter handling
const FuncSignature = struct {
    total_params: usize,
    required_params: usize, // params without defaults
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

    // Counter for unique __TryHelper struct names (avoids shadowing in nested try blocks)
    try_helper_counter: usize,

    // When inside a try helper that contains break/continue, stores the helper ID for special handling
    // null = not in try helper with break/continue, non-null = emit return error.BreakRequested
    try_break_helper_id: ?usize,

    // Lambda support - counter for unique names, storage for lambda function definitions
    lambda_counter: usize,
    lambda_functions: std.ArrayList([]const u8),

    // Counter for unique block labels (avoids nested blk: redefinition)
    block_label_counter: usize,

    // Counter for unique shadow variable names (tuple += creates new const)
    shadow_counter: usize,

    // Track which variables hold closures (for .call() generation)
    closure_vars: FnvVoidMap,

    // Track closures that return void (no catch needed)
    void_closure_vars: FnvVoidMap,

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

    // Track first assignments that may need discards (var_name -> emitted_name)
    // Discards are emitted at end of scope after checking if variable was actually used
    pending_discards: FnvStringMap,

    // Starting position in output buffer for current function
    // Used to limit variable usage search to current function scope only
    function_start_pos: usize,

    // Track which variables hold constant arrays (vs ArrayLists)
    array_vars: FnvVoidMap,

    // Track which variables hold array slices (result of slicing a constant array)
    array_slice_vars: FnvVoidMap,

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

    // Track anytype parameters in current function scope (for comprehension iteration)
    anytype_params: FnvVoidMap,

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

    // Track import aliases (import X as Y)
    // Maps alias name -> module name (e.g., "support" -> "test.support")
    import_aliases: FnvStringMap,

    // Track variable mutations (for list ArrayList vs fixed array decision)
    // Maps variable name -> mutation info
    mutation_info: ?*const @import("../../../analysis/native_types/mutation_analyzer.zig").MutationMap,

    // Track if we're inside a 'with self.assertRaises' context
    // When true, error-producing operations should use catch instead of try
    in_assert_raises_context: bool,

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

    // Track classes that have been hoisted from method bodies to struct level
    // Maps original class name -> actual generated name (which may be renamed due to collisions)
    // These classes should be skipped during normal body generation
    hoisted_local_classes: FnvStringMap,

    // Track variables assigned from BigInt expressions
    // Used to detect when a variable's type is BigInt for subsequent operations
    bigint_vars: FnvVoidMap,

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

    // Track class-level type attributes (e.g., int_class = int)
    // Maps "ClassName.attr_name" -> type_name (e.g., "IntStrDigitLimitsTests.int_class" -> "int")
    class_type_attrs: FnvStringMap,

    // Current class being generated (for super() support)
    // Set during class method generation, null otherwise
    current_class_name: ?[]const u8,

    // Current class body (list of statements) - for checking if params shadow sibling methods
    current_class_body: ?[]ast.Node,

    // Current assignment target name (for type-aware empty list generation)
    // Set during assignment generation, null otherwise
    current_assign_target: ?[]const u8,

    // Captured variables for the current class (from parent scope)
    // Set when entering a class with captured variables, null otherwise
    // Used by expression generator to convert `var_name` to `self.__captured_var_name.*`
    current_class_captures: ?[][]const u8,

    // True when inside __init__ method - captured vars accessed via __cap_* params, not self
    inside_init_method: bool,

    // True when inside __new__ method - captured vars accessed via __cls, not __self
    inside_new_method: bool,

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

    // True when generating code inside a nested function/closure body
    // When true, isDeclared() only checks current scope, not parent function scopes
    // This ensures variables from outer function that weren't captured are treated as undeclared
    inside_nested_function: bool,

    // Current function being generated (for tail-call optimization)
    // Set during function generation, null otherwise
    current_function_name: ?[]const u8,

    // Current function/method body being generated
    // Used for lookahead-based type inference (e.g., dict key type from subscript assignments)
    current_function_body: ?[]const ast.Node,

    // Track if we're inside a generator function
    // When true, yield statements append to __gen_result ArrayList
    in_generator_function: bool,

    // Track skipped modules (external modules not found in registry)
    // Maps module name -> void (e.g., "pytest" -> {})
    // Used to skip code that references these modules
    skipped_modules: FnvVoidMap,

    // Track skipped functions (functions that reference skipped modules)
    // Maps function name -> void (e.g., "run_code" -> {})
    // Used to skip calls to functions that weren't generated
    skipped_functions: FnvVoidMap,

    // Track C extension modules (numpy, pandas, etc.)
    // Maps module name -> alias name (e.g., "numpy" -> "np", "pandas" -> "pd")
    // These are loaded at runtime via PyImport_ImportModule
    c_extension_modules: FnvStringMap,

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

    // Track forward-declared variables (captured by nested classes before defined)
    // Maps variable name -> void (e.g., "list2" -> {})
    // When assigning to a forward-declared var, don't emit "var" again
    forward_declared_vars: FnvVoidMap,

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
    token_lines: ?std.StringHashMap(u32),

    // Keyword occurrence counters for debug line mapping
    // Track how many times we've processed each keyword type during codegen
    keyword_raise_count: u32,
    keyword_assert_count: u32,

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
            .try_helper_counter = 0,
            .try_break_helper_id = null,
            .lambda_counter = 0,
            .lambda_functions = std.ArrayList([]const u8){},
            .block_label_counter = 0,
            .shadow_counter = 0,
            .closure_vars = FnvVoidMap.init(allocator),
            .void_closure_vars = FnvVoidMap.init(allocator),
            .callable_vars = FnvVoidMap.init(allocator),
            .error_callable_vars = FnvVoidMap.init(allocator),
            .recursive_closure_vars = hashmap_helper.StringHashMap([][]const u8).init(allocator),
            .closure_factories = FnvVoidMap.init(allocator),
            .pending_closure_types = FnvStringMap.init(allocator),
            .deferred_closure_instantiations = hashmap_helper.StringHashMap(std.ArrayList(DeferredClosureInfo)).init(allocator),
            .closure_returning_methods = FnvVoidMap.init(allocator),
            .lambda_vars = FnvVoidMap.init(allocator),
            .callable_context_param_type = null,
            .var_renames = FnvStringMap.init(allocator),
            .hoisted_vars = FnvVoidMap.init(allocator),
            .pending_discards = FnvStringMap.init(allocator),
            .function_start_pos = 0,
            .array_vars = FnvVoidMap.init(allocator),
            .array_slice_vars = FnvVoidMap.init(allocator),
            .arraylist_vars = FnvVoidMap.init(allocator),
            .arraylist_aliases = FnvStringMap.init(allocator),
            .class_instance_aliases = FnvStringMap.init(allocator),
            .dict_vars = FnvVoidMap.init(allocator),
            .anytype_params = FnvVoidMap.init(allocator),
            .mutable_classes = FnvVoidMap.init(allocator),
            .error_init_classes = FnvVoidMap.init(allocator),
            .unittest_classes = std.ArrayList(TestClassInfo){},
            .test_factories = hashmap_helper.StringHashMap(TestFactoryInfo).init(allocator),
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
            .import_aliases = FnvStringMap.init(allocator),
            .mutation_info = null,
            .in_assert_raises_context = false,
            .control_flow_terminated = false,
            .c_libraries = std.ArrayList([]const u8){},
            .comptime_evals = FnvVoidMap.init(allocator),
            .interned_strings = hashmap_helper.StringHashMap(usize).init(allocator),
            .intern_list = std.ArrayList([]const u8){},
            .intern_counter = 0,
            .func_local_mutations = FnvVoidMap.init(allocator),
            .func_local_aug_assigns = FnvVoidMap.init(allocator),
            .func_local_uses = FnvVoidMap.init(allocator),
            .global_vars = FnvVoidMap.init(allocator),
            .module_level_funcs = FnvVoidMap.init(allocator),
            .module_level_vars = FnvVoidMap.init(allocator),
            .func_local_vars = FnvVoidMap.init(allocator),
            .nested_class_captures = hashmap_helper.StringHashMap([][]const u8).init(allocator),
            .mutated_captures = FnvVoidMap.init(allocator),
            .nested_class_instances = hashmap_helper.StringHashMap([]const u8).init(allocator),
            .nested_class_names = FnvVoidMap.init(allocator),
            .hoisted_local_classes = FnvStringMap.init(allocator),
            .bigint_vars = FnvVoidMap.init(allocator),
            .nested_class_bases = FnvStringMap.init(allocator),
            .nested_class_defs = FnvClassDefMap.init(allocator),
            .nested_class_method_needs_alloc = FnvVoidMap.init(allocator),
            .nested_class_zig_refs = FnvVoidMap.init(allocator),
            .class_type_attrs = FnvStringMap.init(allocator),
            .current_class_name = null,
            .current_class_body = null,
            .current_assign_target = null,
            .current_class_captures = null,
            .inside_init_method = false,
            .inside_new_method = false,
            .method_self_is_mutable = false,
            .current_method_first_param = null,
            .current_class_parent = null,
            .class_nesting_depth = 0,
            .method_nesting_depth = 0,
            .inside_method_with_self = false,
            .current_scope_id = 0,
            .inside_defer = false,
            .inside_nested_function = false,
            .current_function_name = null,
            .current_function_body = null,
            .in_generator_function = false,
            .skipped_modules = FnvVoidMap.init(allocator),
            .skipped_functions = FnvVoidMap.init(allocator),
            .c_extension_modules = FnvStringMap.init(allocator),
            .local_var_types = hashmap_helper.StringHashMap(NativeType).init(allocator),
            .local_from_imports = FnvStringMap.init(allocator),
            .loop_capture_vars = FnvVoidMap.init(allocator),
            .callable_global_vars = FnvVoidMap.init(allocator),
            .import_module_vars = FnvVoidMap.init(allocator),
            .csv_iterators = FnvVoidMap.init(allocator),
            .forward_declared_vars = FnvVoidMap.init(allocator),
            .call_graph = null,
            .generic_type_params = FnvVoidMap.init(allocator),
            .generic_classes = hashmap_helper.StringHashMap(usize).init(allocator),
            .ctypes_functions = hashmap_helper.StringHashMap(CTypesFuncInfo).init(allocator),
            .debug_writer = null,
            .zig_line_counter = 1,
            .tokens = null,
            .token_lines = null,
            .keyword_raise_count = 0,
            .keyword_assert_count = 0,
        };
        return self;
    }

    pub fn setImportContext(self: *NativeCodegen, ctx: *const @import("c_interop").ImportContext) void {
        self.import_ctx = ctx;
    }

    pub fn setSourceFilePath(self: *NativeCodegen, path: []const u8) void {
        self.source_file_path = path;
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
                self.token_lines = std.StringHashMap(u32).init(self.allocator);
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

    /// Intern a string literal and return its index
    /// Returns existing index if already interned, or creates new entry
    pub fn internString(self: *NativeCodegen, content: []const u8) !usize {
        // Check if already interned
        if (self.interned_strings.get(content)) |idx| {
            return idx;
        }

        // Add new interned string
        const idx = self.intern_counter;
        const duped = try self.allocator.dupe(u8, content);
        try self.interned_strings.put(duped, idx);
        try self.intern_list.append(self.allocator, duped);
        self.intern_counter += 1;
        return idx;
    }

    /// Generate the intern table at module level
    /// Called at the start of code generation
    pub fn genInternTable(self: *NativeCodegen) !void {
        if (self.intern_list.items.len == 0) return;

        try self.emit("\n// Interned string literals (O(1) equality via pointer comparison)\n");
        try self.emit("const __intern = struct {\n");

        for (self.intern_list.items, 0..) |str, i| {
            try self.output.writer(self.allocator).print("    pub const s{d}: []const u8 = \"{s}\";\n", .{ i, str });
        }

        try self.emit("};\n\n");
    }

    /// Get the reference to an interned string by index
    pub fn getInternRef(self: *NativeCodegen, idx: usize) !void {
        try self.output.writer(self.allocator).print("__intern.s{d}", .{idx});
    }

    /// Build call graph from module AST for unified function analysis
    /// Call this once before generate() to enable traits-based codegen decisions
    pub fn buildCallGraph(self: *NativeCodegen, module: ast.Node.Module) !void {
        self.call_graph = try function_traits.buildCallGraph(module, self.allocator);
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

        if (self.inside_nested_function) {
            // Inside nested function: check current scope OR var_renames (for captured vars)
            // Variables from outer scope that weren't captured should be treated as undeclared
            if (self.symbol_table.isDeclaredInCurrentScope(name)) return true;
            // Captured variables are in var_renames, they should count as "declared"
            return self.var_renames.contains(name);
        }
        return self.symbol_table.lookup(name) != null;
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

    /// Infer expression type with scope-aware variable type lookup
    /// For variables, prefers local scope type over global type inferrer
    /// This prevents cross-function type pollution from widened types
    pub fn inferExprScoped(self: *NativeCodegen, node: ast.Node) !NativeType {
        // For name nodes, check local scope first
        if (node == .name) {
            const original_name = node.name.id;
            // Check if variable has been renamed (e.g., loop capture line -> __loop_line)
            const renamed_name = self.var_renames.get(original_name) orelse original_name;
            // Check symbol table FIRST for locally-declared types (e.g., PyValue loop vars)
            // This takes precedence over bigint_vars because we may have re-declared the var
            if (self.symbol_table.getType(renamed_name)) |local_type| {
                // Only use local type if it's not unknown
                if (local_type != .unknown) {
                    return local_type;
                }
            }
            // Check if this variable was assigned from a BigInt expression
            if (self.bigint_vars.contains(renamed_name)) {
                return .bigint;
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
            if (self.type_inferrer.getScopedVar(original_name)) |scoped_type| {
                if (scoped_type != .unknown) {
                    return scoped_type;
                }
            }
            // Fallback to global var_types ONLY if not in a function scope
            // This prevents pollution from same-named variables in other functions
            if (self.current_function_name == null) {
                if (self.type_inferrer.var_types.get(original_name)) |var_type| {
                    if (var_type != .unknown) {
                        return var_type;
                    }
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

    // Helper functions - public for use by statements.zig and expressions.zig
    pub fn emit(self: *NativeCodegen, s: []const u8) CodegenError!void {
        try self.output.appendSlice(self.allocator, s);
        // Track newlines for debug info (Zig line counting)
        for (s) |c| {
            if (c == '\n') {
                self.zig_line_counter += 1;
            }
        }
    }

    /// Emit formatted string
    pub fn emitFmt(self: *NativeCodegen, comptime fmt: []const u8, args: anytype) CodegenError!void {
        const start_len = self.output.items.len;
        try self.output.writer(self.allocator).print(fmt, args);
        // Track newlines for debug info (Zig line counting)
        const new_content = self.output.items[start_len..];
        for (new_content) |c| {
            if (c == '\n') {
                self.zig_line_counter += 1;
            }
        }
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
        // Also clear var_renames - these are function-local shadow renames
        // (e.g., rslices -> __local_rslices_1 inside a function that has local `rslices = [0]*ndim`)
        self.var_renames.clearRetainingCapacity();
    }

    /// Check if a variable is mutated (reassigned after first assignment)
    /// Checks both module-level semantic info AND function-local mutations
    pub fn isVarMutated(self: *NativeCodegen, var_name: []const u8) bool {
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
            var occurrence_count: usize = 0;
            var pos: usize = search_start;
            while (std.mem.indexOfPos(u8, output_str, pos, emit_name)) |idx| {
                const end = idx + emit_name.len;
                const valid_start = idx == 0 or (!std.ascii.isAlphanumeric(output_str[idx - 1]) and output_str[idx - 1] != '_');
                const valid_end = end >= output_str.len or (!std.ascii.isAlphanumeric(output_str[end]) and output_str[end] != '_');

                if (valid_start and valid_end) {
                    occurrence_count += 1;
                    if (occurrence_count > 1) break;
                }
                pos = end;
            }

            // If variable only appears once (or not at all), it's unused
            if (occurrence_count <= 1) {
                try self.emitIndent();
                try self.emit("_ = &");
                try zig_keywords.writeLocalVarName(self.output.writer(self.allocator), emit_name);
                try self.emit(";\n");
            }

            // Mark for removal from pending_discards
            try to_remove.append(self.allocator, var_name);
        }

        // Remove processed entries
        for (to_remove.items) |key| {
            _ = self.pending_discards.swapRemove(key);
        }
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
            const emit_name = entry.value_ptr.*;
            // Count occurrences of the variable name as a complete identifier
            // If count <= 1, variable is only used in its own assignment (unused)
            var occurrence_count: usize = 0;
            var pos: usize = search_start;
            while (std.mem.indexOfPos(u8, output_str, pos, emit_name)) |idx| {
                const end = idx + emit_name.len;
                // Check boundaries for complete identifier match
                const valid_start = idx == 0 or (!std.ascii.isAlphanumeric(output_str[idx - 1]) and output_str[idx - 1] != '_');
                const valid_end = end >= output_str.len or (!std.ascii.isAlphanumeric(output_str[end]) and output_str[end] != '_');

                if (valid_start and valid_end) {
                    occurrence_count += 1;
                    if (occurrence_count > 1) break; // Found more than one use, variable is used
                }
                pos = end;
            }

            // If variable only appears once (or not at all), it's unused
            if (occurrence_count <= 1) {
                try self.emitIndent();
                try self.emit("_ = &");
                try zig_keywords.writeLocalVarName(self.output.writer(self.allocator), emit_name);
                try self.emit(";\n");
            }
        }
        // Clear pending discards after emitting
        self.pending_discards.clearRetainingCapacity();
    }

    /// Check if a local variable name would shadow an imported module
    /// In Python, this is fine (local scopes shadow module scope), but in Zig
    /// module imports are file-scope constants that can't be shadowed
    pub fn wouldShadowImport(self: *NativeCodegen, var_name: []const u8) bool {
        return self.imported_modules.contains(var_name);
    }

    /// Get a safe local variable name that won't shadow imported modules
    /// Returns the original name if it doesn't conflict, or name_local if it does
    pub fn getSafeLocalName(self: *NativeCodegen, var_name: []const u8) ![]const u8 {
        if (self.wouldShadowImport(var_name)) {
            return try std.fmt.allocPrint(self.allocator, "{s}_local", .{var_name});
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
        const name_copy = try self.allocator.dupe(u8, var_name);
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

    /// Check if a module is a C extension (numpy, pandas, etc.)
    pub fn isCExtensionModule(self: *NativeCodegen, module_name: []const u8) bool {
        return self.c_extension_modules.contains(module_name);
    }

    /// Mark a module as C extension (loaded via PyImport_ImportModule at runtime)
    /// Maps both module_name -> module_name and alias -> module_name
    pub fn markCExtensionModule(self: *NativeCodegen, module_name: []const u8, alias: []const u8) !void {
        const name_copy = try self.allocator.dupe(u8, module_name);
        // Map module_name -> module_name
        try self.c_extension_modules.put(name_copy, name_copy);
        // Also map alias -> module_name (e.g., np -> numpy)
        if (!std.mem.eql(u8, module_name, alias)) {
            const alias_copy = try self.allocator.dupe(u8, alias);
            const name_copy2 = try self.allocator.dupe(u8, module_name);
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

    /// Check if a class name inherits from unittest.TestCase (directly or indirectly)
    /// This traverses the inheritance chain through imported modules and local classes
    pub fn isTestCaseSubclass(self: *NativeCodegen, class_name: []const u8) bool {
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
                // Recursively check parent's base
                return self.isTestCaseSubclass(parent_class.bases[0]);
            }
        }

        // Check nested class definitions
        if (self.nested_class_defs.get(class_name)) |parent_class| {
            if (parent_class.bases.len > 0) {
                return self.isTestCaseSubclass(parent_class.bases[0]);
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
