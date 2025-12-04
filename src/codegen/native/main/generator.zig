/// Main code generation functions
const std = @import("std");
const ast = @import("ast");
const core = @import("core.zig");
const NativeCodegen = core.NativeCodegen;
const CodegenError = core.CodegenError;
const imports = @import("imports.zig");
const from_imports_gen = @import("from_imports.zig");
const analyzer = @import("../analyzer.zig");
const statements = @import("../statements.zig");
const expressions = @import("../expressions.zig");
const import_resolver = @import("../../../import_resolver.zig");
const zig_keywords = @import("zig_keywords");
const hashmap_helper = @import("hashmap_helper");
const build_dirs = @import("../../../build_dirs.zig");

// Comptime constants for code generation (zero runtime cost)
const BUILD_DIR = build_dirs.CACHE;
const MODULE_EXT = ".zig";
const IMPORT_PREFIX = "./";
const MAIN_NAME = "__main__";

/// Generate native Zig code for module
pub fn generate(self: *NativeCodegen, module: ast.Node.Module) ![]const u8 {
    // PHASE 1: Analyze module to determine requirements
    const analysis = try analyzer.analyzeModule(module, self.allocator);
    defer if (analysis.global_vars.len > 0) self.allocator.free(analysis.global_vars);

    // Pre-register global variables so they can be detected during method generation
    // This prevents local variables with the same name from shadowing module-level vars
    for (analysis.global_vars) |var_name| {
        try self.markGlobalVar(var_name);
    }

    // PHASE 1.5: Get source file directory for import resolution
    const source_file_dir = if (self.source_file_path) |path|
        try import_resolver.getFileDirectory(path, self.allocator)
    else
        null;
    defer if (source_file_dir) |dir| self.allocator.free(dir);

    // PHASE 1.6: Collect imports and compile imported modules as inlined structs
    var imported_modules = try imports.collectImports(self, module, source_file_dir);
    defer imported_modules.deinit(self.allocator);

    // Store compiled module structs for later emission
    var inlined_modules = std.ArrayList([]const u8){};
    defer {
        for (inlined_modules.items) |code| self.allocator.free(code);
        inlined_modules.deinit(self.allocator);
    }

    // Generate @import() statements for compiled modules
    // Track which root modules have been imported to avoid duplicates
    var imported_roots = hashmap_helper.StringHashMap(void).init(self.allocator);
    defer imported_roots.deinit();

    for (imported_modules.items) |mod_name| {
        // Extract root module name from dotted path (e.g., "test.support" -> "test")
        const root_mod_name = if (std.mem.indexOfScalar(u8, mod_name, '.')) |dot_idx|
            mod_name[0..dot_idx]
        else
            mod_name;

        // Skip if we already imported this root module
        if (imported_roots.contains(root_mod_name)) {
            continue;
        }

        // Skip modules that use registry imports (zig_runtime or c_library)
        // These get their import from the registry, not from @import("./mod.zig")
        if (self.import_registry.lookup(root_mod_name)) |info| {
            if (info.strategy == .zig_runtime or info.strategy == .c_library) {
                continue;
            }
        }

        // Skip if external module (no cache file)
        const import_path = try std.fmt.allocPrint(self.allocator, IMPORT_PREFIX ++ "{s}" ++ MODULE_EXT, .{root_mod_name});
        defer self.allocator.free(import_path);

        // Check if module was compiled to cache (uses comptime constants)
        const build_path = try std.fmt.allocPrint(self.allocator, BUILD_DIR ++ "/{s}" ++ MODULE_EXT, .{root_mod_name});
        defer self.allocator.free(build_path);

        std.fs.cwd().access(build_path, .{}) catch {
            // Module not in cache, skip it
            continue;
        };

        // Generate import statement (escape module name if it's a Zig keyword)
        const escaped_name = try zig_keywords.escapeIfKeyword(self.allocator, root_mod_name);
        const import_stmt = try std.fmt.allocPrint(self.allocator, "const {s} = @import(\"{s}\");\n", .{ escaped_name, import_path });
        try inlined_modules.append(self.allocator, import_stmt);

        // Track that we've imported this root module
        try imported_roots.put(root_mod_name, {});
    }

    // PHASE 2: Register all classes for inheritance support
    for (module.body) |stmt| {
        if (stmt == .class_def) {
            try self.class_registry.registerClass(stmt.class_def.name, stmt.class_def);
        }
    }

    // PHASE 2.1: Register async functions for comptime optimization analysis
    // Also collect ALL module-level function names for parameter shadowing detection
    // And collect module-level variable names for hoisted var type derivation
    for (module.body) |stmt| {
        if (stmt == .function_def) {
            const func = stmt.function_def;
            // Register function name to detect parameter shadowing
            try self.module_level_funcs.put(func.name, {});
            if (func.is_async) {
                const func_name_copy = try self.allocator.dupe(u8, func.name);
                try self.async_function_defs.put(func_name_copy, func);
            }
        } else if (stmt == .class_def) {
            // Register class names for hoisting type derivation
            // Class constructors like Rat(10, 15) should be safe to use in @TypeOf
            try self.module_level_funcs.put(stmt.class_def.name, {});
        } else if (stmt == .assign) {
            // Register module-level variable names
            for (stmt.assign.targets) |target| {
                if (target == .name) {
                    try self.module_level_vars.put(target.name.id, {});
                } else if (target == .tuple) {
                    for (target.tuple.elts) |elt| {
                        if (elt == .name) {
                            try self.module_level_vars.put(elt.name.id, {});
                        }
                    }
                }
            }
        }
    }

    // PHASE 2.5: Analyze mutations for list ArrayList vs fixed array decision
    const mutation_analyzer = @import("../../../analysis/native_types/mutation_analyzer.zig");
    var mutations = try mutation_analyzer.analyzeMutations(module, self.allocator);
    defer {
        for (mutations.values()) |*info| {
            @constCast(info).mutation_types.deinit(self.allocator);
        }
        mutations.deinit();
    }
    self.mutation_info = &mutations;

    // PHASE 3: Generate imports based on analysis (minimal for smaller WASM)
    // Check if any imported modules require runtime
    var needs_runtime_for_imports = false;
    for (imported_modules.items) |mod_name| {
        if (self.import_registry.lookup(mod_name)) |info| {
            if (info.strategy == .zig_runtime) {
                needs_runtime_for_imports = true;
                break;
            }
        }
    }

    // Always import std and runtime - DCE removes if unused
    try self.emit("const std = @import(\"std\");\n");
    try self.emit("const runtime = @import(\"./runtime.zig\");\n");
    if (analysis.needs_string_utils) {
        try self.emit("const string_utils = @import(\"string_utils.zig\");\n");
    }
    if (analysis.needs_hashmap_helper) {
        try self.emit("const hashmap_helper = @import(\"./utils/hashmap_helper.zig\");\n");
    }
    // Always import allocator_helper - needs_allocator defaults to true and most code uses it
    try self.emit("const allocator_helper = @import(\"./utils/allocator_helper.zig\");\n");

    // Emit @import statements for compiled user/stdlib modules (collected in PHASE 1.6)
    for (inlined_modules.items) |import_stmt| {
        try self.emit(import_stmt);
    }

    // PHASE 3.5: Generate C library imports (if any detected)
    if (self.import_ctx) |ctx| {
        const c_import_block = try ctx.generateCImportBlock(self.allocator);
        defer self.allocator.free(c_import_block);
        if (c_import_block.len > 0) {
            try self.emit(c_import_block);
        }
    }

    // PHASE 3.6: Generate c_interop import if C extension modules are used
    if (self.c_extension_modules.count() > 0) {
        try self.emit("const c_interop = @import(\"./c_interop/c_interop.zig\");\n");
    }

    // PHASE 3.7: Emit module assignments for registry modules
    // Note: Compiled user/stdlib modules already emitted via @import above
    for (imported_modules.items) |mod_name| {
        // Track this module name for call site handling
        const mod_copy = try self.allocator.dupe(u8, mod_name);
        try self.imported_modules.put(mod_copy, {});

        // NOTE: Do NOT skip module imports even if from-import has same symbol name.
        // The from-imports.zig already handles skipping the redundant from-import symbol.
        // We need the module import (e.g., const copy = std;) for other symbols like deepcopy.

        // Look up module in registry - only emit registry modules here
        if (self.import_registry.lookup(mod_name)) |info| {
            switch (info.strategy) {
                .zig_runtime, .c_library => {
                    // Use Zig import from registry
                    try self.emit("const ");
                    // Use writeEscapedDottedIdent for consistency with lambda path
                    try zig_keywords.writeEscapedDottedIdent(self.output.writer(self.allocator), mod_name);
                    try self.emit(" = ");
                    if (info.zig_import) |zig_import| {
                        try self.emit(zig_import);
                    } else {
                        try self.emit("struct {}; // TODO: ");
                        try self.emit(mod_name);
                        try self.emit(" not implemented");
                    }
                    try self.emit(";\n");
                },
                .compile_python, .unsupported => {
                    // These modules are handled via @import above (if compiled)
                    // or skipped (if unsupported)
                },
            }
        }
        // User/stdlib modules without registry entry are handled via @import above
    }

    // PHASE 3.7.1: Emit import aliases (import X as Y -> const Y = @"X";)
    for (self.import_aliases.keys()) |alias| {
        const module_name = self.import_aliases.get(alias).?;
        try self.emit("const ");
        try zig_keywords.writeEscapedIdent(self.output.writer(self.allocator), alias);
        try self.emit(" = ");
        try zig_keywords.writeEscapedDottedIdent(self.output.writer(self.allocator), module_name);
        try self.emit(";\n");
    }

    try self.emit("\n");

    // PHASE 3.6: Generate from-import symbol re-exports
    try from_imports_gen.generateFromImports(self);

    // PHASE 3.8: Pre-pass to detect optional import patterns (try: import X except: X = None)
    // This MUST happen before class/function generation so methods using X can be skipped
    for (module.body) |stmt| {
        if (stmt == .try_stmt) {
            // Check if this is an optional import pattern
            const try_node = stmt.try_stmt;
            if (try_node.body.len == 1 and try_node.body[0] == .import_stmt) {
                const mod_name = try_node.body[0].import_stmt.module;
                // Check if module is not in registry (unavailable)
                if (self.import_registry.lookup(mod_name) == null) {
                    // Check if except handler assigns to None
                    for (try_node.handlers) |handler| {
                        for (handler.body) |h_stmt| {
                            if (h_stmt == .assign and h_stmt.assign.targets.len > 0) {
                                if (h_stmt.assign.targets[0] == .name) {
                                    const var_name = h_stmt.assign.targets[0].name.id;
                                    if (std.mem.eql(u8, var_name, mod_name)) {
                                        // This is an optional import pattern - mark as skipped
                                        try self.markSkippedModule(mod_name);
                                    }
                                }
                            }
                        }
                    }
                }
            }
        }
    }

    // PHASE 4: Define __name__ constant (for if __name__ == "__main__" support)
    try self.emit("const __name__ = \"__main__\";\n");

    // PHASE 4.0.1: Define __file__ constant (Python magic variable for source file path)
    try self.emit("const __file__: []const u8 = \"");
    if (self.source_file_path) |path| {
        // Escape special characters in the path
        for (path) |c| {
            if (c == '\\') {
                try self.emit("\\\\");
            } else if (c == '"') {
                try self.emit("\\\"");
            } else {
                try self.output.append(self.allocator, c);
            }
        }
    } else {
        try self.emit("<unknown>");
    }
    try self.emit("\";\n\n");

    // PHASE 4.1: Emit source directory for runtime eval subprocess
    // This allows eval() to spawn metal0 subprocess with correct import paths
    if (source_file_dir) |dir| {
        try self.emit("// metal0 metadata for runtime eval subprocess\n");
        try self.emit("pub const __metal0_source_dir: []const u8 = \"");
        // Escape any special characters in the path
        for (dir) |c| {
            if (c == '\\') {
                try self.emit("\\\\");
            } else if (c == '"') {
                try self.emit("\\\"");
            } else {
                try self.output.append(self.allocator, c);
            }
        }
        try self.emit("\";\n\n");
    }

    // PHASE 4.5: Pre-generate closure wrapper types for functions that return closures
    // This allows the function signature to reference the closure type by name
    try genClosureWrapperTypes(self, module);

    // PHASE 4.6: Analyze functions that return test classes (factory pattern)
    // This enables unittest discovery for classes assigned via tuple unpacking
    try analyzeTestFactories(self, module);

    // PHASE 4.7: Pre-populate module_level_vars with global vars from analysis
    // This must happen BEFORE PHASE 5 (class definitions) so that method body generation
    // can detect and rename local variables that would shadow module-level globals
    for (analysis.global_vars) |var_name| {
        try self.module_level_vars.put(var_name, {});
    }

    // PHASE 5: Generate imports, class and function definitions (before main)
    // In module mode, wrap functions in pub struct
    if (self.mode == .module) {
        // Module mode: emit __global_allocator for f-strings and other allocating operations
        // This is needed because modules are compiled separately and don't have main() setup
        if (analysis.needs_allocator) {
            try self.emit("\n// Module-level allocator for f-strings and dynamic allocations\n");
            try self.emit("var __gpa = std.heap.GeneralPurposeAllocator(.{ .safety = true, .thread_safe = true }){};\n");
            try self.emit("var __global_allocator: std.mem.Allocator = __gpa.allocator();\n\n");
        }

        if (self.module_name) |mod_name| {
            try self.emit("pub const ");
            try zig_keywords.writeEscapedIdent(self.output.writer(self.allocator), mod_name);
            try self.emit(" = struct {\n");
            self.indent();
        }
    }

    for (module.body) |stmt| {
        if (stmt == .import_stmt) {
            try statements.genImport(self, stmt.import_stmt);
        } else if (stmt == .import_from) {
            try statements.genImportFrom(self, stmt.import_from);
        } else if (stmt == .class_def) {
            try statements.genClassDef(self, stmt.class_def);
            try self.emit("\n");
        } else if (stmt == .function_def) {
            if (self.mode == .module) {
                // In module mode, make functions pub
                try self.emitIndent();
                try self.emit("pub ");
            }
            try statements.genFunctionDef(self, stmt.function_def);
            try self.emit("\n");
        } else if (stmt == .assign) {
            if (self.mode == .module) {
                // In module mode, export constants as pub const
                // Handle tuple unpacking: x, y = 1, 2 -> need individual pub const for each
                if (stmt.assign.targets.len == 1 and (stmt.assign.targets[0] == .tuple or stmt.assign.targets[0] == .list)) {
                    // Tuple/list unpacking at module level
                    const target_elts = if (stmt.assign.targets[0] == .tuple)
                        stmt.assign.targets[0].tuple.elts
                    else
                        stmt.assign.targets[0].list.elts;

                    // Generate temporary for the tuple value
                    try self.emitIndent();
                    const tmp_name = try std.fmt.allocPrint(self.allocator, "__module_unpack_{d}", .{self.unpack_counter});
                    defer self.allocator.free(tmp_name);
                    self.unpack_counter += 1;

                    try self.emit("const ");
                    try self.emit(tmp_name);
                    try self.emit(" = ");
                    try expressions.genExpr(self, stmt.assign.value.*);
                    try self.emit(";\n");

                    // Generate pub const for each target (skip if already declared - reassignment)
                    for (target_elts, 0..) |target, j| {
                        if (target == .name) {
                            const var_name = target.name.id;
                            // Skip if this variable was already declared at module level
                            if (self.isDeclared(var_name)) {
                                // Reassignment at module level - skip (Zig doesn't allow redefinition)
                                continue;
                            }
                            try self.declareVar(var_name);
                            try self.emitIndent();
                            try self.emit("pub const ");
                            try zig_keywords.writeEscapedIdent(self.output.writer(self.allocator), var_name);
                            try self.output.writer(self.allocator).print(" = {s}.@\"{d}\";\n", .{ tmp_name, j });
                        }
                    }

                    // Check if this is a call to a test factory function
                    // If so, register the module-level variable names as test classes
                    if (stmt.assign.value.* == .call) {
                        const call_node = stmt.assign.value.call;
                        if (call_node.func.* == .name) {
                            const func_name = call_node.func.name.id;
                            if (self.test_factories.get(func_name)) |factory_info| {
                                // Register each target with its corresponding class info
                                for (target_elts, 0..) |target, j| {
                                    if (target == .name and j < factory_info.returned_classes.len) {
                                        const var_name = target.name.id;
                                        const orig_class_info = factory_info.returned_classes[j];

                                        // Create a new TestClassInfo with the module-level variable name
                                        try self.unittest_classes.append(self.allocator, core.TestClassInfo{
                                            .class_name = var_name,
                                            .test_methods = orig_class_info.test_methods,
                                            .has_setUp = orig_class_info.has_setUp,
                                            .has_tearDown = orig_class_info.has_tearDown,
                                            .has_setup_class = orig_class_info.has_setup_class,
                                            .has_teardown_class = orig_class_info.has_teardown_class,
                                        });
                                    }
                                }
                            }
                        }
                    }
                } else {
                    // Simple assignment: x = value
                    // Check if variable was already declared (reassignment)
                    var all_declared = true;
                    for (stmt.assign.targets) |target| {
                        if (target == .name) {
                            if (!self.isDeclared(target.name.id)) {
                                all_declared = false;
                                break;
                            }
                        }
                    }

                    // Skip reassignments at module level (Zig doesn't allow redefinition)
                    if (all_declared) {
                        continue;
                    }

                    try self.emitIndent();
                    try self.emit("pub const ");
                    // Generate target name
                    for (stmt.assign.targets, 0..) |target, i| {
                        if (target == .name) {
                            const var_name = target.name.id;
                            try self.declareVar(var_name);
                            try zig_keywords.writeEscapedIdent(self.output.writer(self.allocator), var_name);
                        }
                        if (i < stmt.assign.targets.len - 1) {
                            try self.emit(", ");
                        }
                    }
                    try self.emit(" = ");
                    try expressions.genExpr(self, stmt.assign.value.*);
                    try self.emit(";\n");
                }
            }
        }
    }

    // Close module struct (only if we opened one)
    if (self.mode == .module) {
        if (self.module_name != null) {
            self.dedent();
            try self.emit("};\n");
        }
        // Module mode doesn't generate main, just return
        return self.output.toOwnedSlice(self.allocator);
    }

    // PHASE 5.4: Generate intern table for string literals (after first pass collects them)
    // Note: The intern table is populated during code generation below
    // We'll insert it at the end if needed

    // PHASE 5.5: Generate module-level allocator (only if needed)
    if (analysis.needs_allocator) {
        try self.emit("\n// Module-level allocator for async functions and f-strings\n");
        try self.emit("// Debug/WASM: GPA instance (release uses c_allocator, no instance needed)\n");
        try self.emit("var __gpa = std.heap.GeneralPurposeAllocator(.{ .safety = true, .thread_safe = true }){};\n");
        try self.emit("var __global_allocator: std.mem.Allocator = undefined;\n");
        try self.emit("var __allocator_initialized: bool = false;\n");
        // sys.argv mutable global - can be assigned by Python code
        try self.emit("var __sys_argv: [][]const u8 = &[_][]const u8{};\n\n");
    }

    // PHASE 5.6: Generate module-level global variables (for 'global' keyword support)
    if (analysis.global_vars.len > 0) {
        try self.emit("\n// Module-level variables declared with 'global' keyword\n");
        for (analysis.global_vars) |var_name| {
            // Track in module_level_vars so local variables with same name get renamed
            // to avoid Zig's module-level shadowing error
            try self.module_level_vars.put(var_name, {});
            // Get type from type inferrer, default to i64 for integers
            const var_type = self.type_inferrer.var_types.get(var_name);

            // Callable types (function references like float.fromhex) are handled specially:
            // They're emitted at module level directly when encountered as module-level assignments
            // Skip pre-declaration here to avoid type mismatch
            if (var_type) |vt| {
                if (vt == .callable) {
                    // Track as callable global - will be emitted as const at module level in statements
                    try self.markGlobalVar(var_name);
                    try self.callable_global_vars.put(try self.allocator.dupe(u8, var_name), {});
                    continue;
                }
            }

            // Check if this variable is assigned from a closure factory (e.g., x = outer())
            // In that case, use the pre-generated closure type instead of inferred type
            var closure_type_name: ?[]const u8 = null;
            for (module.body) |stmt| {
                if (stmt == .assign) {
                    const assign = stmt.assign;
                    for (assign.targets) |target| {
                        if (target == .name and std.mem.eql(u8, target.name.id, var_name)) {
                            // Check if RHS is a call to a closure factory function
                            if (assign.value.* == .call) {
                                const call = assign.value.call;
                                if (call.func.* == .name) {
                                    const func_name = call.func.name.id;
                                    if (self.closure_factories.contains(func_name)) {
                                        // This is a closure factory call - look up the return type
                                        const sig = @import("../statements/functions/generators/signature.zig");
                                        // Find the nested function being returned and get its type
                                        for (module.body) |func_stmt| {
                                            if (func_stmt == .function_def and std.mem.eql(u8, func_stmt.function_def.name, func_name)) {
                                                if (sig.getReturnedNestedFuncName(func_stmt.function_def.body)) |nested_name| {
                                                    if (self.pending_closure_types.get(nested_name)) |type_name| {
                                                        closure_type_name = type_name;
                                                    }
                                                }
                                                break;
                                            }
                                        }
                                    }
                                }
                            }
                        }
                    }
                }
            }

            // Check if this variable is assigned from a generic class instantiation
            // Generic classes can't be pre-declared because we need the type argument
            // e.g., Box(42) -> Box(i64), but we don't know that until we see the call
            var is_generic_class_instance = false;
            for (module.body) |stmt| {
                if (stmt == .assign) {
                    const assign = stmt.assign;
                    for (assign.targets) |target| {
                        if (target == .name and std.mem.eql(u8, target.name.id, var_name)) {
                            // Check if RHS is a call to a generic class
                            if (assign.value.* == .call) {
                                const call = assign.value.call;
                                if (call.func.* == .name) {
                                    const class_name = call.func.name.id;
                                    if (self.generic_classes.contains(class_name)) {
                                        is_generic_class_instance = true;
                                    }
                                }
                            }
                        }
                    }
                }
            }

            // Skip pre-declaring generic class instances - they'll be declared inline
            if (is_generic_class_instance) {
                continue;
            }

            // Check if this variable is assigned from a list comprehension
            // List comprehensions need to be pre-declared at module level because they might be
            // used in class methods (which are generated as module-level struct methods)
            var is_listcomp_assignment = false;
            for (module.body) |stmt| {
                if (stmt == .assign) {
                    const assign = stmt.assign;
                    for (assign.targets) |target| {
                        if (target == .name and std.mem.eql(u8, target.name.id, var_name)) {
                            if (assign.value.* == .listcomp) {
                                is_listcomp_assignment = true;
                            }
                        }
                    }
                }
            }

            // Pre-declare list comprehensions as std.ArrayList(runtime.PyValue)
            // This handles the common case where element type is complex
            if (is_listcomp_assignment) {
                try self.emit("var ");
                try self.emit(var_name);
                try self.emit(": std.ArrayList(runtime.PyValue) = undefined;\n");
                try self.symbol_table.declare(var_name, .unknown, true);
                try self.markGlobalVar(var_name);
                continue;
            }

            // Check if this variable is assigned from import_module() or get_feature_macros()
            // These are compile-time values that need special handling
            var is_import_module_call = false;
            var is_feature_macros_call = false;
            for (module.body) |stmt| {
                if (stmt == .assign) {
                    const assign = stmt.assign;
                    for (assign.targets) |target| {
                        if (target == .name and std.mem.eql(u8, target.name.id, var_name)) {
                            if (assign.value.* == .call) {
                                const call = assign.value.call;
                                // Check for import_helper.import_module() or import_module()
                                if (call.func.* == .attribute) {
                                    const attr = call.func.attribute;
                                    if (std.mem.eql(u8, attr.attr, "import_module")) {
                                        is_import_module_call = true;
                                    }
                                } else if (call.func.* == .name) {
                                    const func_name = call.func.name.id;
                                    if (std.mem.eql(u8, func_name, "import_module")) {
                                        is_import_module_call = true;
                                    } else if (std.mem.eql(u8, func_name, "get_feature_macros")) {
                                        is_feature_macros_call = true;
                                    }
                                }
                            }
                        }
                    }
                }
            }

            // Skip pre-declaring import_module results - they're compile-time type refs
            if (is_import_module_call) {
                try self.import_module_vars.put(try self.allocator.dupe(u8, var_name), {});
                continue;
            }

            // Skip pre-declaring get_feature_macros results - they're compile-time struct refs
            if (is_feature_macros_call) {
                try self.import_module_vars.put(try self.allocator.dupe(u8, var_name), {});
                continue;
            }

            // Check if this variable is assigned from csv module functions (reader, writer, DictReader, DictWriter)
            // These return anonymous structs that can't be pre-declared with a type
            var is_csv_call = false;
            for (module.body) |stmt| {
                if (stmt == .assign) {
                    const assign = stmt.assign;
                    for (assign.targets) |target| {
                        if (target == .name and std.mem.eql(u8, target.name.id, var_name)) {
                            if (assign.value.* == .call) {
                                const call = assign.value.call;
                                if (call.func.* == .attribute) {
                                    const attr = call.func.attribute;
                                    if (attr.value.* == .name and std.mem.eql(u8, attr.value.name.id, "csv")) {
                                        // csv.reader, csv.writer, csv.DictReader, csv.DictWriter
                                        is_csv_call = true;
                                    }
                                }
                            }
                        }
                    }
                }
            }

            // Skip pre-declaring csv module results - they're anonymous iterator structs
            if (is_csv_call) {
                continue;
            }

            // Check if this variable is assigned from a known module constant (e.g., support.MAX_Py_ssize_t)
            // These are compile-time constants that should be emitted as const with correct type
            var is_module_constant = false;
            var module_const_type: ?[]const u8 = null;
            for (module.body) |stmt| {
                if (stmt == .assign) {
                    const assign = stmt.assign;
                    for (assign.targets) |target| {
                        if (target == .name and std.mem.eql(u8, target.name.id, var_name)) {
                            if (assign.value.* == .attribute) {
                                const attr = assign.value.attribute;
                                // support.MAX_Py_ssize_t, support._1G, etc.
                                if (attr.value.* == .name) {
                                    const module_name = attr.value.name.id;
                                    if (std.mem.eql(u8, module_name, "support")) {
                                        const attr_name = attr.attr;
                                        if (std.mem.eql(u8, attr_name, "MAX_Py_ssize_t") or
                                            std.mem.eql(u8, attr_name, "_1G") or
                                            std.mem.eql(u8, attr_name, "_2G") or
                                            std.mem.eql(u8, attr_name, "_4G"))
                                        {
                                            is_module_constant = true;
                                            module_const_type = "i64";
                                        } else if (std.mem.eql(u8, attr_name, "verbose") or
                                            std.mem.eql(u8, attr_name, "MS_WINDOWS") or
                                            std.mem.eql(u8, attr_name, "is_apple"))
                                        {
                                            is_module_constant = true;
                                            module_const_type = "bool";
                                        } else if (std.mem.eql(u8, attr_name, "SHORT_TIMEOUT")) {
                                            is_module_constant = true;
                                            module_const_type = "f64";
                                        }
                                    }
                                }
                            }
                        }
                    }
                }
            }

            // Emit module constants as const with correct type
            if (is_module_constant) {
                if (module_const_type) |const_type| {
                    try self.emit("const ");
                    try zig_keywords.writeEscapedIdent(self.output.writer(self.allocator), var_name);
                    try self.emit(": ");
                    try self.emit(const_type);
                    try self.emit(" = support.");
                    // Find the attribute name from the assignment
                    for (module.body) |stmt| {
                        if (stmt == .assign) {
                            const assign = stmt.assign;
                            for (assign.targets) |target| {
                                if (target == .name and std.mem.eql(u8, target.name.id, var_name)) {
                                    if (assign.value.* == .attribute) {
                                        try self.emit(assign.value.attribute.attr);
                                        break;
                                    }
                                }
                            }
                        }
                    }
                    try self.emit(";\n");
                    try self.symbol_table.declare(var_name, if (std.mem.eql(u8, const_type, "i64")) .{ .int = .bounded } else if (std.mem.eql(u8, const_type, "f64")) .float else if (std.mem.eql(u8, const_type, "bool")) .bool else .unknown, true);
                    try self.markGlobalVar(var_name);
                    continue;
                }
            }

            // Handle feature_macros related variables with correct types
            // These derive from FeatureMacros struct which returns strings, not PyObjects
            if (std.mem.eql(u8, var_name, "EXPECTED_FEATURE_MACROS")) {
                try self.emit("var EXPECTED_FEATURE_MACROS: hashmap_helper.StringHashMap(void) = undefined;\n");
                try self.symbol_table.declare(var_name, .unknown, true);
                try self.markGlobalVar(var_name);
                continue;
            }
            if (std.mem.eql(u8, var_name, "WINDOWS_FEATURE_MACROS")) {
                try self.emit("var WINDOWS_FEATURE_MACROS: hashmap_helper.StringHashMap([]const u8) = undefined;\n");
                try self.symbol_table.declare(var_name, .unknown, true);
                try self.markGlobalVar(var_name);
                continue;
            }

            // Skip variables that are already module-level functions
            // Python allows `genslices = rslices` to reassign function names,
            // but in Zig the function is already defined so we skip pre-declaration
            if (self.module_level_funcs.contains(var_name)) {
                continue;
            }

            // Also skip variables that are assigned a module-level function
            // e.g., `permutations = rpermutation` - can't pre-declare a function reference
            // Need to search recursively since assignment might be in if/for/while blocks
            const is_func_alias = isFunctionAliasRecursive(module.body, var_name, &self.module_level_funcs);
            if (is_func_alias) continue;

            // For dict types, check mutation analysis to determine correct key/value types
            // Type inference defaults empty dicts to StringHashMap, but mutation analysis
            // can tell us the actual key types used (e.g., d[i] = x means int keys)

            // Also check if this variable is assigned from another dict's .copy() method
            // In that case, inherit the source dict's corrected type
            var copy_source_dict: ?[]const u8 = null;
            for (module.body) |stmt| {
                if (stmt == .assign) {
                    const assign = stmt.assign;
                    for (assign.targets) |target| {
                        if (target == .name and std.mem.eql(u8, target.name.id, var_name)) {
                            // Check if RHS is source_dict.copy()
                            if (assign.value.* == .call) {
                                const call = assign.value.call;
                                if (call.func.* == .attribute) {
                                    const attr = call.func.attribute;
                                    if (std.mem.eql(u8, attr.attr, "copy") and attr.value.* == .name) {
                                        copy_source_dict = attr.value.name.id;
                                    }
                                }
                            }
                        }
                    }
                }
            }

            var needs_free = false;
            const zig_type = if (closure_type_name) |ctn| blk: {
                break :blk ctn;
            } else if (var_type) |vt| blk: {
                // Check if this is a dict that needs type override based on mutations
                if (@as(std.meta.Tag(@TypeOf(vt)), vt) == .dict) {
                    // If this dict is copied from another dict, inherit its corrected type
                    if (copy_source_dict) |source_name| {
                        if (self.mutation_info) |mut_info| {
                            const src_has_int_keys = mutation_analyzer.hasDictIntKeyMutation(mut_info.*, source_name);
                            const src_has_str_keys = mutation_analyzer.hasDictStrKeyMutation(mut_info.*, source_name);

                            if (src_has_int_keys and src_has_str_keys) {
                                break :blk "hashmap_helper.StringHashMap(runtime.PyValue)";
                            } else if (src_has_int_keys) {
                                // Inherit source dict's corrected type (AutoHashMap with int keys)
                                break :blk "std.AutoHashMap(i64, i64)";
                            }
                        }
                    }

                    if (self.mutation_info) |mut_info| {
                        const has_int_keys = mutation_analyzer.hasDictIntKeyMutation(mut_info.*, var_name);
                        const has_str_keys = mutation_analyzer.hasDictStrKeyMutation(mut_info.*, var_name);

                        if (has_int_keys and has_str_keys) {
                            // Mixed keys - use runtime.PyValue for heterogeneous access
                            break :blk "hashmap_helper.StringHashMap(runtime.PyValue)";
                        } else if (has_int_keys) {
                            // Int keys only - infer value type from dict
                            // Empty dicts default to unknown value type, which should be i64
                            // to match dict.zig codegen (d = {} with d[i] = x typically has int values)
                            const value_type = vt.dict.value.*;
                            const value_tag = @as(std.meta.Tag(@TypeOf(value_type)), value_type);
                            if (value_tag == .int) {
                                break :blk "std.AutoHashMap(i64, i64)";
                            } else if (value_tag == .float) {
                                break :blk "std.AutoHashMap(i64, f64)";
                            } else if (value_tag == .string) {
                                break :blk "std.AutoHashMap(i64, []const u8)";
                            } else if (value_tag == .unknown) {
                                // Empty dict with int keys defaults to i64 values
                                // (matches dict.zig:61 behavior)
                                break :blk "std.AutoHashMap(i64, i64)";
                            } else {
                                // Default to PyObject for complex values
                                break :blk "std.AutoHashMap(i64, *runtime.PyObject)";
                            }
                        }
                        // String keys (default) - fall through to nativeTypeToZigType
                    }
                }
                needs_free = true;
                break :blk try self.nativeTypeToZigType(vt);
            } else "i64";
            defer if (needs_free) self.allocator.free(zig_type);

            try self.emit("var ");
            try self.emit(var_name);
            try self.emit(": ");
            try self.emit(zig_type);
            try self.emit(" = undefined;\n");

            // Mark these as declared at module level (scope 0)
            try self.symbol_table.declare(var_name, var_type orelse .{ .int = .bounded }, true);

            // Also track them as global vars in codegen for assignment handling
            try self.markGlobalVar(var_name);
        }
        try self.emit("\n");
    }

    // PHASE 5.7: Generate callable global assignments at module level
    // These are function references like `fromHex = float.fromhex` that need to be
    // accessible from class methods (which are defined outside main())
    if (self.callable_global_vars.count() > 0) {
        try self.emit("\n// Module-level callable references\n");
        for (module.body) |stmt| {
            if (stmt == .assign) {
                const assign = stmt.assign;
                // Check if this is a callable global assignment
                for (assign.targets) |target| {
                    if (target == .name) {
                        const var_name = target.name.id;
                        if (self.callable_global_vars.contains(var_name)) {
                            // Emit at module level: const fromHex = runtime.floatFromHex;
                            try self.emit("const ");
                            try zig_keywords.writeEscapedIdent(self.output.writer(self.allocator), var_name);
                            try self.emit(" = ");
                            try self.genExpr(assign.value.*);
                            try self.emit(";\n");
                            // Mark as declared so we skip it in main()
                            try self.declareVar(var_name);
                        }
                    }
                }
            }
        }
        try self.emit("\n");
    }

    // PHASE 5.8: Generate import_module() const declarations
    // These are compile-time module type references like `ctypes_test = import_module("ctypes")`
    if (self.import_module_vars.count() > 0) {
        try self.emit("\n// Module references from import_module()\n");
        for (module.body) |stmt| {
            if (stmt == .assign) {
                const assign = stmt.assign;
                for (assign.targets) |target| {
                    if (target == .name) {
                        const var_name = target.name.id;
                        if (self.import_module_vars.contains(var_name)) {
                            // Emit: const ctypes_test = import_module("ctypes");
                            try self.emit("const ");
                            try zig_keywords.writeEscapedIdent(self.output.writer(self.allocator), var_name);
                            try self.emit(" = ");
                            try self.genExpr(assign.value.*);
                            try self.emit(";\n");
                            // Mark as declared so we skip in main()
                            try self.declareVar(var_name);
                        }
                    }
                }
            }
        }
        try self.emit("\n");
    }

    // PHASE 6: Generate main function (script mode only)
    // For WASM: Zig's std.start automatically exports _start if pub fn main exists
    try self.emit("pub fn main() ");
    // Main returns !void if allocator or runtime is used (runtime functions can fail)
    if (analysis.needs_allocator or analysis.needs_runtime) {
        try self.emit("!void {\n");
    } else {
        try self.emit("void {\n");
    }
    self.indent();

    // Setup allocator only if needed (skip for pure functions - smaller WASM)
    // Strategy: c_allocator in release (fast, OS cleanup), GPA in debug/WASM (safe)
    if (analysis.needs_allocator) {
        try self.emitIndent();
        try self.emit("const allocator = blk: {\n");
        try self.emitIndent();
        try self.emit("    if (comptime allocator_helper.useFastAllocator()) {\n");
        try self.emitIndent();
        try self.emit("        // Release mode: use c_allocator, OS reclaims at exit\n");
        try self.emitIndent();
        try self.emit("        break :blk std.heap.c_allocator;\n");
        try self.emitIndent();
        try self.emit("    } else {\n");
        try self.emitIndent();
        try self.emit("        // Debug/WASM: use GPA for leak detection\n");
        try self.emitIndent();
        try self.emit("        break :blk __gpa.allocator();\n");
        try self.emitIndent();
        try self.emit("    }\n");
        try self.emitIndent();
        try self.emit("};\n\n");

        // Initialize module-level allocator
        try self.emitIndent();
        try self.emit("__global_allocator = allocator;\n");
        try self.emitIndent();
        try self.emit("__allocator_initialized = true;\n");
        // Initialize sys.argv from OS args (skip in shared lib mode where argv is invalid)
        try self.emitIndent();
        try self.emit("__sys_argv = blk: {\n");
        try self.emitIndent();
        try self.emit("    // In shared library mode, std.os.argv may be invalid\n");
        try self.emitIndent();
        try self.emit("    if (comptime @import(\"builtin\").output_mode == .Exe) {\n");
        try self.emitIndent();
        try self.emit("        const os_args = std.os.argv;\n");
        try self.emitIndent();
        try self.emit("        var argv_list = std.ArrayList([]const u8){};\n");
        try self.emitIndent();
        try self.emit("        for (os_args) |arg| argv_list.append(allocator, std.mem.span(arg)) catch continue;\n");
        try self.emitIndent();
        try self.emit("        break :blk argv_list.items;\n");
        try self.emitIndent();
        try self.emit("    } else {\n");
        try self.emitIndent();
        try self.emit("        break :blk &[_][]const u8{};\n");
        try self.emitIndent();
        try self.emit("    }\n");
        try self.emitIndent();
        try self.emit("};\n");
        try self.emit("\n");

        // Initialize runtime modules that need allocator (from registry needs_init flag)
        for (self.imported_modules.keys()) |mod_name| {
            if (self.import_registry.lookup(mod_name)) |info| {
                if (info.needs_init) {
                    try self.emitIndent();
                    // Use writeEscapedDottedIdent for dotted module names like "test.support"
                    try zig_keywords.writeEscapedDottedIdent(self.output.writer(self.allocator), mod_name);
                    try self.emit(".init(__global_allocator);\n");
                }
            }
        }
    }

    // PHASE 7: Generate statements (skip class/function defs and imports - already handled)
    // This will populate self.lambda_functions
    // Clear hoisted_vars before generating main body (for proper try/except variable tracking)
    self.hoisted_vars.clearRetainingCapacity();

    // Analyze module-level mutations for scope-aware var/const determination
    // This populates func_local_mutations with aug_assign and multi-assign info
    try statements.analyzeModuleLevelMutations(self, module.body);

    for (module.body) |stmt| {
        if (stmt != .function_def and stmt != .class_def and stmt != .import_stmt and stmt != .import_from) {
            try self.generateStmt(stmt);
        }
    }

    // PHASE 7.5: Apply decorators (after statements so variables like 'app' are defined)
    if (self.decorated_functions.items.len > 0) {
        try self.emit("\n");
        try self.emitIndent();
        try self.emit("// Apply decorators\n");
        for (self.decorated_functions.items) |decorated_func| {
            for (decorated_func.decorators) |decorator| {
                try self.emitIndent();
                try self.emit("_ = ");
                try self.genExpr(decorator);
                // Use .call() method to apply decorator (works for Flask route decorators)
                try self.emit(".call(&");
                try self.emit(decorated_func.name);
                try self.emit(");\n");
            }
        }
    }

    // If user defined main(), call it (but not for async main - user calls via asyncio.run)
    if (analysis.has_user_main and !analysis.has_async_user_main) {
        try self.emitIndent();
        try self.emit("__user_main();\n");
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
        if (analysis.needs_hashmap_helper) {
            try self.emit("const hashmap_helper = @import(\"./utils/hashmap_helper.zig\");\n");
        }
        // Always import allocator_helper (matches the non-lambda path)
        try self.emit("const allocator_helper = @import(\"./utils/allocator_helper.zig\");\n");

        // Add module imports (Phase 3.7 copy for lambda path)
        // First, emit @import for compiled Python modules
        var lambda_imported_roots = hashmap_helper.StringHashMap(void).init(self.allocator);
        defer lambda_imported_roots.deinit();

        for (self.imported_modules.keys()) |mod_name| {
            // Extract root module name from dotted path
            const root_mod_name = if (std.mem.indexOfScalar(u8, mod_name, '.')) |dot_idx|
                mod_name[0..dot_idx]
            else
                mod_name;

            // Skip if already imported
            if (lambda_imported_roots.contains(root_mod_name)) continue;

            // NOTE: Do NOT skip module imports here. The from-imports.zig handles
            // skipping redundant from-import symbols. We need the module import
            // (e.g., const copy = std;) for other symbols like deepcopy.

            // First try to lookup the full module path (e.g., test.support.numbers)
            // This handles submodules that have their own registry entries
            if (self.import_registry.lookup(mod_name)) |info| {
                switch (info.strategy) {
                    .zig_runtime, .c_library => {
                        try self.emit("const ");
                        // Use writeEscapedDottedIdent for dotted module names like "test.support"
                        try zig_keywords.writeEscapedDottedIdent(self.output.writer(self.allocator), mod_name);
                        try self.emit(" = ");
                        if (info.zig_import) |zig_import| {
                            try self.emit(zig_import);
                        } else {
                            try self.emit("struct {}");
                        }
                        try self.emit(";\n");
                    },
                    else => {},
                }
            } else if (self.import_registry.lookup(root_mod_name)) |info| {
                // Fallback to root module for modules without submodule registry entries
                switch (info.strategy) {
                    .zig_runtime, .c_library => {
                        try self.emit("const ");
                        try zig_keywords.writeEscapedDottedIdent(self.output.writer(self.allocator), mod_name);
                        try self.emit(" = ");
                        if (info.zig_import) |zig_import| {
                            try self.emit(zig_import);
                        } else {
                            try self.emit("struct {}");
                        }
                        try self.emit(";\n");
                    },
                    else => {},
                }
            } else {
                // Compiled Python module - emit @import if cache file exists
                const build_path = try std.fmt.allocPrint(self.allocator, BUILD_DIR ++ "/{s}" ++ MODULE_EXT, .{root_mod_name});
                defer self.allocator.free(build_path);

                std.fs.cwd().access(build_path, .{}) catch continue;

                // Emit @import for compiled module
                const escaped_name = try zig_keywords.escapeIfKeyword(self.allocator, root_mod_name);
                defer if (escaped_name.ptr != root_mod_name.ptr) self.allocator.free(escaped_name);
                try self.emit("const ");
                try self.emit(escaped_name);
                try self.emit(" = @import(\"");
                try self.emit(IMPORT_PREFIX);
                try self.emit(root_mod_name);
                try self.emit(MODULE_EXT);
                try self.emit("\");\n");

                try lambda_imported_roots.put(root_mod_name, {});
            }
        }
        try self.emit("\n");

        // Add from-import symbol re-exports (Phase 3.6 copy for lambda path)
        try from_imports_gen.generateFromImports(self);

        // Add __name__ constant
        try self.emit("const __name__ = \"__main__\";\n");

        // Add __file__ constant
        try self.emit("const __file__: []const u8 = \"");
        if (self.source_file_path) |path| {
            for (path) |c| {
                if (c == '\\') {
                    try self.emit("\\\\");
                } else if (c == '"') {
                    try self.emit("\\\"");
                } else {
                    try self.output.append(self.allocator, c);
                }
            }
        } else {
            try self.emit("<unknown>");
        }
        try self.emit("\";\n\n");

        // Add lambda functions
        for (self.lambda_functions.items) |lambda_code| {
            try self.emit(lambda_code);
        }

        // Find where class/function definitions start (after imports, __name__, __file__)
        // Parse current_output to extract everything after imports and magic constants
        var lines = std.mem.splitScalar(u8, current_output, '\n');
        var skip_count: usize = 0;
        while (lines.next()) |line| {
            skip_count += 1;
            if (std.mem.indexOf(u8, line, "const __file__") != null) {
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
                try self.emit(line);
                try self.emit("\n");
            }
        }
    }

    return self.output.toOwnedSlice(self.allocator);
}

