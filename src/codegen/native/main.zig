/// Native Zig code generation - No PyObject overhead
/// Generates stack-allocated native types based on type inference
/// Core module - delegates to json/http/builtins/methods/async
const std = @import("std");
const ast = @import("../../ast.zig");
const native_types = @import("../../analysis/native_types.zig");
const NativeType = native_types.NativeType;
const TypeInferrer = native_types.TypeInferrer;
const SemanticInfo = @import("../../analysis/types.zig").SemanticInfo;

// Import specialized modules
const json = @import("json.zig");
const http = @import("http.zig");
const async_mod = @import("async.zig");
const builtins = @import("builtins.zig");
const methods = @import("methods.zig");
const analyzer = @import("analyzer.zig");
const dispatch = @import("dispatch.zig");
const statements = @import("statements.zig");
const expressions = @import("expressions.zig");
const comptime_eval = @import("../../analysis/comptime_eval.zig");
const symbol_table_mod = @import("symbol_table.zig");
const SymbolTable = symbol_table_mod.SymbolTable;
const ClassRegistry = symbol_table_mod.ClassRegistry;
const MethodInfo = symbol_table_mod.MethodInfo;

const import_registry = @import("import_registry.zig");

/// Error set for code generation
pub const CodegenError = error{
    OutOfMemory,
} || native_types.InferError;

/// Tracks a function with decorators for later application
pub const DecoratedFunction = struct {
    name: []const u8,
    decorators: []ast.Node,
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

    const FromImportInfo = struct {
        module: []const u8,
        names: [][]const u8,
        asnames: []?[]const u8,
    };

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

    /// Compile a Python module to a Zig module file
    fn compileModuleToZig(module_name: []const u8, allocator: std.mem.Allocator) !void {
        // Find the .py file (in same directory or examples/)
        var py_path_buf: [1024]u8 = undefined;
        const py_path = blk: {
            // Try current directory
            const path1 = std.fmt.bufPrint(&py_path_buf, "{s}.py", .{module_name}) catch return;
            std.fs.cwd().access(path1, .{}) catch {
                // Try examples directory
                const path2 = std.fmt.bufPrint(&py_path_buf, "examples/{s}.py", .{module_name}) catch return;
                std.fs.cwd().access(path2, .{}) catch return; // Module not found
                break :blk path2;
            };
            break :blk path1;
        };

        // Read source
        const source = try std.fs.cwd().readFileAlloc(allocator, py_path, 10 * 1024 * 1024);
        defer allocator.free(source);

        // Lex, parse, analyze
        const lexer_mod = @import("../../lexer.zig");
        const parser_mod = @import("../../parser.zig");
        const semantic_types_mod = @import("../../analysis/types.zig");
        const lifetime_analysis_mod = @import("../../analysis/lifetime.zig");
        const native_types_mod = @import("../../analysis/native_types.zig");

        var lex = try lexer_mod.Lexer.init(allocator, source);
        defer lex.deinit();
        const tokens = try lex.tokenize();
        defer allocator.free(tokens);

        var p = parser_mod.Parser.init(allocator, tokens);
        var tree = try p.parse();
        defer tree.deinit(allocator);

        if (tree != .module) return error.InvalidAST;

        var semantic_info = semantic_types_mod.SemanticInfo.init(allocator);
        defer semantic_info.deinit();
        _ = try lifetime_analysis_mod.analyzeLifetimes(&semantic_info, tree, 1);

        var type_inferrer = try native_types_mod.TypeInferrer.init(allocator);
        defer type_inferrer.deinit();
        try type_inferrer.analyze(tree.module);

        // Use full codegen to generate proper module code
        var codegen = try NativeCodegen.init(allocator, &type_inferrer, &semantic_info);
        defer codegen.deinit();

        // Generate imports
        try codegen.emit("const std = @import(\"std\");\n");
        try codegen.emit("const runtime = @import(\"./runtime.zig\");\n\n");

        // Generate only function and class definitions (make all functions pub)
        for (tree.module.body) |stmt| {
            if (stmt == .function_def or stmt == .class_def) {
                // For functions, we need to make them pub
                if (stmt == .function_def) {
                    const func = stmt.function_def;
                    try codegen.emit("pub ");

                    // Generate async keyword if needed
                    if (func.is_async) {
                        try codegen.emit("async ");
                    }

                    try codegen.emit("fn ");
                    try codegen.emit(func.name);
                    try codegen.emit("(");

                    // Parameters with type inference
                    for (func.args, 0..) |arg, i| {
                        if (i > 0) try codegen.emit(", ");
                        try codegen.emit(arg.name);
                        try codegen.emit(": ");

                        // Try to infer parameter type
                        const param_type = type_inferrer.var_types.get(arg.name) orelse native_types_mod.NativeType.int;
                        const type_str = switch (param_type) {
                            .int => "i64",
                            .float => "f64",
                            .bool => "bool",
                            .string => "[]const u8",
                            else => "i64",
                        };
                        try codegen.emit(type_str);
                    }

                    // Add allocator parameter for module functions
                    if (func.args.len > 0) try codegen.emit(", ");
                    try codegen.emit("allocator: std.mem.Allocator");

                    try codegen.emit(") ");

                    // Return type - default to i64
                    try codegen.emit("i64");
                    try codegen.emit(" {\n");

                    codegen.indent();

                    // Generate function body using full codegen
                    for (func.body) |body_stmt| {
                        try codegen.generateStmt(body_stmt);
                    }

                    codegen.dedent();
                    try codegen.emit("}\n\n");
                } else {
                    // For classes, use the full codegen
                    try statements.genClassDef(codegen, stmt.class_def);
                }
            }
        }

        const zig_code = try codegen.output.toOwnedSlice(allocator);
        defer allocator.free(zig_code);

        // Write to .build/module_name.zig
        const zig_path = try std.fmt.allocPrint(allocator, ".build/{s}.zig", .{module_name});
        defer allocator.free(zig_path);

        const file = try std.fs.cwd().createFile(zig_path, .{});
        defer file.close();
        try file.writeAll(zig_code);
    }

    /// Scan AST for import statements and collect module names with registry lookup
    fn collectImports(self: *NativeCodegen, module: ast.Node.Module) !std.ArrayList([]const u8) {
        var imports = std.ArrayList([]const u8){};

        // Collect unique Python module names from import statements
        var module_names = std.StringHashMap(void).init(self.allocator);
        defer module_names.deinit();

        // Clear previous from-imports
        self.from_imports.clearRetainingCapacity();

        for (module.body) |stmt| {
            // Handle both "import X" and "from X import Y"
            switch (stmt) {
                .import_stmt => |imp| {
                    const module_name = imp.module;
                    try module_names.put(module_name, {});
                },
                .import_from => |imp| {
                    const module_name = imp.module;
                    try module_names.put(module_name, {});

                    // Store from-import info for symbol re-export generation
                    try self.from_imports.append(self.allocator, FromImportInfo{
                        .module = module_name,
                        .names = imp.names,
                        .asnames = imp.asnames,
                    });
                },
                else => {},
            }
        }

        // Process each module using registry
        var iter = module_names.keyIterator();
        while (iter.next()) |python_module| {
            if (self.import_registry.lookup(python_module.*)) |info| {
                switch (info.strategy) {
                    .zig_runtime, .c_library => {
                        // Include modules with Zig implementations
                        try imports.append(self.allocator, python_module.*);
                    },
                    .compile_python => {
                        // Include for compilation (will be handled in generate())
                        try imports.append(self.allocator, python_module.*);
                    },
                    .unsupported => {
                        std.debug.print("Warning: Module '{s}' not supported yet\n", .{python_module.*});
                    },
                }
            } else {
                // Module not in registry - warn and assume user module
                std.debug.print("Warning: Module '{s}' not in registry, assuming user module\n", .{python_module.*});
                try imports.append(self.allocator, python_module.*);
            }
        }

        return imports;
    }

    /// Generate native Zig code for module
    pub fn generate(self: *NativeCodegen, module: ast.Node.Module) ![]const u8 {
        // PHASE 1: Analyze module to determine requirements
        const analysis = try analyzer.analyzeModule(module, self.allocator);

        // PHASE 1.5: Collect imports and compile imported modules
        var imported_modules = try self.collectImports(module);
        defer imported_modules.deinit(self.allocator);

        // Compile each imported module to .zig file
        for (imported_modules.items) |mod_name| {
            try compileModuleToZig(mod_name, self.allocator);
        }

        // PHASE 2: Register all classes for inheritance support
        for (module.body) |stmt| {
            if (stmt == .class_def) {
                try self.class_registry.registerClass(stmt.class_def.name, stmt.class_def);
            }
        }

        // PHASE 3: Generate imports based on analysis
        try self.emit("const std = @import(\"std\");\n");
        // Always import runtime for formatAny() and other utilities
        try self.emit("const runtime = @import(\"./runtime.zig\");\n");
        if (analysis.needs_string_utils) {
            try self.emit("const string_utils = @import(\"string_utils.zig\");\n");
        }

        // PHASE 3.5: Generate C library imports (if any detected)
        if (self.import_ctx) |ctx| {
            const c_import_block = try ctx.generateCImportBlock(self.allocator);
            defer self.allocator.free(c_import_block);
            if (c_import_block.len > 0) {
                try self.emit(c_import_block);
            }
        }

        // Add user module imports using registry
        for (imported_modules.items) |mod_name| {
            try self.emit("const ");
            try self.emit(mod_name);
            try self.emit(" = ");

            // Look up module in registry
            if (self.import_registry.lookup(mod_name)) |info| {
                switch (info.strategy) {
                    .zig_runtime, .c_library => {
                        // Use Zig import from registry
                        if (info.zig_import) |zig_import| {
                            try self.emit(zig_import);
                        } else {
                            // Fallback to user module
                            try self.emit("@import(\"");
                            try self.emit(mod_name);
                            try self.emit(".zig\")");
                        }
                    },
                    .compile_python => {
                        // Import compiled Python module
                        try self.emit("@import(\"");
                        try self.emit(mod_name);
                        try self.emit(".zig\")");
                    },
                    .unsupported => {
                        // Generate comment for unsupported modules
                        try self.emit("struct {}; // TODO: ");
                        try self.emit(mod_name);
                        try self.emit(" not supported yet");
                    },
                }
            } else {
                // Module not in registry - assume user module
                try self.emit("@import(\"");
                try self.emit(mod_name);
                try self.emit(".zig\")");
            }
            try self.emit(";\n");
        }

        try self.emit("\n");

        // PHASE 3.6: Generate from-import symbol re-exports
        // For "from json import loads", generate: const loads = json.loads;
        for (self.from_imports.items) |from_imp| {
            // Check if this is a Tier 1 runtime module (functions need allocator)
            const is_runtime_module = self.import_registry.lookup(from_imp.module) != null and
                (std.mem.eql(u8, from_imp.module, "json") or
                std.mem.eql(u8, from_imp.module, "http") or
                std.mem.eql(u8, from_imp.module, "asyncio"));

            for (from_imp.names, 0..) |name, i| {
                // Get the symbol name (use alias if provided)
                const symbol_name = if (i < from_imp.asnames.len and from_imp.asnames[i] != null)
                    from_imp.asnames[i].?
                else
                    name;

                // Skip import * for now (complex to implement)
                if (std.mem.eql(u8, name, "*")) {
                    std.debug.print("Warning: 'from {s} import *' not supported yet\n", .{from_imp.module});
                    continue;
                }

                // Track if this symbol needs allocator (runtime module functions)
                if (is_runtime_module) {
                    try self.from_import_needs_allocator.put(symbol_name, {});
                }

                // Generate: const symbol_name = module.name;
                try self.emit("const ");
                try self.emit(symbol_name);
                try self.emit(" = ");
                try self.emit(from_imp.module);
                try self.emit(".");
                try self.emit(name);
                try self.emit(";\n");
            }
        }

        if (self.from_imports.items.len > 0) {
            try self.emit("\n");
        }

        // PHASE 4: Define __name__ constant (for if __name__ == "__main__" support)
        try self.emit("const __name__ = \"__main__\";\n\n");

        // PHASE 5: Generate imports, class and function definitions (before main)
        for (module.body) |stmt| {
            if (stmt == .import_stmt) {
                try statements.genImport(self, stmt.import_stmt);
            } else if (stmt == .import_from) {
                try statements.genImportFrom(self, stmt.import_from);
            } else if (stmt == .class_def) {
                try statements.genClassDef(self, stmt.class_def);
                try self.emit("\n");
            } else if (stmt == .function_def) {
                try statements.genFunctionDef(self, stmt.function_def);
                try self.emit("\n");
            }
        }

        // PHASE 6: Generate main function
        try self.emit("pub fn main() !void {\n");
        self.indent();

        // Setup allocator (only if needed)
        if (analysis.needs_allocator) {
            try self.emitIndent();
            try self.emit("var gpa = std.heap.GeneralPurposeAllocator(.{}){};\n");
            try self.emitIndent();
            try self.emit("defer _ = gpa.deinit();\n");
            try self.emitIndent();
            try self.emit("const allocator = gpa.allocator();\n");
            // Suppress unused warning if there are constant arrays that don't need allocation
            if (self.array_vars.count() > 0) {
                try self.emitIndent();
                try self.emit("_ = allocator; // May be unused if only constant arrays\n");
            }
            try self.emit("\n");
        }

        // PHASE 6.5: Apply decorators (after allocator, before other code)
        // This allows decorators to run after variables are defined but before main logic
        if (self.decorated_functions.items.len > 0) {
            try self.emitIndent();
            try self.emit("// Apply decorators\n");
            for (self.decorated_functions.items) |decorated_func| {
                for (decorated_func.decorators) |decorator| {
                    try self.emitIndent();
                    try self.emit("_ = ");
                    try self.genExpr(decorator);
                    try self.emit("(&");
                    try self.emit(decorated_func.name);
                    try self.emit(");\n");
                }
            }
            try self.emit("\n");
        }

        // PHASE 7: Generate statements (skip class/function defs and imports - already handled)
        // This will populate self.lambda_functions
        for (module.body) |stmt| {
            if (stmt != .function_def and stmt != .class_def and stmt != .import_stmt and stmt != .import_from) {
                try self.generateStmt(stmt);
            }
        }

        self.dedent();
        try self.emit("}\n");

        // PHASE 8: Prepend lambda functions if any were generated
        if (self.lambda_functions.items.len > 0) {
            // Get current output
            const current_output = try self.output.toOwnedSlice(self.allocator);
            defer self.allocator.free(current_output);

            // Rebuild output with lambdas first
            self.output = std.ArrayList(u8){};

            // Add imports
            try self.emit("const std = @import(\"std\");\n");
            try self.emit("const runtime = @import(\"./runtime.zig\");\n");
            if (analysis.needs_string_utils) {
                try self.emit("const string_utils = @import(\"string_utils.zig\");\n");
            }
            try self.emit("\n");

            // Add __name__ constant
            try self.emit("const __name__ = \"__main__\";\n\n");

            // Add lambda functions
            for (self.lambda_functions.items) |lambda_code| {
                try self.output.appendSlice(self.allocator, lambda_code);
            }

            // Find where class/function definitions start (after first two const declarations)
            // Parse current_output to extract everything after imports and __name__
            var lines = std.mem.splitScalar(u8, current_output, '\n');
            var skip_count: usize = 0;
            while (lines.next()) |line| {
                skip_count += 1;
                if (std.mem.indexOf(u8, line, "const __name__") != null) {
                    // Skip this line and the blank line after
                    _ = lines.next(); // blank line
                    skip_count += 1;
                    break;
                }
            }

            // Append the rest of the original output (class/func defs + main)
            var lines2 = std.mem.splitScalar(u8, current_output, '\n');
            var i: usize = 0;
            while (lines2.next()) |line| : (i += 1) {
                if (i >= skip_count) {
                    try self.output.appendSlice(self.allocator, line);
                    try self.output.appendSlice(self.allocator, "\n");
                }
            }
        }

        return self.output.toOwnedSlice(self.allocator);
    }

    pub fn generateStmt(self: *NativeCodegen, node: ast.Node) CodegenError!void {
        switch (node) {
            .assign => |assign| try statements.genAssign(self, assign),
            .aug_assign => |aug| try statements.genAugAssign(self, aug),
            .expr_stmt => |expr| try statements.genExprStmt(self, expr.value.*),
            .if_stmt => |if_stmt| try statements.genIf(self, if_stmt),
            .while_stmt => |while_stmt| try statements.genWhile(self, while_stmt),
            .for_stmt => |for_stmt| try statements.genFor(self, for_stmt),
            .return_stmt => |ret| try statements.genReturn(self, ret),
            .assert_stmt => |assert_node| try statements.genAssert(self, assert_node),
            .try_stmt => |try_node| try statements.genTry(self, try_node),
            .class_def => |class| try statements.genClassDef(self, class),
            .import_stmt => |import| try statements.genImport(self, import),
            .import_from => |import| try statements.genImportFrom(self, import),
            .pass => try statements.genPass(self),
            .break_stmt => try statements.genBreak(self),
            .continue_stmt => try statements.genContinue(self),
            else => {},
        }
    }

    // Expression generation delegated to expressions.zig
    pub fn genExpr(self: *NativeCodegen, node: ast.Node) CodegenError!void {
        try expressions.genExpr(self, node);
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
};