pub fn generateStmt(self: *NativeCodegen, node: ast.Node) CodegenError!void {
    // Skip generating statements after control flow termination (return/raise)
    // to avoid unreachable code errors in Zig
    if (self.control_flow_terminated) return;

    switch (node) {
        .assign => |assign| try statements.genAssign(self, assign),
        .ann_assign => |ann_assign| try statements.genAnnAssign(self, ann_assign),
        .aug_assign => |aug| try statements.genAugAssign(self, aug),
        .expr_stmt => |expr| try statements.genExprStmt(self, expr.value.*),
        .if_stmt => |if_stmt| try statements.genIf(self, if_stmt),
        .match_stmt => |match_stmt| try statements.genMatch(self, match_stmt),
        .while_stmt => |while_stmt| try statements.genWhile(self, while_stmt),
        .for_stmt => |for_stmt| try statements.genFor(self, for_stmt),
        .return_stmt => |ret| try statements.genReturn(self, ret),
        .assert_stmt => |assert_node| try statements.genAssert(self, assert_node),
        .try_stmt => |try_node| try statements.genTry(self, try_node),
        .raise_stmt => |raise_node| try statements.genRaise(self, raise_node),
        .class_def => |class| {
            // Skip if this class was hoisted to struct level (for return type visibility)
            if (self.hoisted_local_classes.contains(class.name)) return;
            try statements.genClassDef(self, class);
        },
        .function_def => |func| {
            // Only use nested function generation for truly nested functions
            if (func.is_nested) {
                try statements.genNestedFunctionDef(self, func);
            } else {
                // Top-level functions use regular generation
                try statements.genFunctionDef(self, func);
            }
        },
        .import_stmt => |import| try statements.genImport(self, import),
        .import_from => |import| try statements.genImportFrom(self, import),
        .pass => try statements.genPass(self),
        .ellipsis_literal => try statements.genPass(self), // Ellipsis as statement is equivalent to pass
        .break_stmt => try statements.genBreak(self),
        .continue_stmt => try statements.genContinue(self),
        .global_stmt => |global| try statements.genGlobal(self, global),
        .del_stmt => |del| try statements.genDel(self, del),
        .with_stmt => |with| try statements.genWith(self, with),
        .yield_stmt => |yield| {
            // For generator functions, append yield value to __gen_result ArrayList
            if (self.in_generator_function) {
                try self.emitIndent();
                // Use renamed variable if inside TryHelper (where __gen_result is passed as pointer)
                const gen_result_name = self.var_renames.get("__gen_result") orelse "__gen_result";
                try self.emit("try ");
                try self.emit(gen_result_name);
                try self.emit(".append(__global_allocator, runtime.PyValue.from(");
                if (yield.value) |val| {
                    try expressions.genExpr(self, val.*);
                } else {
                    try self.emit("undefined");
                }
                try self.emit("));\n");
            } else {
                try statements.genPass(self);
            }
        },
        else => {},
    }
}

// Expression generation delegated to expressions.zig
pub fn genExpr(self: *NativeCodegen, node: ast.Node) CodegenError!void {
    try expressions.genExpr(self, node);
}

/// Pre-generate closure wrapper types for functions that return closures.
/// This runs BEFORE function generation so the types exist when we need them.
/// For zero-capture closures, we generate the entire implementation at module level.
fn genClosureWrapperTypes(self: *NativeCodegen, module: ast.Node.Module) !void {
    const sig = @import("../statements/functions/generators/signature.zig");
    const var_tracking = @import("../statements/functions/nested/var_tracking.zig");
    const zero_capture = @import("../statements/functions/nested/zero_capture.zig");

    for (module.body) |stmt| {
        if (stmt == .function_def) {
            const func = stmt.function_def;

            // Check if this function returns a nested function (closure)
            if (sig.getReturnedNestedFuncName(func.body)) |nested_func_name| {
                // Find the nested function definition to get its signature
                var nested_func: ?ast.Node.FunctionDef = null;
                for (func.body) |body_stmt| {
                    if (body_stmt == .function_def) {
                        if (std.mem.eql(u8, body_stmt.function_def.name, nested_func_name)) {
                            nested_func = body_stmt.function_def;
                            break;
                        }
                    }
                }

                if (nested_func) |nf| {
                    // Check if this is a zero-capture closure
                    // We can only pre-generate zero-capture closures at module level
                    // Pass outer function's params so we can detect captured variables
                    const captured = var_tracking.findCapturedVarsWithOuter(
                        self,
                        nf,
                        func.args,
                    ) catch continue;
                    defer self.allocator.free(captured);

                    if (captured.len == 0) {
                        // Generate a unique type name based on the outer function
                        const type_name = try std.fmt.allocPrint(
                            self.allocator,
                            "{s}__struct_{d}",
                            .{ func.name, self.lambda_counter },
                        );

                        // Store the type name for later reference in signature.zig
                        // Key is the nested function name, value is the pre-generated type name
                        const nested_name_copy = try self.allocator.dupe(u8, nested_func_name);
                        try self.pending_closure_types.put(nested_name_copy, type_name);

                        // Also mark this function as a closure factory (caller in outer function)
                        const func_name_copy = try self.allocator.dupe(u8, func.name);
                        try self.closure_factories.put(func_name_copy, {});

                        // Generate the entire zero-capture closure at module level
                        // This includes impl struct + wrapper struct
                        try zero_capture.genModuleLevelZeroCaptureClosure(self, nf, type_name);

                        self.lambda_counter += 1;
                    }
                }
            }
        }
    }
}

/// Analyze functions that return test classes (factory pattern for unittest)
/// This populates test_factories map with factory function name -> TestClassInfo[]
fn analyzeTestFactories(self: *NativeCodegen, module: ast.Node.Module) !void {
    const generators = @import("../statements/functions/generators.zig");
    const function_traits = @import("function_traits");

    for (module.body) |stmt| {
        if (stmt != .function_def) continue;
        const func = stmt.function_def;

        // Find test classes defined inside this function
        var test_classes = std.ArrayList(core.TestClassInfo){};
        errdefer {
            for (test_classes.items) |info| self.allocator.free(info.test_methods);
            test_classes.deinit(self.allocator);
        }

        // Track class names and their info
        var class_info_map = hashmap_helper.StringHashMap(core.TestClassInfo).init(self.allocator);
        defer class_info_map.deinit();

        for (func.body) |body_stmt| {
            if (body_stmt != .class_def) continue;
            const class = body_stmt.class_def;

            // Check if class inherits from unittest.TestCase
            if (class.bases.len == 0) continue;
            if (!std.mem.eql(u8, class.bases[0], "unittest.TestCase")) continue;

            // Collect test methods
            var test_methods = std.ArrayList(core.TestMethodInfo){};
            var has_setUp = false;
            var has_tearDown = false;
            var has_setup_class = false;
            var has_teardown_class = false;

            for (class.body) |class_stmt| {
                if (class_stmt != .function_def) continue;
                const method = class_stmt.function_def;
                const method_name = method.name;

                if (std.mem.startsWith(u8, method_name, "test_") or std.mem.startsWith(u8, method_name, "test")) {
                    const method_needs_allocator = function_traits.analyzeNeedsAllocator(method, class.name);
                    const skip_reason: ?[]const u8 = if (generators.hasCPythonOnlyDecorator(method.decorators))
                        "CPython implementation test"
                    else if (generators.hasSkipUnlessCPythonModule(method.decorators))
                        "Requires CPython-only module"
                    else
                        null;

                    try test_methods.append(self.allocator, core.TestMethodInfo{
                        .name = method_name,
                        .skip_reason = skip_reason,
                        .needs_allocator = method_needs_allocator,
                        .returns_error = method_needs_allocator, // Methods needing allocator typically have fallible ops
                        .is_skipped = skip_reason != null,
                    });
                } else if (std.mem.eql(u8, method_name, "setUp")) {
                    has_setUp = true;
                } else if (std.mem.eql(u8, method_name, "tearDown")) {
                    has_tearDown = true;
                } else if (std.mem.eql(u8, method_name, "setUpClass")) {
                    has_setup_class = true;
                } else if (std.mem.eql(u8, method_name, "tearDownClass")) {
                    has_teardown_class = true;
                }
            }

            if (test_methods.items.len > 0) {
                try class_info_map.put(class.name, core.TestClassInfo{
                    .class_name = class.name,
                    .test_methods = try test_methods.toOwnedSlice(self.allocator),
                    .has_setUp = has_setUp,
                    .has_tearDown = has_tearDown,
                    .has_setup_class = has_setup_class,
                    .has_teardown_class = has_teardown_class,
                });
            } else {
                test_methods.deinit(self.allocator);
            }
        }

        // If no test classes found, skip this function
        if (class_info_map.count() == 0) continue;

        // Find the return statement to get the order of returned classes
        var returned_class_names = std.ArrayList([]const u8){};
        defer returned_class_names.deinit(self.allocator);

        for (func.body) |body_stmt| {
            if (body_stmt != .return_stmt) continue;
            const ret_val = body_stmt.return_stmt.value orelse continue;

            // Check if return value is a tuple of class names
            if (ret_val.* == .tuple) {
                for (ret_val.tuple.elts) |elt| {
                    if (elt == .name) {
                        try returned_class_names.append(self.allocator, elt.name.id);
                    }
                }
            }
        }

        // Build ordered list of test class info based on return order
        for (returned_class_names.items) |class_name| {
            if (class_info_map.get(class_name)) |info| {
                try test_classes.append(self.allocator, info);
                _ = class_info_map.swapRemove(class_name);
            }
        }

        if (test_classes.items.len > 0) {
            const func_name_copy = try self.allocator.dupe(u8, func.name);
            try self.test_factories.put(func_name_copy, core.TestFactoryInfo{
                .returned_classes = try test_classes.toOwnedSlice(self.allocator),
            });
        }
    }
}

/// Check if a variable is assigned a module-level function anywhere in the body
/// Searches recursively through if/for/while/try blocks
fn isFunctionAliasRecursive(body: []const ast.Node, var_name: []const u8, module_level_funcs: *const hashmap_helper.StringHashMap(void)) bool {
    for (body) |stmt| {
        switch (stmt) {
            .assign => {
                const assign = stmt.assign;
                for (assign.targets) |target| {
                    if (target == .name and std.mem.eql(u8, target.name.id, var_name)) {
                        if (assign.value.* == .name) {
                            if (module_level_funcs.contains(assign.value.name.id)) {
                                return true;
                            }
                        }
                    }
                }
            },
            .if_stmt => {
                const if_s = stmt.if_stmt;
                if (isFunctionAliasRecursive(if_s.body, var_name, module_level_funcs)) return true;
                if (isFunctionAliasRecursive(if_s.else_body, var_name, module_level_funcs)) return true;
            },
            .for_stmt => {
                if (isFunctionAliasRecursive(stmt.for_stmt.body, var_name, module_level_funcs)) return true;
            },
            .while_stmt => {
                if (isFunctionAliasRecursive(stmt.while_stmt.body, var_name, module_level_funcs)) return true;
            },
            .try_stmt => {
                const try_s = stmt.try_stmt;
                if (isFunctionAliasRecursive(try_s.body, var_name, module_level_funcs)) return true;
                for (try_s.handlers) |handler| {
                    if (isFunctionAliasRecursive(handler.body, var_name, module_level_funcs)) return true;
                }
                if (isFunctionAliasRecursive(try_s.finalbody, var_name, module_level_funcs)) return true;
            },
            else => {},
        }
    }
    return false;
}
