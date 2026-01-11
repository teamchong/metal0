/// Main code generation functions
const std = @import("std");

/// Debug flag for code generation logging
const DEBUG_CODEGEN = false;

const ast = @import("analysis.ast");
const core = @import("core.zig");
const NativeCodegen = core.NativeCodegen;
const CodegenError = core.CodegenError;
const imports = @import("imports.zig");
const from_imports_gen = @import("from_imports.zig");
const analyzer = @import("../analyzer.zig");
const statements = @import("../statements.zig");
const expressions = @import("../expressions.zig");
const import_resolver = @import("../../../import_resolver.zig");
const zig_keywords = @import("utils.zig_keywords");
const hashmap_helper = @import("utils.hashmap_helper");
const build_dirs = @import("../../../build_dirs.zig");
const method_categories = @import("../dispatch/method_categories.zig");
const FnvVoidMap = hashmap_helper.StringHashMap(void);

// MIGRATED TO ZIGBUILDER

// Import trait modules for type checking
const type_traits = @import("../../../analysis/traits/type_traits.zig");
const string_traits = @import("../../../analysis/traits/string_traits.zig");
const container_traits = @import("../../../analysis/traits/container_traits.zig");
const module_functions = @import("../dispatch/module_functions.zig");

// Multi-pass build system
const ir = @import("../../ir.zig");
const ir_gen = @import("../../passes/ir_gen.zig");
const pass_analysis = @import("../../passes/analysis.zig");
const variable_resolution = @import("../../passes/variable_resolution.zig");
const emit_pass = @import("../../passes/emit.zig");

// Comptime constants for code generation (zero runtime cost)
const BUILD_DIR = build_dirs.CACHE;
const MODULE_EXT = ".zig";
const IMPORT_PREFIX = "./";
const MAIN_NAME = "__main__";

// Import paths using module names (defined via -M flags in compiler.zig)
// No file paths needed - Zig resolves modules via -M flags at compile time
const RUNTIME_IMPORT = "runtime";
const RUNTIME_PREFIX = "runtime.";  // For submodules like runtime.string_utils
const UTILS_PREFIX = "utils.";      // For utils.hashmap_helper, utils.allocator_helper

// Package modules manifest for batch compilation
// Format: one line per package, "module_name:absolute_path"
const PACKAGE_MODULES_MANIFEST = BUILD_DIR ++ "/package_modules.txt";

/// Write a package module entry to the manifest file (append-only, thread-safe)
/// This is called during codegen for each imported module
pub fn writePackageModuleEntry(module_name: []const u8, abs_path: []const u8) !void {
    // Buffer for formatted output
    var write_buf: [4096]u8 = undefined;

    // Open or create manifest file for appending
    const file = std.fs.cwd().openFile(PACKAGE_MODULES_MANIFEST, .{ .mode = .read_write }) catch |err| {
        if (err == error.FileNotFound) {
            // Create new file
            const new_file = try std.fs.cwd().createFile(PACKAGE_MODULES_MANIFEST, .{});
            defer new_file.close();
            const line = std.fmt.bufPrint(&write_buf, "{s}:{s}\n", .{ module_name, abs_path }) catch return;
            try new_file.writeAll(line);
            return;
        }
        return err;
    };
    defer file.close();

    // Check if this module is already in the manifest (avoid duplicates)
    var buf: [64 * 1024]u8 = undefined;
    const content_len = file.readAll(&buf) catch 0;
    const content = buf[0..content_len];

    // Simple check: if "module_name:" exists in content, skip
    const prefix = std.fmt.bufPrint(&write_buf, "{s}:", .{module_name}) catch return;
    if (std.mem.indexOf(u8, content, prefix) != null) {
        return; // Already exists
    }

    // Seek to end and append
    file.seekFromEnd(0) catch {};
    const line = std.fmt.bufPrint(&write_buf, "{s}:{s}\n", .{ module_name, abs_path }) catch return;
    file.writeAll(line) catch {};
}

/// Generate native Zig code for module
pub fn generate(self: *NativeCodegen, module: ast.Node.Module) ![]const u8 {
    if (DEBUG_CODEGEN) std.debug.print("generate(): Starting...\n", .{});

    // PHASE 1: Analyze module to determine requirements
    if (DEBUG_CODEGEN) std.debug.print("generate(): Phase 1 - Analyzing module...\n", .{});
    const analysis = try analyzer.analyzeModule(module, self.allocator);
    defer if (analysis.global_vars.len > 0) self.allocator.free(analysis.global_vars);
    if (DEBUG_CODEGEN) std.debug.print("generate(): Phase 1 complete.\n", .{});

    // PHASE 1.1: Build call graph for function trait analysis (error handling, allocator needs, etc.)
    if (DEBUG_CODEGEN) std.debug.print("generate(): Phase 1.1 - Building call graph...\n", .{});
    try self.buildCallGraph(module);
    if (DEBUG_CODEGEN) std.debug.print("generate(): Phase 1.1 complete.\n", .{});

    // PHASE 1.2: Multi-pass analysis
    // Generate IR and run analysis for const/var inference, hoisting, captures, declaration order
    if (DEBUG_CODEGEN) std.debug.print("generate(): Phase 1.2 - Multi-pass analysis...\n", .{});
    const ir_stmts = ir_gen.generateIR(module, self.allocator) catch |err| blk: {
        if (DEBUG_CODEGEN) std.debug.print("generate(): IR generation failed: {any}, using fallbacks\n", .{err});
        break :blk null;
    };
    if (ir_stmts) |stmts| {
        const analysis_result = pass_analysis.analyze(stmts, self.allocator) catch |err| blk: {
            if (DEBUG_CODEGEN) std.debug.print("generate(): Pass analysis failed: {any}, using fallbacks\n", .{err});
            break :blk null;
        };
        if (analysis_result) |result| {
            // Store pointer to analysis result - heap allocate to keep it alive
            const result_ptr = try self.allocator.create(pass_analysis.AnalysisResult);
            result_ptr.* = result;
            self.pass_analysis_result = result_ptr;
            if (DEBUG_CODEGEN) std.debug.print("generate(): Phase 1.2 complete - multi-pass analysis enabled\n", .{});
        }
    }
    if (self.pass_analysis_result == null) {
        if (DEBUG_CODEGEN) std.debug.print("generate(): Phase 1.2 - Using fallback defaults\n", .{});
    }

    // PHASE 2.5: Variable Resolution Pass
    // Pre-compute unique Zig names for ALL variables before codegen
    // This eliminates runtime state accumulation (var_renames, hoisted_vars, etc.)
    if (DEBUG_CODEGEN) std.debug.print("generate(): Phase 2.5 - Variable resolution...\n", .{});
    const var_resolution = variable_resolution.resolveVariables(module.body, self.allocator) catch |err| blk: {
        if (DEBUG_CODEGEN) std.debug.print("generate(): Variable resolution failed: {any}, using fallbacks\n", .{err});
        break :blk null;
    };
    if (var_resolution) |resolution| {
        // Store pointer to resolution result - heap allocate to keep it alive
        const resolution_ptr = try self.allocator.create(variable_resolution.VariableResolution);
        resolution_ptr.* = resolution;
        self.var_resolution = resolution_ptr;
        if (DEBUG_CODEGEN) std.debug.print("generate(): Phase 2.5 complete - variable resolution enabled\n", .{});
    } else {
        if (DEBUG_CODEGEN) std.debug.print("generate(): Phase 2.5 - Using fallback variable names\n", .{});
    }

    // Pre-register global variables so they can be detected during method generation
    // This prevents local variables with the same name from shadowing module-level vars
    if (DEBUG_CODEGEN) std.debug.print("generate(): Registering {d} global vars...\n", .{analysis.global_vars.len});
    for (analysis.global_vars) |var_name| {
        try self.markGlobalVar(var_name);
    }
    if (DEBUG_CODEGEN) std.debug.print("generate(): Global vars registered.\n", .{});

    // PHASE 1.5: Get source file directory for import resolution
    if (DEBUG_CODEGEN) std.debug.print("generate(): Phase 1.5 - Getting source file directory...\n", .{});
    const source_file_dir = if (self.source_file_path) |path|
        try import_resolver.getFileDirectory(path, self.allocator)
    else
        null;
    defer if (source_file_dir) |dir| self.allocator.free(dir);
    if (DEBUG_CODEGEN) std.debug.print("generate(): Phase 1.5 complete.\n", .{});

    // PHASE 1.6: Collect imports and compile imported modules as inlined structs
    if (DEBUG_CODEGEN) std.debug.print("generate(): Phase 1.6 - Collecting imports...\n", .{});
    var imported_modules = try imports.collectImports(self, module, source_file_dir);
    defer imported_modules.deinit(self.allocator);
    if (DEBUG_CODEGEN) std.debug.print("generate(): Phase 1.6 complete - {d} imports collected.\n", .{imported_modules.items.len});

    // PHASE 1.7: Pre-scan star imports to populate module_level_from_imports BEFORE function generation
    // This ensures wouldParamShadow() correctly detects shadowing even when star import is at end of file
    if (DEBUG_CODEGEN) std.debug.print("generate(): Phase 1.7 - Pre-scanning star imports...\n", .{});
    try self.prescanStarImports(module.body, source_file_dir);
    if (DEBUG_CODEGEN) std.debug.print("generate(): Phase 1.7 complete.\n", .{});

    // Store compiled module structs for later emission
    if (DEBUG_CODEGEN) std.debug.print("generate(): Initializing inlined_modules list...\n", .{});
    var inlined_modules = std.ArrayList([]const u8){};
    defer {
        for (inlined_modules.items) |code| self.allocator.free(code);
        inlined_modules.deinit(self.allocator);
    }

    // Generate @import() statements for compiled modules
    // Track which root modules have been imported to avoid duplicates
    if (DEBUG_CODEGEN) std.debug.print("generate(): Initializing imported_roots map...\n", .{});
    var imported_roots = hashmap_helper.StringHashMap(void).init(self.allocator);
    defer imported_roots.deinit();

    if (DEBUG_CODEGEN) std.debug.print("generate(): Processing {d} imported modules...\n", .{imported_modules.items.len});
    for (imported_modules.items, 0..) |mod_name, i| {
        if (DEBUG_CODEGEN) std.debug.print("generate():   Processing import {d}/{d}: {s}\n", .{i+1, imported_modules.items.len, mod_name});

        // Skip empty module names (from bare "." relative imports)
        if (mod_name.len == 0) continue;

        // Extract root module name from dotted path (e.g., "test.support" -> "test")
        const root_mod_name = if (std.mem.indexOfScalar(u8, mod_name, '.')) |dot_idx|
            mod_name[0..dot_idx]
        else
            mod_name;

        // Skip empty root module names (from relative imports like ".something")
        if (root_mod_name.len == 0) continue;

        // Skip if we already imported this root module
        if (imported_roots.contains(root_mod_name)) {
            continue;
        }

        // Skip self-imports (module importing itself)
        if (self.module_name) |current_module| {
            // For numpy/__init__.py, module_name is "numpy"
            // Skip if importing the same module
            if (std.mem.eql(u8, root_mod_name, current_module)) {
                continue;
            }
            // Also check if it's a submodule of current module (e.g., numpy._core from numpy)
            if (std.mem.startsWith(u8, root_mod_name, current_module) and
                root_mod_name.len > current_module.len and
                root_mod_name[current_module.len] == '.')
            {
                // This is a relative import within the same package, skip
                continue;
            }
        }

        // Skip modules that use registry imports (zig_runtime or c_library)
        // These get their import from the registry, not from @import("./mod.zig")
        if (self.import_registry.lookup(root_mod_name)) |info| {
            if (info.strategy == .zig_runtime or info.strategy == .c_library) {
                continue;
            }
        }

        // Check if module was compiled - try simple path first, then resolved path
        // Simple path: .metal0/gen/{module_name}.zig (local user modules)
        // Resolved path: .metal0/gen/{source_path}/{module_name}.zig (site-packages)
        var import_path_owned: ?[]const u8 = null;
        defer if (import_path_owned) |p| self.allocator.free(p);

        // Try simple path first: .metal0/gen/{module_name}.zig
        const simple_build_path = try std.fmt.allocPrint(self.allocator, BUILD_DIR ++ "/" ++ build_dirs.SRC_SUBDIR ++ "/{s}" ++ MODULE_EXT, .{root_mod_name});
        defer self.allocator.free(simple_build_path);

        if (std.fs.cwd().access(simple_build_path, .{})) |_| {
            import_path_owned = try std.fmt.allocPrint(self.allocator, IMPORT_PREFIX ++ build_dirs.SRC_SUBDIR ++ "/{s}" ++ MODULE_EXT, .{root_mod_name});
        } else |_| {
            // Try resolved path: resolve module to source, then get compiled path
            const source_path = import_resolver.resolveImport(root_mod_name, source_file_dir, self.allocator) catch null;
            if (source_path) |sp| {
                defer self.allocator.free(sp);
                const zig_path = build_dirs.projectZigPath(self.allocator, ".", sp) catch continue;
                defer self.allocator.free(zig_path);
                std.fs.cwd().access(zig_path, .{}) catch continue;

                // ALL project modules use module names (not absolute paths)
                // Zig rejects @import() with absolute paths outside module search path
                // Register ALL modules in the manifest for the compiler to add -M flags
                const abs_path = std.fs.cwd().realpathAlloc(self.allocator, zig_path) catch continue;
                defer self.allocator.free(abs_path);

                // Use module name in @import()
                import_path_owned = try self.allocator.dupe(u8, root_mod_name);

                // Write module:path mapping to package_modules.txt for compilation
                try writePackageModuleEntry(root_mod_name, abs_path);
            } else {
                // Module not found
                continue;
            }
        }

        const import_path = import_path_owned orelse continue;

        // Generate import statement (escape module name if it's a Zig keyword)
        // Add comptime reference to suppress unused variable warnings for modules
        // that may be used only via runtime.eval or dynamic imports
        const escaped_name = try zig_keywords.escapeIfKeyword(self.allocator, root_mod_name);
        const import_stmt = try std.fmt.allocPrint(self.allocator, "const {s} = @import(\"{s}\");\ncomptime {{ _ = &{s}; }}\n", .{ escaped_name, import_path, escaped_name });
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
                const func_name_copy = try self.arena.allocator().dupe(u8, func.name);
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

    // PHASE 2.2: Collect conditional assignments that need hoisting
    // Variables assigned in BOTH if and else branches at module level need pre-declaration
    var conditional_assignments = try collectConditionalAssignments(module.body, self.type_inferrer, self.allocator);
    defer {
        for (conditional_assignments.items) |cond_var| {
            self.allocator.free(cond_var.name);
        }
        conditional_assignments.deinit(self.allocator);
    }

    // Register conditional variables in module_level_vars
    for (conditional_assignments.items) |cond_var| {
        try self.module_level_vars.put(cond_var.name, {});
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
    try self.emit("const runtime = @import(\"runtime\");\n");
    if (analysis.needs_string_utils) {
        // string_utils is a submodule of runtime, access via runtime.string_utils
        try self.emit("const string_utils = runtime.string_utils;\n");
    }
    if (analysis.needs_hashmap_helper) {
        // Use runtime.hashmap_helper - hashmap_helper is re-exported from runtime module
        try self.emit("const hashmap_helper = runtime.hashmap_helper;\n");
    }
    // Always import allocator_helper - needs_allocator defaults to true and most code uses it
    // Use runtime.allocator_helper - allocator_helper is re-exported from runtime module
    try self.emit("const allocator_helper = runtime.allocator_helper;\n");

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

    // PHASE 3.6: Generate c_interop import
    // Always emit c_interop import - DCE will remove if unused
    // This is needed because C extension method calls are detected during codegen (after imports)
    try self.emit("const c_interop = @import(\"c_interop\");\n");
    if (self.c_extension_modules.count() > 0) {

        // PHASE 3.6.1: Generate C extension module imports
        // import numpy as np -> var np: ?*c_interop.PyObject = null;
        // The actual import happens at runtime in main() before any code runs
        // Track which modules we've already emitted (avoid duplicates from alias + module_name)
        var emitted_c_ext = hashmap_helper.StringHashMap(void).init(self.allocator);
        defer emitted_c_ext.deinit();

        for (self.c_extension_modules.keys()) |key| {
            const module_name = self.c_extension_modules.get(key).?;
            // Skip module_name -> module_name entries if we have an alias
            if (std.mem.eql(u8, key, module_name)) {
                // Check if there's an alias for this module
                var has_alias = false;
                for (self.c_extension_modules.keys()) |k| {
                    const v = self.c_extension_modules.get(k).?;
                    if (std.mem.eql(u8, v, module_name) and !std.mem.eql(u8, k, module_name)) {
                        has_alias = true;
                        break;
                    }
                }
                if (has_alias) continue; // Skip - we'll use the alias instead
            }

            // Avoid duplicate emissions
            if (emitted_c_ext.contains(key)) continue;
            try emitted_c_ext.put(key, {});

            // Skip dotted module names ONLY if there's no alias
            // e.g., "import numpy.testing" (key=numpy.testing, module_name=numpy.testing) -> skip
            // But "import numpy.exceptions as ex" (key=ex, module_name=numpy.exceptions) -> declare var ex
            // Submodules without alias are accessed via fromImport()
            if (std.mem.indexOfScalar(u8, module_name, '.') != null and std.mem.eql(u8, key, module_name)) continue;

            // Generate: [pub] var np: ?*c_interop.PyObject = null;
            // The import will be done at runtime start via c_interop.importModule()
            // For dotted names like numpy.exceptions, we need to escape: var @"numpy.exceptions": ...
            // Use pub for module mode so symbols are accessible from importing modules
            if (self.mode == .module) try self.emit("pub ");
            try self.emit("var ");
            try self.emitIdent(key);
            try self.emit(": ?*c_interop.PyObject = null;\n");
        }

        // PHASE 3.6.2: Emit root module variables for submodule imports
        // When "import numpy._core.include" is used, emit "var numpy" even if "numpy as np" exists
        // This allows direct access to the root module name in attribute chains like numpy._core.lib.pkgconfig
        for (self.c_extension_root_modules.keys()) |root_module| {
            // Skip if already emitted (might overlap with regular c_extension_modules)
            if (emitted_c_ext.contains(root_module)) continue;

            // Skip if this is the current module (self-reference)
            if (self.module_name) |current_module| {
                if (std.mem.eql(u8, root_module, current_module)) continue;
            }

            try emitted_c_ext.put(root_module, {});

            // Use pub for module mode so symbols are accessible from importing modules
            if (self.mode == .module) try self.emit("pub ");
            try self.emit("var ");
            try self.emitIdent(root_module);
            try self.emit(": ?*c_interop.PyObject = null;\n");
        }
    }

    // PHASE 3.7: Emit module assignments for registry modules
    // Note: Compiled user/stdlib modules already emitted via @import above
    // Track emitted module consts to avoid duplicates (e.g., import _pyio appearing twice)
    var emitted_module_consts = hashmap_helper.StringHashMap(void).init(self.allocator);
    defer emitted_module_consts.deinit();

    for (imported_modules.items) |mod_name| {
        // Skip if we've already emitted this module const
        if (emitted_module_consts.contains(mod_name)) {
            continue;
        }

        // Special handling for 'builtins' module
        // builtins.func() calls are dispatched to builtin handlers, but code may access builtins.__dict__ etc.
        if (std.mem.eql(u8, mod_name, "builtins")) {
            // Generate: const builtins = runtime.builtins;
            try self.emit("const builtins = runtime.builtins;\n");
            try emitted_module_consts.put(mod_name, {});
            continue;
        }

        // Special handling for codegen-only modules (e.g., logic_table)
        // These modules have dispatch handlers but no runtime library - dispatch.zig handles them
        // IMPORTANT: Check if module also has a runtime library (in registry with zig_runtime/c_library)
        // Modules like 'unittest' have BOTH dispatch handlers AND a runtime library
        if (module_functions.hasCodegenDispatch(mod_name)) {
            // Check if this module also needs a runtime import
            const needs_runtime_import = if (self.import_registry.lookup(mod_name)) |info|
                (info.strategy == .zig_runtime or info.strategy == .c_library)
            else
                false;

            if (!needs_runtime_import) {
                // Pure codegen module - emit empty placeholder for import aliases to reference
                // e.g., `import bdb as _bdb` needs `const bdb = struct {};` for `const _bdb = bdb;`
                try self.emit("const ");
                if (std.mem.indexOfScalar(u8, mod_name, '.') != null) {
                    try self.emitDottedIdent(mod_name);
                } else {
                    try self.emitIdent(mod_name);
                }
                try self.emit(" = struct {};\n");
                const mod_copy = try self.arena.allocator().dupe(u8, mod_name);
                try self.imported_modules.put(mod_copy, {});
                try emitted_module_consts.put(mod_name, {});
                continue;
            }
            // Fall through to emit the runtime import
        }

        try emitted_module_consts.put(mod_name, {});

        // Track this module name for call site handling
        const mod_copy = try self.arena.allocator().dupe(u8, mod_name);
        try self.imported_modules.put(mod_copy, {});

        // NOTE: Do NOT skip module imports even if from-import has same symbol name.
        // The from-imports.zig already handles skipping the redundant from-import symbol.
        // We need the module import (e.g., const copy = std;) for other symbols like deepcopy.

        // Look up module in registry - only emit registry modules here
        if (self.import_registry.lookup(mod_name)) |info| {
            switch (info.strategy) {
                .zig_runtime, .c_library => {
                    // Use Zig import from registry
                    // Prefer direct_import for DCE-friendly imports, fallback to zig_import
                    const import_path = info.direct_import orelse info.zig_import;
                    try self.emit("const ");
                    // For dotted names (e.g., test.pickletester), use emitDottedIdent
                    // For simple names, use emitIdent (NOT emitVarName which adds _ suffix)
                    // Module imports should keep their original names so usage matches (e.g., unittest.assertX)
                    if (std.mem.indexOfScalar(u8, mod_name, '.') != null) {
                        try self.emitDottedIdent(mod_name);
                    } else {
                        try self.emitIdent(mod_name);
                    }
                    try self.emit(" = ");
                    if (import_path) |path| {
                        // Use emitImportPath to handle keyword module names like "enum"
                        try self.emitImportPath(path);
                        try self.emit(";\n");
                    } else {
                        // No direct import path - try stdlib_modules_gen as fallback
                        const stdlib_gen = @import("../stdlib_modules_gen.zig");
                        if (stdlib_gen.hasModule(mod_name)) {
                            try self.emit("runtime.Lib.");
                            try self.emitDottedIdent(mod_name);
                            try self.emit(";\n");
                        } else {
                            // Module not implemented - mark as skipped for VM fallback
                            // dispatch.zig will use VM fallback for any access
                            try self.markSkippedModule(mod_name);
                            // Emit empty struct as placeholder (const decl already emitted)
                            try self.emit("struct {};\n");
                        }
                    }
                },
                .compile_python, .unsupported => {
                    // These modules are handled via @import above (if compiled)
                    // or skipped (if unsupported)
                },
            }
        } else {
            // Module not in registry - check if it's in stdlib_modules_gen
            const stdlib_gen = @import("../stdlib_modules_gen.zig");
            if (stdlib_gen.hasModule(mod_name)) {
                // Generate import from runtime.Lib
                try self.emit("const ");
                // For dotted names, use emitDottedIdent; for simple names, use emitIdent
                // Module imports should keep their original names so usage matches
                if (std.mem.indexOfScalar(u8, mod_name, '.') != null) {
                    try self.emitDottedIdent(mod_name);
                } else {
                    try self.emitIdent(mod_name);
                }
                try self.emit(" = runtime.Lib.");
                // Replace dots with @"" for nested modules
                try self.emitDottedIdent(mod_name);
                try self.emit(";\n");
            }
            // User modules without registry entry are handled via @import above
        }
    }

    // PHASE 3.7.1: Emit import aliases (import X as Y -> const Y = X;)
    // For dotted names like numpy._core.numeric, emit nested field access: numpy._core.numeric
    // Skip C extension modules - they don't have Zig aliases, they're called via c_interop
    for (self.import_aliases.keys()) |alias| {
        const module_name = self.import_aliases.get(alias).?;
        // Skip C extension modules - they are loaded at runtime via c_interop.callModuleFunction
        if (self.isCExtensionModule(module_name) or self.isCExtensionModule(alias)) {
            continue;
        }
        try self.emit("const ");
        try self.emitIdent(alias);
        try self.emit(" = ");
        // For dotted module names like numpy._core.numeric, emit as nested field access
        // numpy._core.numeric instead of @"numpy__core_numeric"
        if (std.mem.indexOfScalar(u8, module_name, '.') != null) {
            // Split on dots and emit as nested field access
            var iter = std.mem.splitScalar(u8, module_name, '.');
            var first = true;
            while (iter.next()) |part| {
                if (!first) {
                    try self.emit(".");
                }
                try self.emitIdent(part);
                first = false;
            }
        } else {
            try self.emitIdent(module_name);
        }
        try self.emit(";\n");
    }

    try self.emit("\n");

    // PHASE 3.6: Generate from-import symbol re-exports
    try from_imports_gen.generateFromImports(self);

    // PHASE 3.7: Emit module-level type aliases BEFORE class definitions
    // Type aliases like `F = fractions.Fraction` must be at module level because
    // class methods (e.g., DummyFloat._richcmp) need them at compile time.
    try emitModuleLevelTypeAliases(self, module.body);

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

    // PHASE 3.9: Emit export marker for Zig 0.15 build-lib compatibility
    // In Zig 0.15, "module 'main' declared but not used" error occurs for shared libraries
    // unless there's at least one export symbol. This marker satisfies that requirement.
    // Only emit for main entry file (not dependencies, which are @imported)
    if (!self.is_dependency) {
        try self.emit("export fn _metal0_module_marker() callconv(.c) void {}\n");
    }

    // PHASE 4: Define __name__ constant (for if __name__ == "__main__" support)
    try self.emit("const __name__ = \"__main__\";\n");
    // Track __name__ as module-level so local assignments get renamed to avoid shadowing
    try self.module_level_vars.put("__name__", {});

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
                try self.emitFmt("{c}", .{c});
            }
        }
    } else {
        try self.emit("<unknown>");
    }
    try self.emit("\";\n\n");
    // Track __file__ as module-level so local assignments get renamed to avoid shadowing
    try self.module_level_vars.put("__file__", {});

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
                try self.emitFmt("{c}", .{c});
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
    if (DEBUG_CODEGEN) std.debug.print("generate(): Phase 4.7 - Pre-populating module_level_vars with {d} global vars...\n", .{analysis.global_vars.len});
    for (analysis.global_vars) |var_name| {
        try self.module_level_vars.put(var_name, {});
    }
    if (DEBUG_CODEGEN) std.debug.print("generate(): Phase 4.7 complete.\n", .{});

    // PHASE 4.8: Generate conditional global variable declarations
    // Variables assigned in both if/else branches need pre-declaration as var (mutable)
    if (conditional_assignments.items.len > 0) {
        try self.emit("\n// Module-level conditional variables (assigned in if/else branches)\n");
        for (conditional_assignments.items) |cond_var| {
            // Skip if already declared (e.g., via 'global' keyword)
            if (self.isDeclared(cond_var.name)) {
                continue;
            }

            // Use var (mutable) since these are assigned conditionally
            // Use the inferred type from both branches (or PyValue as fallback)
            // Use Pass 2.5 name for declaration to match references
            const zig_name = self.getZigName(cond_var.name);
            try self.emit("var ");
            try self.emitIdent(zig_name);
            try self.emit(": ");
            try self.emit(cond_var.zig_type);
            try self.emit(" = undefined;\n");

            // Mark as declared so main() doesn't re-declare (use original name for tracking)
            try self.declareVar(cond_var.name);
            try self.markGlobalVar(cond_var.name);

            // Track the type so assignment codegen can generate correct empty containers
            try self.conditional_var_types.put(cond_var.name, cond_var.zig_type);
        }
        try self.emit("\n");
    }

    // PHASE 5: Generate imports, class and function definitions (before main)
    // In module mode, wrap functions in pub struct
    if (DEBUG_CODEGEN) std.debug.print("generate(): Phase 5 - Generating class and function definitions...\n", .{});
    if (DEBUG_CODEGEN) std.debug.print("generate():   Mode: {s}\n", .{@tagName(self.mode)});
    if (self.mode == .module) {
        if (DEBUG_CODEGEN) std.debug.print("generate():   Module mode detected.\n", .{});
        // Module mode: emit __global_allocator for f-strings and other allocating operations
        // This is needed because modules are compiled separately and don't have main() setup
        if (analysis.needs_allocator) {
            try self.emit("\n// Module-level allocator for f-strings and dynamic allocations\n");
            try self.emit("var __gpa = std.heap.GeneralPurposeAllocator(.{ .safety = true, .thread_safe = true }){};\n");
            try self.emit("var __global_allocator: std.mem.Allocator = __gpa.allocator();\n");
        }

        // Module mode: emit sys.platform and sys.byteorder constants (computed at compile time)
        // These are used when modules reference sys.platform or sys.byteorder at module level
        try self.emit("const __sys_platform: []const u8 = switch (@import(\"builtin\").os.tag) { .linux => \"linux\", .macos => \"darwin\", .windows => \"win32\", .freebsd => \"freebsd\", else => \"unknown\" };\n");
        try self.emit("const __sys_byteorder: []const u8 = if (@import(\"builtin\").cpu.arch.endian() == .little) \"little\" else \"big\";\n");

        if (self.module_name) |mod_name| {
            try self.emit("pub const ");
            try self.emitIdent(mod_name);
            try self.emit(" = struct {\n");
            self.indent();
        }
    }
    if (DEBUG_CODEGEN) std.debug.print("generate():   Module mode setup complete.\n", .{});

    if (DEBUG_CODEGEN) std.debug.print("generate(): Phase 5.1 - Processing {d} module body statements...\n", .{module.body.len});
    for (module.body, 0..) |stmt, i| {
        if (DEBUG_CODEGEN) std.debug.print("generate():   Phase 5.1 - Statement {d}/{d}: {s}\n", .{i+1, module.body.len, @tagName(stmt)});
        if (stmt == .import_stmt) {
            try statements.genImport(self, stmt.import_stmt);
        } else if (stmt == .import_from) {
            try statements.genImportFrom(self, stmt.import_from);
        } else if (stmt == .class_def) {
            // Record debug line mapping for class definitions
            if (DEBUG_CODEGEN) std.debug.print("generate():     Processing class: {s}\n", .{stmt.class_def.name});
            self.recordLineMappingForName(stmt.class_def.name);
            try statements.genClassDef(self, stmt.class_def);
            try self.emit("\n");
        } else if (stmt == .function_def) {
            // Record debug line mapping for function definitions
            self.recordLineMappingForName(stmt.function_def.name);
            if (self.mode == .module) {
                // In module mode, make functions pub
                try self.emitIndent();
                try self.emit("pub ");
            }
            try statements.genFunctionDef(self, stmt.function_def);
            try self.emit("\n");
            // Clear func_local_uses after module-level function generation
            // This prevents the state from leaking into subsequent class definitions
            // which could incorrectly trigger `_ = &ClassName;` emission at struct level
            self.func_local_uses.clearRetainingCapacity();
        } else if (stmt == .try_stmt) {
            // Hoist function definitions from except handlers to module level
            // This is needed because:
            // 1. try/except is processed inside main() later (Phase 7)
            // 2. Zig doesn't allow function definitions inside catch blocks
            // 3. Python pattern: try: from X import func except: def func(): pass
            //
            // IMPORTANT: Only hoist if the import will FAIL (module doesn't have the function)
            // If import succeeds, the try body will create a const that would shadow the hoisted function
            const try_node = stmt.try_stmt;

            // Check if try body has an import_from - if so, check what's being imported
            var imported_names = std.StringHashMap(void).init(self.allocator);
            defer imported_names.deinit();

            for (try_node.body) |try_body_stmt| {
                if (try_body_stmt == .import_from) {
                    const imp = try_body_stmt.import_from;
                    // Check if module exists and has the imported names
                    const mod_name = imp.module;
                    const mod_info = self.import_registry.lookup(mod_name);
                    if (mod_info != null) {
                        // Module exists - the import will succeed for its exported functions
                        // Mark all imported names as "will succeed"
                        for (imp.names) |name| {
                            try imported_names.put(name, {});
                        }
                    }
                }
            }

            for (try_node.handlers) |handler| {
                for (handler.body) |h_stmt| {
                    if (h_stmt == .function_def) {
                        const func_name = h_stmt.function_def.name;
                        // Only hoist if this function name is NOT being successfully imported
                        if (imported_names.contains(func_name)) {
                            // Import will succeed - don't hoist, the import will provide the function
                            // BUT: mark it so the handler body skips generating it
                            try self.module_level_vars.put(func_name, {});
                            continue;
                        }
                        // Import will fail - hoist the fallback function
                        self.recordLineMappingForName(func_name);
                        try statements.genFunctionDef(self, h_stmt.function_def);
                        try self.emit("\n");
                        self.func_local_uses.clearRetainingCapacity();
                        // Mark as hoisted so we skip it in the handler body later
                        // Use module_level_vars (not hoisted_vars) since hoisted_vars gets cleared before main()
                        try self.module_level_vars.put(func_name, {});
                    }
                }
            }
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
                    const tmp_name = try self.freshName("module_unpack");

                    try self.emit("const ");
                    try self.emit(tmp_name);
                    try self.emit(" = ");
                    // At module level, we need to wrap any try expressions in catch unreachable
                    // since 'try' is not allowed outside function scope
                    const needs_error_handling = stmt.assign.value.* == .call;
                    if (needs_error_handling) {
                        try self.emit("(");
                    }
                    try expressions.genExpr(self, stmt.assign.value.*);
                    if (needs_error_handling) {
                        try self.emit(") catch unreachable");
                    }
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
                            const disambiguated_name = self.getModuleLevelName(var_name);
                            try self.declareVar(var_name);
                            try self.emitIndent();
                            try self.emit("pub const ");
                            try self.emitIdent(disambiguated_name);
                            try self.emitFmt(" = {s}.@\"{d}\";\n", .{ tmp_name, j });
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
                                        // Mark as factory-returned since it comes from tuple unpacking of factory call
                                        try self.unittest_classes.append(self.allocator, core.TestClassInfo{
                                            .class_name = var_name,
                                            .test_methods = orig_class_info.test_methods,
                                            .has_setUp = orig_class_info.has_setUp,
                                            .has_tearDown = orig_class_info.has_tearDown,
                                            .has_setup_class = orig_class_info.has_setup_class,
                                            .has_teardown_class = orig_class_info.has_teardown_class,
                                            .is_factory_returned = true,
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
                    // Generate target name - use disambiguated name if it conflicts with module name
                    for (stmt.assign.targets, 0..) |target, target_idx| {
                        if (target == .name) {
                            const var_name = target.name.id;
                            const disambiguated_name = self.getModuleLevelName(var_name);
                            try self.declareVar(var_name);
                            try self.emitIdent(disambiguated_name);
                        }
                        if (target_idx < stmt.assign.targets.len - 1) {
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
        try self.emit("// Browser WASM: FixedBufferAllocator (no std.Thread), Native: GPA\n");
        try self.emit("const __is_freestanding = @import(\"builtin\").os.tag == .freestanding;\n");
        try self.emit("// Freestanding uses fixed buffer (64KB), native uses GPA\n");
        try self.emit("var __wasm_buffer: [64 * 1024]u8 = undefined;\n");
        try self.emit("var __fba = std.heap.FixedBufferAllocator.init(&__wasm_buffer);\n");
        try self.emit("var __gpa = std.heap.GeneralPurposeAllocator(.{ .safety = true, .thread_safe = true }){};\n");
        try self.emit("var __global_allocator: std.mem.Allocator = undefined;\n");
        try self.emit("var __allocator_initialized: bool = false;\n");
        // sys.argv mutable global - can be assigned by Python code
        try self.emit("var __sys_argv: [][]const u8 = &[_][]const u8{};\n");
        // sys module pre-computed globals (avoid repeated block label collisions)
        try self.emit("var __sys_executable: []const u8 = \"\";\n");
        try self.emit("var __sys_platform: []const u8 = \"unknown\";\n");
        try self.emit("var __sys_byteorder: []const u8 = \"little\";\n\n");
    }

    // PHASE 5.6: Generate module-level global variables (for 'global' keyword support)
    if (analysis.global_vars.len > 0) {
        // PRE-SCAN: Detect ALL type aliases FIRST before processing any variables
        // This ensures type_alias_targets is fully populated when we process variables
        // that use type aliases (e.g., a = R(0, 1) where R = fractions.Fraction)
        for (analysis.global_vars) |var_name| {
            for (module.body) |stmt| {
                if (stmt == .assign) {
                    const assign = stmt.assign;
                    for (assign.targets) |target| {
                        if (target == .name and std.mem.eql(u8, target.name.id, var_name)) {
                            // Check if RHS is a module.Type pattern (fractions.Fraction, decimal.Decimal, etc.)
                            if (assign.value.* == .attribute) {
                                const attr = assign.value.attribute;
                                if (attr.value.* == .name) {
                                    const module_name = attr.value.name.id;
                                    const attr_name = attr.attr;
                                    // Known type exports from modules
                                    if (std.mem.eql(u8, module_name, "fractions") and std.mem.eql(u8, attr_name, "Fraction")) {
                                        try self.type_alias_vars.put(try self.arena.allocator().dupe(u8, var_name), {});
                                        try self.type_alias_targets.put(try self.arena.allocator().dupe(u8, var_name), try self.arena.allocator().dupe(u8, attr_name));
                                    } else if (std.mem.eql(u8, module_name, "decimal") and std.mem.eql(u8, attr_name, "Decimal")) {
                                        try self.type_alias_vars.put(try self.arena.allocator().dupe(u8, var_name), {});
                                        try self.type_alias_targets.put(try self.arena.allocator().dupe(u8, var_name), try self.arena.allocator().dupe(u8, attr_name));
                                    }
                                }
                            }
                        }
                    }
                }
            }
        }

        try self.emit("\n// Module-level variables declared with 'global' keyword\n");
        for (analysis.global_vars) |var_name| {
            // Track in module_level_vars so local variables with same name get renamed
            // to avoid Zig's module-level shadowing error
            try self.module_level_vars.put(var_name, {});

            // Check if this is a type alias (already detected in pre-scan)
            // Skip pre-declaring type aliases - they'll be emitted as const at assignment
            if (self.type_alias_vars.contains(var_name)) {
                continue;
            }

            // Legacy early check kept for safety (should already be caught by pre-scan)
            var is_type_alias_early = false;
            var type_alias_target_early: ?[]const u8 = null;
            for (module.body) |stmt| {
                if (stmt == .assign) {
                    const assign = stmt.assign;
                    for (assign.targets) |target| {
                        if (target == .name and std.mem.eql(u8, target.name.id, var_name)) {
                            // Check if RHS is a module.Type pattern (fractions.Fraction, decimal.Decimal, etc.)
                            if (assign.value.* == .attribute) {
                                const attr = assign.value.attribute;
                                if (attr.value.* == .name) {
                                    const module_name = attr.value.name.id;
                                    const attr_name = attr.attr;
                                    // Known type exports from modules
                                    if (std.mem.eql(u8, module_name, "fractions") and std.mem.eql(u8, attr_name, "Fraction")) {
                                        is_type_alias_early = true;
                                        type_alias_target_early = attr_name;
                                    } else if (std.mem.eql(u8, module_name, "decimal") and std.mem.eql(u8, attr_name, "Decimal")) {
                                        is_type_alias_early = true;
                                        type_alias_target_early = attr_name;
                                    }
                                }
                            }
                        }
                    }
                }
            }

            // Skip pre-declaring type aliases - they'll be emitted as const at assignment
            if (is_type_alias_early) {
                if (type_alias_target_early) |target_type| {
                    try self.type_alias_vars.put(try self.arena.allocator().dupe(u8, var_name), {});
                    try self.type_alias_targets.put(try self.arena.allocator().dupe(u8, var_name), try self.arena.allocator().dupe(u8, target_type));
                }
                continue;
            }

            // Get type from type inferrer, default to i64 for integers
            const var_type = self.type_inferrer.var_types.get(var_name);

            // Callable types (function references like float.fromhex) are handled specially:
            // They're emitted at module level directly when encountered as module-level assignments
            // Skip pre-declaration here to avoid type mismatch
            if (var_type) |vt| {
                if (type_traits.isCallable(vt)) {
                    // Track as callable global - will be emitted as const at module level in statements
                    try self.markGlobalVar(var_name);
                    try self.callable_global_vars.put(try self.arena.allocator().dupe(u8, var_name), {});
                    continue;
                }

                // Tuples of callables (operator.le, operator.lt, etc.) need special handling:
                // They can't be forward-declared because operator wrappers are bare fn ptrs,
                // not PyCallable structs. Skip pre-declaration and emit as const at module level.
                if (container_traits.isTuple(vt)) {
                    var has_callable = false;
                    for (vt.tuple) |t| {
                        if (t == .callable) {
                            has_callable = true;
                            break;
                        }
                    }
                    if (has_callable) {
                        // Track as callable global - will be emitted as const at module level
                        try self.markGlobalVar(var_name);
                        try self.callable_global_vars.put(try self.arena.allocator().dupe(u8, var_name), {});
                        continue;
                    }
                }
            }

            // Also check if assignment is a BinOp combining callable tuples
            // e.g., comparisons = order_comparisons + equality_comparisons
            for (module.body) |stmt| {
                if (stmt == .assign) {
                    const assign = stmt.assign;
                    for (assign.targets) |target| {
                        if (target == .name and std.mem.eql(u8, target.name.id, var_name)) {
                            if (assign.value.* == .binop) {
                                const binop = assign.value.binop;
                                if (binop.op == .Add) {
                                    // Check if both operands are callable tuples
                                    const left_is_callable = blk: {
                                        if (binop.left.* == .name) {
                                            const left_type = self.type_inferrer.var_types.get(binop.left.name.id);
                                            if (left_type) |lt| {
                                                if (container_traits.isTuple(lt)) {
                                                    for (lt.tuple) |t| {
                                                        if (t == .callable) break :blk true;
                                                    }
                                                }
                                            }
                                        }
                                        break :blk false;
                                    };
                                    const right_is_callable = blk: {
                                        if (binop.right.* == .name) {
                                            const right_type = self.type_inferrer.var_types.get(binop.right.name.id);
                                            if (right_type) |rt| {
                                                if (container_traits.isTuple(rt)) {
                                                    for (rt.tuple) |t| {
                                                        if (t == .callable) break :blk true;
                                                    }
                                                }
                                            }
                                        }
                                        break :blk false;
                                    };
                                    if (left_is_callable or right_is_callable) {
                                        // Track as callable global - will be emitted as const at module level
                                        try self.markGlobalVar(var_name);
                                        try self.callable_global_vars.put(try self.arena.allocator().dupe(u8, var_name), {});
                                        break;
                                    }
                                }
                            }
                        }
                    }
                }
            }
            // Skip if already added to callable_global_vars
            if (self.callable_global_vars.contains(var_name)) {
                continue;
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
            var listcomp_node: ?*const ast.Node = null;
            for (module.body) |stmt| {
                if (stmt == .assign) {
                    const assign = stmt.assign;
                    for (assign.targets) |target| {
                        if (target == .name and std.mem.eql(u8, target.name.id, var_name)) {
                            if (assign.value.* == .listcomp) {
                                listcomp_node = assign.value;
                            }
                        }
                    }
                }
            }

            // Pre-declare list comprehensions using type inference (which correctly handles
            // string concatenation, loop variable types, etc.)
            if (listcomp_node) |lc_node| {
                const lc_type = self.type_inferrer.inferExpr(lc_node.*) catch .unknown;
                try self.emit("var ");
                try self.emitVarName(self.getZigName(var_name));
                try self.emit(": ");
                if (container_traits.isList(lc_type)) {
                    // Use the inferred list type with correct element type
                    var type_buf: std.ArrayListUnmanaged(u8) = .{};
                    defer type_buf.deinit(self.allocator);
                    try lc_type.toZigType(self.allocator, &type_buf);
                    try self.emit(type_buf.items);
                } else {
                    // Fallback to generic list type
                    try self.emit("std.ArrayList(runtime.PyValue)");
                }
                try self.emit(" = undefined;\n");
                try self.symbol_table.declare(var_name, lc_type, true);
                try self.markGlobalVar(var_name);
                continue;
            }

            // Check if this variable is assigned from a dict comprehension
            // Dict comprehensions have full type info (key and value types) from type inference
            var dictcomp_node: ?*const ast.Node = null;
            for (module.body) |stmt| {
                if (stmt == .assign) {
                    const assign = stmt.assign;
                    for (assign.targets) |target| {
                        if (target == .name and std.mem.eql(u8, target.name.id, var_name)) {
                            if (assign.value.* == .dictcomp) {
                                dictcomp_node = assign.value;
                            }
                        }
                    }
                }
            }

            // Pre-declare dict comprehensions using type inference (which correctly handles
            // [*range(n)] and (*range(n),) patterns for loop variable types)
            if (dictcomp_node) |dc_node| {
                const dc_type = self.type_inferrer.inferExpr(dc_node.*) catch .unknown;
                try self.emit("var ");
                try self.emitVarName(self.getZigName(var_name));
                try self.emit(": ");
                if (container_traits.isDict(dc_type)) {
                    // Use the inferred dict type with correct key/value types
                    var type_buf: std.ArrayListUnmanaged(u8) = .{};
                    defer type_buf.deinit(self.allocator);
                    try dc_type.toZigType(self.allocator, &type_buf);
                    try self.emit(type_buf.items);
                } else {
                    // Fallback to generic dict type
                    try self.emit("hashmap_helper.StringHashMap(*runtime.PyObject)");
                }
                try self.emit(" = undefined;\n");
                try self.symbol_table.declare(var_name, dc_type, true);
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
                try self.import_module_vars.put(try self.arena.allocator().dupe(u8, var_name), {});
                continue;
            }

            // Skip pre-declaring get_feature_macros results - they're compile-time struct refs
            if (is_feature_macros_call) {
                try self.import_module_vars.put(try self.arena.allocator().dupe(u8, var_name), {});
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

            // Check if this variable is assigned from dict() builtin with no args
            // The type is only known at runtime based on subsequent mutations
            var is_dict_builtin = false;
            for (module.body) |stmt| {
                if (stmt == .assign) {
                    const assign = stmt.assign;
                    for (assign.targets) |target| {
                        if (target == .name and std.mem.eql(u8, target.name.id, var_name)) {
                            if (assign.value.* == .call) {
                                const call = assign.value.call;
                                if (call.func.* == .name) {
                                    const func_name = call.func.name.id;
                                    if (std.mem.eql(u8, func_name, "dict") and call.args.len == 0) {
                                        is_dict_builtin = true;
                                    }
                                }
                            }
                        }
                    }
                }
            }

            // For dict() builtin assignments, use mutation-analyzed type for pre-declaration
            // and initialize directly (skip the d = dict() assignment later)
            if (is_dict_builtin) {
                if (self.mutation_info) |mut_info| {
                    const has_str_keys = mutation_analyzer.hasDictStrKeyMutation(mut_info.*, var_name);
                    const has_int_keys = mutation_analyzer.hasDictIntKeyMutation(mut_info.*, var_name);

                    // Check value type from type inferrer (following pattern from line 942-963)
                    const dict_type = self.type_inferrer.var_types.get(var_name);
                    var value_tag_str: ?[]const u8 = null;
                    if (dict_type) |dt| {
                        if (container_traits.isDict(dt)) {
                            const value_type = dt.dict.value.*;
                            if (string_traits.isString(value_type)) value_tag_str = "string";
                            if (type_traits.isFloating(value_type)) value_tag_str = "float";
                        }
                    }

                    // Determine type based on key/value analysis
                    // Look for value type in dict mutations by scanning the module AST
                    var dict_value_type: []const u8 = "i64";
                    for (module.body) |stmt| {
                        if (stmt == .assign) {
                            const assign = stmt.assign;
                            for (assign.targets) |target| {
                                if (target == .subscript and target.subscript.value.* == .name) {
                                    if (std.mem.eql(u8, target.subscript.value.name.id, var_name)) {
                                        // Found d[key] = value, check value type
                                        if (assign.value.* == .constant) {
                                            if (assign.value.constant.value == .string) {
                                                dict_value_type = "[]const u8";
                                            } else if (assign.value.constant.value == .float) {
                                                dict_value_type = "f64";
                                            }
                                        } else if (assign.value.* == .name or assign.value.* == .attribute) {
                                            // Variable reference - might be string, default to generic
                                            // Check type inference if available
                                            const val_type = self.type_inferrer.inferExpr(assign.value.*) catch .unknown;
                                            if (string_traits.isString(val_type)) {
                                                dict_value_type = "[]const u8";
                                            }
                                        }
                                        break;
                                    }
                                }
                            }
                        }
                    }

                    const zig_type: []const u8 = if (has_str_keys) blk: {
                        if (value_tag_str) |vtag| {
                            if (std.mem.eql(u8, vtag, "string")) break :blk "hashmap_helper.StringHashMap([]const u8)";
                            if (std.mem.eql(u8, vtag, "float")) break :blk "hashmap_helper.StringHashMap(f64)";
                        }
                        if (std.mem.eql(u8, dict_value_type, "[]const u8")) break :blk "hashmap_helper.StringHashMap([]const u8)";
                        if (std.mem.eql(u8, dict_value_type, "f64")) break :blk "hashmap_helper.StringHashMap(f64)";
                        break :blk "hashmap_helper.StringHashMap(i64)";
                    } else if (has_int_keys) blk: {
                        if (value_tag_str) |vtag| {
                            if (std.mem.eql(u8, vtag, "string")) break :blk "std.AutoArrayHashMap(i64, []const u8)";
                            if (std.mem.eql(u8, vtag, "float")) break :blk "std.AutoArrayHashMap(i64, f64)";
                        }
                        if (std.mem.eql(u8, dict_value_type, "[]const u8")) break :blk "std.AutoArrayHashMap(i64, []const u8)";
                        if (std.mem.eql(u8, dict_value_type, "f64")) break :blk "std.AutoArrayHashMap(i64, f64)";
                        break :blk "std.AutoArrayHashMap(i64, i64)";
                    } else "hashmap_helper.StringHashMap(i64)"; // Default for empty dict()

                    try self.emit("var ");
                    try self.emitVarName(self.getZigName(var_name));
                    try self.emit(": ");
                    try self.emit(zig_type);
                    try self.emit(" = undefined;\n");
                    try self.symbol_table.declare(var_name, .unknown, true);
                    try self.markGlobalVar(var_name);
                    // Track for assignment handling - skip assignment, will be initialized in main
                    try self.dict_builtin_vars.put(try self.arena.allocator().dupe(u8, var_name), {});
                    continue;
                }
            }

            // Check if this variable is assigned a type alias (e.g., R = fractions.Fraction)
            // Type aliases need `const R = type` not `var R: SomeType = undefined`
            var type_alias_target: ?[]const u8 = null;
            for (module.body) |stmt| {
                if (stmt == .assign) {
                    const assign = stmt.assign;
                    for (assign.targets) |target| {
                        if (target == .name and std.mem.eql(u8, target.name.id, var_name)) {
                            // Check if RHS is a module.Type pattern (fractions.Fraction, decimal.Decimal, etc.)
                            if (assign.value.* == .attribute) {
                                const attr = assign.value.attribute;
                                if (attr.value.* == .name) {
                                    const module_name = attr.value.name.id;
                                    const attr_name = attr.attr;
                                    // Known type exports from modules
                                    if (std.mem.eql(u8, module_name, "fractions") and std.mem.eql(u8, attr_name, "Fraction")) {
                                        type_alias_target = attr_name;
                                    } else if (std.mem.eql(u8, module_name, "decimal") and std.mem.eql(u8, attr_name, "Decimal")) {
                                        type_alias_target = attr_name;
                                    }
                                }
                            }
                            // Also check if RHS is a simple name that was from-imported
                            // e.g., `from fractions import Fraction; R = Fraction`
                            // We can't rely on module_level_from_imports here because it's
                            // populated in Phase 5.1, after this Phase 4.7.
                            // Instead, scan the module body for from-imports directly.
                            if (assign.value.* == .name) {
                                const rhs_name = assign.value.name.id;
                                // Scan module body for from-import that provides this name
                                for (module.body) |from_stmt| {
                                    if (from_stmt == .import_from) {
                                        const from_import = from_stmt.import_from;
                                        // ImportFrom has names: [][]const u8 and asnames: []?[]const u8
                                        for (from_import.names, 0..) |import_name, idx| {
                                            // Get the local name (asname if set, else import_name)
                                            const local_name = if (idx < from_import.asnames.len and from_import.asnames[idx] != null)
                                                from_import.asnames[idx].?
                                            else
                                                import_name;
                                            if (std.mem.eql(u8, local_name, rhs_name)) {
                                                // Found the from-import. Now check if it's a type alias.
                                                // fractions.Fraction or decimal.Decimal
                                                if (std.mem.eql(u8, from_import.module, "fractions") and
                                                    std.mem.eql(u8, import_name, "Fraction"))
                                                {
                                                    type_alias_target = "Fraction";
                                                } else if (std.mem.eql(u8, from_import.module, "decimal") and
                                                    std.mem.eql(u8, import_name, "Decimal"))
                                                {
                                                    type_alias_target = "Decimal";
                                                }
                                            }
                                        }
                                    }
                                }
                            }
                        }
                    }
                }
            }

            // Skip pre-declaring type aliases - they'll be emitted as const at assignment
            if (type_alias_target) |target_type| {
                try self.type_alias_vars.put(try self.arena.allocator().dupe(u8, var_name), {});
                try self.type_alias_targets.put(try self.arena.allocator().dupe(u8, var_name), try self.arena.allocator().dupe(u8, target_type));
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
                    try self.emitIdent(self.getZigName(var_name));
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
                if (container_traits.isDict(vt)) {
                    // If this dict is copied from another dict, inherit its corrected type
                    if (copy_source_dict) |source_name| {
                        if (self.mutation_info) |mut_info| {
                            const src_has_int_keys = mutation_analyzer.hasDictIntKeyMutation(mut_info.*, source_name);
                            const src_has_str_keys = mutation_analyzer.hasDictStrKeyMutation(mut_info.*, source_name);

                            if (src_has_int_keys and src_has_str_keys) {
                                break :blk "hashmap_helper.StringHashMap(runtime.PyValue)";
                            } else if (src_has_int_keys) {
                                // Inherit source dict's corrected type (AutoArrayHashMap with int keys)
                                break :blk "std.AutoArrayHashMap(i64, i64)";
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
                            if (type_traits.isIntegral(value_type)) {
                                break :blk "std.AutoArrayHashMap(i64, i64)";
                            } else if (type_traits.isFloating(value_type)) {
                                break :blk "std.AutoArrayHashMap(i64, f64)";
                            } else if (string_traits.isString(value_type)) {
                                break :blk "std.AutoArrayHashMap(i64, []const u8)";
                            } else if (type_traits.isUnknown(value_type)) {
                                // Empty dict with int keys defaults to i64 values
                                // (matches dict.zig:61 behavior)
                                break :blk "std.AutoArrayHashMap(i64, i64)";
                            } else {
                                // Default to PyObject for complex values
                                break :blk "std.AutoArrayHashMap(i64, *runtime.PyObject)";
                            }
                        } else if (has_str_keys) {
                            // String keys with mutations - check value type
                            // Empty dicts default to unknown value type, which should be i64
                            // to match dict.zig codegen (d['key'] = 1 typically has int values)
                            const value_type = vt.dict.value.*;
                            if (type_traits.isIntegral(value_type)) {
                                break :blk "hashmap_helper.StringHashMap(i64)";
                            } else if (type_traits.isFloating(value_type)) {
                                break :blk "hashmap_helper.StringHashMap(f64)";
                            } else if (string_traits.isString(value_type)) {
                                break :blk "hashmap_helper.StringHashMap([]const u8)";
                            } else if (type_traits.isUnknown(value_type)) {
                                // Empty dict with string keys defaults to i64 values
                                // (matches dict.zig behavior for empty dicts with str key mutations)
                                break :blk "hashmap_helper.StringHashMap(i64)";
                            }
                            // For other value types, fall through to nativeTypeToZigType
                        }
                        // Default - fall through to nativeTypeToZigType
                    }
                }

                // Check if this is a class instance for a known module-level class
                // If so, use the class name directly instead of *runtime.PyObject
                // This avoids type mismatch when assigning Class.init() to the variable
                if (vt == .class_instance) {
                    const class_name = vt.class_instance;
                    // Check if this class is defined at module level in this file
                    if (self.class_registry.classes.contains(class_name)) {
                        break :blk class_name;
                    }
                    // Also check if it's registered as a module-level function (class constructors
                    // are registered there during PHASE 2.1)
                    if (self.module_level_funcs.contains(class_name)) {
                        break :blk class_name;
                    }
                }

                // Check if this variable is assigned from a type alias call (R(0, 1) where R = fractions.Fraction)
                // This must be checked before falling back to nativeTypeToZigType
                for (module.body) |stmt| {
                    if (stmt == .assign) {
                        const assign = stmt.assign;
                        for (assign.targets) |target| {
                            if (target == .name and std.mem.eql(u8, target.name.id, var_name)) {
                                if (assign.value.* == .call) {
                                    const call = assign.value.call;
                                    if (call.func.* == .name) {
                                        const func_name = call.func.name.id;
                                        if (self.type_alias_targets.get(func_name)) |target_type| {
                                            // R(0, 1) where R = fractions.Fraction -> use Fraction type
                                            if (std.mem.eql(u8, target_type, "Fraction")) {
                                                break :blk "fractions.Fraction";
                                            } else if (std.mem.eql(u8, target_type, "Decimal")) {
                                                break :blk "runtime.Decimal";
                                            }
                                        }
                                    }
                                }
                            }
                        }
                    }
                }

                needs_free = true;
                break :blk try self.nativeTypeToZigType(vt);
            } else blk: {
                // Type not in var_types - try to infer from the assignment value in module body
                // This handles cases where global var type wasn't captured during analysis
                for (module.body) |stmt| {
                    if (stmt == .assign) {
                        const assign = stmt.assign;
                        for (assign.targets) |target| {
                            if (target == .name and std.mem.eql(u8, target.name.id, var_name)) {
                                // Found the assignment - infer type from value
                                if (assign.value.* == .constant) {
                                    const val = assign.value.constant.value;
                                    if (val == .string) break :blk "[]const u8";
                                    if (val == .int) break :blk "i64";
                                    if (val == .float) break :blk "f64";
                                    if (val == .bool) break :blk "bool";
                                    if (val == .none) break :blk "?*anyopaque";
                                }
                                // Check if this is a call to a type alias (R(0, 1) where R = fractions.Fraction)
                                if (assign.value.* == .call) {
                                    const call = assign.value.call;
                                    if (call.func.* == .name) {
                                        const func_name = call.func.name.id;
                                        if (self.type_alias_targets.get(func_name)) |target_type| {
                                            // R(0, 1) where R = fractions.Fraction -> use fractions.Fraction type
                                            if (std.mem.eql(u8, target_type, "Fraction")) {
                                                break :blk "fractions.Fraction";
                                            } else if (std.mem.eql(u8, target_type, "Decimal")) {
                                                break :blk "decimal.Decimal";
                                            }
                                        }
                                    }
                                }
                                // For non-constant values, try type inference on the expression
                                const inferred = self.type_inferrer.inferExpr(assign.value.*) catch .unknown;
                                if (string_traits.isString(inferred)) break :blk "[]const u8";
                                if (type_traits.isIntegral(inferred)) break :blk "i64";
                                if (type_traits.isFloating(inferred)) break :blk "f64";
                                if (inferred == .bool) break :blk "bool";
                                // Handle unknown types - use PyValue for runtime safety
                                if (inferred == .unknown) break :blk "runtime.PyValue";
                            }
                        }
                    }
                }
                // Final fallback: default to i64
                break :blk "i64";
            };
            defer if (needs_free) self.allocator.free(zig_type);

            try self.emit("var ");
            try self.emitVarName(self.getZigName(var_name));
            try self.emit(": ");
            try self.emit(zig_type);
            try self.emit(" = undefined;\n");

            // Mark these as declared at module level (scope 0)
            try self.symbol_table.declare(var_name, var_type orelse .{ .int = .bounded }, true);

            // Also track them as global vars in codegen for assignment handling
            try self.markGlobalVar(var_name);

            // If declared as PyValue, track for assignment wrapping
            // This ensures assignments like `cdll = null` become `cdll = runtime.PyValue.from(null)`
            if (std.mem.eql(u8, zig_type, "runtime.PyValue")) {
                try self.pyvalue_hoisted_vars.put(var_name, {});
            }
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
                            try self.emitIdent(self.getZigName(var_name));
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
                            // Skip if this module was already emitted as a stub in import processing
                            if (self.imported_modules.contains(var_name)) {
                                // Still mark as declared so we skip in main()
                                try self.declareVar(var_name);
                                continue;
                            }
                            // Emit: const ctypes_test = import_module("ctypes");
                            try self.emit("const ");
                            try self.emitIdent(self.getZigName(var_name));
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
    // Use 'pub' for Zig 0.15 compatibility - 'export' can't have error return type
    // For WASM: Zig's std.start automatically exports _start if main exists
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
        try self.emit("    if (comptime __is_freestanding) {\n");
        try self.emitIndent();
        try self.emit("        // Browser WASM: FixedBufferAllocator (no std.Thread)\n");
        try self.emitIndent();
        try self.emit("        break :blk __fba.allocator();\n");
        try self.emitIndent();
        try self.emit("    } else if (comptime allocator_helper.useFastAllocator()) {\n");
        try self.emitIndent();
        try self.emit("        // Release mode: use c_allocator, OS reclaims at exit\n");
        try self.emitIndent();
        try self.emit("        break :blk std.heap.c_allocator;\n");
        try self.emitIndent();
        try self.emit("    } else {\n");
        try self.emitIndent();
        try self.emit("        // Debug: use GPA for leak detection\n");
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
        try self.emit("    // In shared library mode or WASM, std.os.argv is invalid\n");
        try self.emitIndent();
        try self.emit("    const builtin = @import(\"builtin\");\n");
        try self.emitIndent();
        try self.emit("    const is_wasm = builtin.os.tag == .wasi or builtin.os.tag == .freestanding;\n");
        try self.emitIndent();
        try self.emit("    const is_lib = builtin.output_mode == .Lib or builtin.link_mode == .dynamic;\n");
        try self.emitIndent();
        try self.emit("    if (comptime builtin.output_mode == .Exe and !is_wasm and !is_lib) {\n");
        try self.emitIndent();
        try self.emit("        const os_args = std.os.argv;\n");
        try self.emitIndent();
        try self.emit("        var argv_list = std.ArrayListUnmanaged([]const u8){};\n");
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

        // Initialize sys.executable (compute once to avoid block label collisions)
        try self.emitIndent();
        const sys_exec_id = self.nextNameId();
        try self.emitFmt("__sys_executable = (__m{d}_sys_exec: {{\n", .{sys_exec_id});
        try self.emitIndent();
        try self.emit("    const __m0_builtin = @import(\"builtin\");\n");
        try self.emitIndent();
        try self.emit("    const is_wasm = __m0_builtin.os.tag == .wasi or __m0_builtin.os.tag == .freestanding;\n");
        try self.emitIndent();
        try self.emit("    const is_lib = __m0_builtin.output_mode == .Lib or __m0_builtin.link_mode == .dynamic;\n");
        try self.emitIndent();
        try self.emitFmt("    if (comptime is_wasm or is_lib) break :__m{d}_sys_exec \"\";\n", .{sys_exec_id});
        try self.emitIndent();
        try self.emit("    const args = std.os.argv;\n");
        try self.emitIndent();
        try self.emitFmt("    if (args.len > 0) break :__m{d}_sys_exec std.mem.span(args[0]);\n", .{sys_exec_id});
        try self.emitIndent();
        try self.emitFmt("    break :__m{d}_sys_exec \"\";\n", .{sys_exec_id});
        try self.emit("});\n");

        // Initialize sys.platform (compute once)
        try self.emitIndent();
        try self.emit("__sys_platform = switch (@import(\"builtin\").os.tag) { .linux => \"linux\", .macos => \"darwin\", .windows => \"win32\", .freebsd => \"freebsd\", else => \"unknown\" };\n");

        // Initialize sys.byteorder (compute once)
        try self.emitIndent();
        try self.emit("__sys_byteorder = if (@import(\"builtin\").cpu.arch.endian() == .little) \"little\" else \"big\";\n");
        try self.emit("\n");

        // Initialize runtime modules that need allocator (from registry needs_init flag)
        for (self.imported_modules.keys()) |mod_name| {
            if (self.import_registry.lookup(mod_name)) |info| {
                if (info.needs_init) {
                    try self.emitIndent();
                    // Use emitDottedIdent for dotted module names like "test.support"
                    try self.emitDottedIdent(mod_name);
                    try self.emit(".init(__global_allocator);\n");
                }
            }
        }

        // Initialize C extension modules via c_interop.importModule()
        // import numpy as np -> np = c_interop.importModule("numpy") orelse @panic("...");
        if (self.c_extension_modules.count() > 0) {
            try self.emit("\n");
            try self.emitIndent();
            try self.emit("// Initialize C extension modules\n");

            // Track emitted to avoid duplicates
            var emitted_c_ext = hashmap_helper.StringHashMap(void).init(self.allocator);
            defer emitted_c_ext.deinit();

            for (self.c_extension_modules.keys()) |key| {
                const module_name = self.c_extension_modules.get(key).?;
                // Skip module_name -> module_name entries if we have an alias
                if (std.mem.eql(u8, key, module_name)) {
                    var has_alias = false;
                    for (self.c_extension_modules.keys()) |k| {
                        const v = self.c_extension_modules.get(k).?;
                        if (std.mem.eql(u8, v, module_name) and !std.mem.eql(u8, k, module_name)) {
                            has_alias = true;
                            break;
                        }
                    }
                    if (has_alias) continue;
                }

                if (emitted_c_ext.contains(key)) continue;
                try emitted_c_ext.put(key, {});

                // Skip dotted module names ONLY if there's no alias
                // e.g., "import numpy.testing" (key=numpy.testing, module_name=numpy.testing) -> skip
                // But "import numpy.exceptions as ex" (key=ex, module_name=numpy.exceptions) -> import
                // Submodules without alias are accessed via fromImport()
                if (std.mem.indexOfScalar(u8, module_name, '.') != null and std.mem.eql(u8, key, module_name)) continue;

                try self.emitIndent();
                // For dotted names like numpy.exceptions, escape the variable name
                try self.emitIdent(key);
                try self.emitFmt(" = c_interop.importModule(\"{s}\") orelse @panic(\"Failed to import C extension module: {s}\");\n", .{ module_name, module_name });
            }

            // Initialize root modules for submodule imports
            // When "import numpy._core.include" is used, initialize "numpy" even if "numpy as np" exists
            for (self.c_extension_root_modules.keys()) |root_module| {
                if (emitted_c_ext.contains(root_module)) continue;
                try emitted_c_ext.put(root_module, {});

                try self.emitIndent();
                try self.emitIdent(root_module);
                try self.emitFmt(" = c_interop.importModule(\"{s}\") orelse @panic(\"Failed to import C extension module: {s}\");\n", .{ root_module, root_module });
            }
        }

        // Initialize from-imports from C extension modules
        // e.g., assert_ = c_interop.fromImport("numpy.testing", "assert_") orelse @panic(...);
        if (self.c_extension_from_imports.count() > 0) {
            try self.emit("\n");
            try self.emitIndent();
            try self.emit("// Initialize from-imports from C extension modules\n");

            for (self.c_extension_from_imports.keys()) |symbol_name| {
                const info = self.c_extension_from_imports.get(symbol_name).?;
                try self.emitIndent();
                try self.emitIdent(symbol_name);
                try self.emitFmt(" = c_interop.fromImport(\"{s}\", \"{s}\") orelse @panic(\"Failed to import '{s}' from '{s}'\");\n", .{ info.module, info.attr, info.attr, info.module });
            }
        }
    }

    // PHASE 7: Generate statements (skip class/function defs and imports - already handled)
    // This will populate self.lambda_functions
    // Clear hoisted_vars before generating main body (for proper try/except variable tracking)
    self.hoisted_vars.clearRetainingCapacity();
    self.hoisted_dynamic_closures.clearRetainingCapacity();

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

    // Flush builder to output before final return
    try self.flushBuilder();

    // PHASE 8: Prepend lambda functions if any were generated
    if (self.lambda_functions.items.len > 0) {
        // Get current output
        const current_output = try self.output.toOwnedSlice(self.allocator);
        defer self.allocator.free(current_output);

        // Rebuild output with lambdas first
        self.output = std.ArrayList(u8){};

        // Add imports
        try self.emit("const std = @import(\"std\");\n");
        try self.emit("const runtime = @import(\"runtime\");\n");
        if (analysis.needs_string_utils) {
            try self.emit("const string_utils = runtime.string_utils;\n");
        }
        if (analysis.needs_hashmap_helper) {
            // Use runtime.hashmap_helper - hashmap_helper is re-exported from runtime module
            try self.emit("const hashmap_helper = runtime.hashmap_helper;\n");
        }
        // Always import allocator_helper (matches the non-lambda path)
        // Use runtime.allocator_helper - allocator_helper is re-exported from runtime module
        try self.emit("const allocator_helper = runtime.allocator_helper;\n");

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
                        // Prefer direct_import for DCE-friendly imports
                        const import_path = info.direct_import orelse info.zig_import;
                        try self.emit("const ");
                        // For dotted names, use emitDottedIdent; for simple names, use emitIdent
                        // Module imports should keep their original names so usage matches
                        if (std.mem.indexOfScalar(u8, mod_name, '.') != null) {
                            try self.emitDottedIdent(mod_name);
                        } else {
                            try self.emitIdent(mod_name);
                        }
                        try self.emit(" = ");
                        if (import_path) |path| {
                            // Use emitImportPath to handle keyword module names like "enum"
                            try self.emitImportPath(path);
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
                        // Prefer direct_import for DCE-friendly imports
                        const import_path = info.direct_import orelse info.zig_import;
                        try self.emit("const ");
                        // For dotted names, use emitDottedIdent; for simple names, use emitIdent
                        // Module imports should keep their original names so usage matches
                        if (std.mem.indexOfScalar(u8, mod_name, '.') != null) {
                            try self.emitDottedIdent(mod_name);
                        } else {
                            try self.emitIdent(mod_name);
                        }
                        try self.emit(" = ");
                        if (import_path) |path| {
                            // Use emitImportPath to handle keyword module names like "enum"
                            try self.emitImportPath(path);
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
                // Add comptime reference to suppress unused variable warnings
                const escaped_name = try zig_keywords.escapeIfKeyword(self.allocator, root_mod_name);
                defer if (escaped_name.ptr != root_mod_name.ptr) self.allocator.free(escaped_name);
                try self.emit("const ");
                try self.emit(escaped_name);
                try self.emit(" = @import(\"");
                try self.emit(IMPORT_PREFIX);
                try self.emit(root_mod_name);
                try self.emit(MODULE_EXT);
                try self.emit("\");\n");
                try self.emit("comptime { _ = &");
                try self.emit(escaped_name);
                try self.emit("; }\n");

                try lambda_imported_roots.put(root_mod_name, {});
            }
        }
        try self.emit("\n");

        // Add from-import symbol re-exports (Phase 3.6 copy for lambda path)
        try from_imports_gen.generateFromImports(self);

        // Add __name__ constant
        try self.emit("const __name__ = \"__main__\";\n");
        try self.module_level_vars.put("__name__", {});

        // Add __file__ constant
        try self.emit("const __file__: []const u8 = \"");
        if (self.source_file_path) |path| {
            for (path) |c| {
                if (c == '\\') {
                    try self.emit("\\\\");
                } else if (c == '"') {
                    try self.emit("\\\"");
                } else {
                    try self.emitFmt("{c}", .{c});
                }
            }
        } else {
            try self.emit("<unknown>");
        }
        try self.emit("\";\n\n");
        try self.module_level_vars.put("__file__", {});

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

    // Post-process output to fix `_ = varname;` patterns that cause "pointless discard" errors
    // This converts simple identifier discards to use & prefix which is valid in Zig
    try self.fixPointlessDiscards();

    return self.output.toOwnedSlice(self.allocator);
}

pub fn generateStmt(self: *NativeCodegen, node: ast.Node) CodegenError!void {
    // Skip generating statements after control flow termination (return/raise)
    // to avoid unreachable code errors in Zig
    if (self.control_flow_terminated) return;

    // NOTE: Do NOT flush builder here. Each module that uses getBodyDupe()
    // must save/restore builder state to avoid capturing unrelated content.
    // Flushing here captures partial content from previous code paths.

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
            // Record debug line mapping for class definitions
            self.recordLineMappingForName(class.name);
            // Skip if this class was hoisted to struct level (for return type visibility)
            if (self.hoisted_local_classes.contains(class.name)) return;
            try statements.genClassDef(self, class);
            // Track this local class in current scope so assertRaises can detect it needs .init() call
            // Use current_scope_classes which is cleared between methods (not hoisted_local_classes)
            try self.current_scope_classes.put(class.name, {});
        },
        .function_def => |func| {
            // Record debug line mapping for function definitions
            self.recordLineMappingForName(func.name);
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
                const gen_result_name = self.getZigName("__gen_result");
                // Inside defer blocks, 'try' is not allowed - use 'catch {}' instead
                if (self.inside_defer) {
                    try self.emit(gen_result_name);
                    try self.emit(".append(__global_allocator, runtime.PyValue.from(");
                    if (yield.value) |val| {
                        try expressions.genExpr(self, val.*);
                    } else {
                        try self.emit("null");
                    }
                    try self.emit(")) catch {};\n");
                } else {
                    try self.emit("try ");
                    try self.emit(gen_result_name);
                    try self.emit(".append(__global_allocator, runtime.PyValue.from(");
                    if (yield.value) |val| {
                        try expressions.genExpr(self, val.*);
                    } else {
                        // yield without value yields None in Python
                        try self.emit("null");
                    }
                    try self.emit("));\n");
                }
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
                    // Pass outer function's params (including *args and **kwargs) so we can detect captured variables
                    const captured = var_tracking.findCapturedVarsWithSpecialParams(
                        self,
                        nf,
                        func.args,
                        func.vararg,
                        func.kwarg,
                    ) catch continue;
                    defer self.allocator.free(captured);

                    if (captured.len == 0) {
                        // Generate a unique type name based on the outer function
                        const id = self.name_gen.nextId();
                        const type_name = try std.fmt.allocPrint(
                            self.allocator,
                            "__m{d}_{s}__struct",
                            .{ id, func.name },
                        );

                        // Store the type name for later reference in signature.zig
                        // Key is the nested function name, value is the pre-generated type name
                        const nested_name_copy = try self.arena.allocator().dupe(u8, nested_func_name);
                        try self.pending_closure_types.put(nested_name_copy, type_name);

                        // Also mark this function as a closure factory (caller in outer function)
                        const func_name_copy = try self.arena.allocator().dupe(u8, func.name);
                        try self.closure_factories.put(func_name_copy, {});

                        // Generate the entire zero-capture closure at module level
                        // This includes impl struct + wrapper struct
                        try zero_capture.genModuleLevelZeroCaptureClosure(self, nf, type_name);
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
    const function_traits = @import("analysis.function_traits");

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
                } else if (method_categories.getUnittestLifecycleKind(method_name)) |kind| {
                    switch (kind) {
                        .setUp => has_setUp = true,
                        .tearDown => has_tearDown = true,
                        .setUpClass => has_setup_class = true,
                        .tearDownClass => has_teardown_class = true,
                    }
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
            const func_name_copy = try self.arena.allocator().dupe(u8, func.name);
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
                if (stmt.for_stmt.orelse_body) |orelse_body| {
                    if (isFunctionAliasRecursive(orelse_body, var_name, module_level_funcs)) return true;
                }
            },
            .while_stmt => {
                if (isFunctionAliasRecursive(stmt.while_stmt.body, var_name, module_level_funcs)) return true;
                if (stmt.while_stmt.orelse_body) |orelse_body| {
                    if (isFunctionAliasRecursive(orelse_body, var_name, module_level_funcs)) return true;
                }
            },
            .try_stmt => {
                const try_s = stmt.try_stmt;
                if (isFunctionAliasRecursive(try_s.body, var_name, module_level_funcs)) return true;
                for (try_s.handlers) |handler| {
                    if (isFunctionAliasRecursive(handler.body, var_name, module_level_funcs)) return true;
                }
                if (isFunctionAliasRecursive(try_s.else_body, var_name, module_level_funcs)) return true;
                if (isFunctionAliasRecursive(try_s.finalbody, var_name, module_level_funcs)) return true;
            },
            .with_stmt => {
                if (isFunctionAliasRecursive(stmt.with_stmt.body, var_name, module_level_funcs)) return true;
            },
            .match_stmt => {
                for (stmt.match_stmt.cases) |case| {
                    if (isFunctionAliasRecursive(case.body, var_name, module_level_funcs)) return true;
                }
            },
            else => {},
        }
    }
    return false;
}

/// Emit module-level type aliases before class definitions.
/// Detects patterns like `F = fractions.Fraction` and emits `const F = fractions.Fraction;`
/// at module level so class methods can reference them.
fn emitModuleLevelTypeAliases(self: *NativeCodegen, body: []const ast.Node) !void {
    var emitted_any = false;

    for (body) |stmt| {
        if (stmt != .assign) continue;

        const assign = stmt.assign;
        // Only handle simple name targets
        for (assign.targets) |target| {
            if (target != .name) continue;
            const var_name = target.name.id;

            // Check if RHS is module.Type pattern
            if (assign.value.* == .attribute) {
                const attr = assign.value.attribute;
                if (attr.value.* == .name) {
                    const module_name = attr.value.name.id;
                    const attr_name = attr.attr;

                    // Known type exports from modules
                    const is_type_alias = blk: {
                        if (std.mem.eql(u8, module_name, "fractions") and std.mem.eql(u8, attr_name, "Fraction")) break :blk true;
                        if (std.mem.eql(u8, module_name, "decimal") and std.mem.eql(u8, attr_name, "Decimal")) break :blk true;
                        // Add more patterns as needed
                        break :blk false;
                    };

                    if (is_type_alias) {
                        if (!emitted_any) {
                            try self.emit("\n// Module-level type aliases\n");
                            emitted_any = true;
                        }

                        // Track this type alias for call codegen
                        try self.type_alias_vars.put(try self.arena.allocator().dupe(u8, var_name), {});
                        // Also store what type it aliases (e.g., "R" -> "Fraction")
                        try self.type_alias_targets.put(try self.arena.allocator().dupe(u8, var_name), try self.arena.allocator().dupe(u8, attr_name));

                        // Emit: const F = fractions.Fraction;
                        try self.emit("const ");
                        try self.emitIdent(self.getZigName(var_name));
                        try self.emit(" = ");
                        // Emit module.attribute
                        try self.emitIdent(self.getZigName(module_name));
                        try self.emit(".");
                        try self.emitIdent(attr_name);
                        try self.emit(";\n");

                        // Mark as declared so main() doesn't re-declare it
                        try self.declareVar(var_name);
                        try self.markGlobalVar(var_name);
                    }
                }
            }
        }
    }
}

/// Extract all variables assigned in a list of statements (recursively)
fn extractAssignedVars(stmts: []const ast.Node, vars: *FnvVoidMap, allocator: std.mem.Allocator) !void {
    for (stmts) |stmt| {
        switch (stmt) {
            .assign => {
                for (stmt.assign.targets) |target| {
                    if (target == .name) {
                        try vars.put(try allocator.dupe(u8, target.name.id), {});
                    } else if (target == .tuple) {
                        for (target.tuple.elts) |elt| {
                            if (elt == .name) {
                                try vars.put(try allocator.dupe(u8, elt.name.id), {});
                            }
                        }
                    }
                }
            },
            .if_stmt => |if_node| {
                try extractAssignedVars(if_node.body, vars, allocator);
                try extractAssignedVars(if_node.else_body, vars, allocator);
            },
            .for_stmt => |for_node| {
                try extractAssignedVars(for_node.body, vars, allocator);
                if (for_node.orelse_body) |orelse_body| {
                    try extractAssignedVars(orelse_body, vars, allocator);
                }
            },
            .while_stmt => |while_node| {
                try extractAssignedVars(while_node.body, vars, allocator);
                if (while_node.orelse_body) |orelse_body| {
                    try extractAssignedVars(orelse_body, vars, allocator);
                }
            },
            .with_stmt => |with_node| {
                try extractAssignedVars(with_node.body, vars, allocator);
            },
            .try_stmt => |try_node| {
                try extractAssignedVars(try_node.body, vars, allocator);
                for (try_node.handlers) |handler| {
                    try extractAssignedVars(handler.body, vars, allocator);
                }
                try extractAssignedVars(try_node.else_body, vars, allocator);
                try extractAssignedVars(try_node.finalbody, vars, allocator);
            },
            else => {},
        }
    }
}

/// Conditional variable info with inferred type
const ConditionalVar = struct {
    name: []const u8,
    zig_type: []const u8, // Zig type string (e.g., "i64", "hashmap_helper.StringHashMap(void)")
};

/// Helper to emit Zig type from NativeType
fn emitZigTypeFromNative(native_type: @import("../../../analysis/native_types/core.zig").NativeType, allocator: std.mem.Allocator) ![]const u8 {
    return switch (native_type) {
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
        .list => |elem_type| blk: {
            const elem_zig = try emitZigTypeFromNative(elem_type.*, allocator);
            break :blk try std.fmt.allocPrint(allocator, "std.ArrayListUnmanaged({s})", .{elem_zig});
        },
        .dict => |kv| blk: {
            const val_zig = try emitZigTypeFromNative(kv.value.*, allocator);
            // Most dicts use StringHashMap
            break :blk try std.fmt.allocPrint(allocator, "hashmap_helper.StringHashMap({s})", .{val_zig});
        },
        .set => |elem_type| blk: {
            // Sets are StringHashMap(void) for string keys
            // For other key types, use std.AutoArrayHashMap (not hashmap_helper which doesn't have AutoHashMap)
            if (elem_type.* == .string) {
                break :blk "hashmap_helper.StringHashMap(void)";
            }
            // For non-string keys (e.g., PyValue), use StringHashMap(void) as fallback
            // since frozenset with string literals should still use StringHashMap
            break :blk "hashmap_helper.StringHashMap(void)";
        },
        .tuple => "runtime.PyValue", // Tuples use PyValue for heterogeneous elements
        .class_instance => |name| name,
        .optional => |inner| blk: {
            const inner_zig = try emitZigTypeFromNative(inner.*, allocator);
            break :blk try std.fmt.allocPrint(allocator, "?{s}", .{inner_zig});
        },
        else => "runtime.PyValue", // Fallback to PyValue for complex types
    };
}

/// Infer type from a single branch of assignments
/// Returns PyValue if unable to infer or multiple assignments found
fn inferBranchVarType(stmts: []const ast.Node, var_name: []const u8, type_inferrer: anytype, allocator: std.mem.Allocator) ![]const u8 {
    _ = allocator;

    // Find the assignment to this variable
    for (stmts) |stmt| {
        if (stmt == .assign) {
            for (stmt.assign.targets) |target| {
                if (target == .name and std.mem.eql(u8, target.name.id, var_name)) {
                    // Infer type from the value expression
                    const inferred_type = type_inferrer.inferExpr(stmt.assign.value.*) catch {
                        return "runtime.PyValue"; // Fallback on inference error
                    };

                    // Convert NativeType to Zig type string
                    return emitZigTypeFromNative(inferred_type, type_inferrer.allocator) catch {
                        return "runtime.PyValue"; // Fallback on conversion error
                    };
                }
            }
        } else if (stmt == .if_stmt) {
            // Recursively check nested if statements
            const if_type = inferBranchVarType(stmt.if_stmt.body, var_name, type_inferrer, type_inferrer.allocator) catch "runtime.PyValue";
            if (!std.mem.eql(u8, if_type, "runtime.PyValue")) {
                return if_type;
            }
            const else_type = inferBranchVarType(stmt.if_stmt.else_body, var_name, type_inferrer, type_inferrer.allocator) catch "runtime.PyValue";
            if (!std.mem.eql(u8, else_type, "runtime.PyValue")) {
                return else_type;
            }
        }
    }

    return "runtime.PyValue"; // Variable not found in this branch
}

/// Collect module-level conditional assignments that need hoisting
/// Returns a list of ConditionalVar structs with names and inferred types
fn collectConditionalAssignments(module_body: []const ast.Node, type_inferrer: anytype, allocator: std.mem.Allocator) !std.ArrayList(ConditionalVar) {
    var conditional_vars = std.ArrayList(ConditionalVar){};

    for (module_body) |stmt| {
        if (stmt == .if_stmt) {
            const if_node = stmt.if_stmt;

            // Collect variables assigned in if branch
            var if_vars = FnvVoidMap.init(allocator);
            defer if_vars.deinit();
            try extractAssignedVars(if_node.body, &if_vars, allocator);

            // Collect variables assigned in else branch
            var else_vars = FnvVoidMap.init(allocator);
            defer else_vars.deinit();
            try extractAssignedVars(if_node.else_body, &else_vars, allocator);

            // Variables assigned in BOTH branches need hoisting
            // (They're guaranteed to be defined after the if/else)
            var if_iter = if_vars.iterator();
            while (if_iter.next()) |entry| {
                const var_name = entry.key_ptr.*;
                if (else_vars.contains(var_name)) {
                    // Infer types from both branches
                    const if_type = try inferBranchVarType(if_node.body, var_name, type_inferrer, allocator);
                    const else_type = try inferBranchVarType(if_node.else_body, var_name, type_inferrer, allocator);

                    // Use the common type, or PyValue if they differ
                    // Special case: if one branch is a set and the other is an empty tuple/PyValue,
                    // use the set type (Python idiom: () as empty container)
                    const final_type = blk: {
                        if (std.mem.eql(u8, if_type, else_type)) {
                            break :blk if_type;
                        }
                        // Check if either type is a set (StringHashMap or AutoHashMap with void value)
                        const if_is_set = std.mem.indexOf(u8, if_type, "HashMap") != null and
                            std.mem.indexOf(u8, if_type, "void)") != null;
                        const else_is_set = std.mem.indexOf(u8, else_type, "HashMap") != null and
                            std.mem.indexOf(u8, else_type, "void)") != null;

                        // If one branch is a set and other is PyValue (from empty tuple),
                        // prefer the set type - empty tuple will be converted to empty set
                        if (if_is_set and std.mem.eql(u8, else_type, "runtime.PyValue")) {
                            break :blk if_type;
                        }
                        if (else_is_set and std.mem.eql(u8, if_type, "runtime.PyValue")) {
                            break :blk else_type;
                        }
                        break :blk "runtime.PyValue"; // Different types → use PyValue wrapper
                    };

                    const name_copy = try allocator.dupe(u8, var_name);
                    try conditional_vars.append(allocator, ConditionalVar{
                        .name = name_copy,
                        .zig_type = final_type,
                    });
                }
            }
        }
    }

    return conditional_vars;
}

// ============================================================================
// Multi-Pass Build System (Experimental)
// ============================================================================

/// Generate code using the multi-pass build system.
/// This is an experimental alternative to the single-pass `generate` function.
///
/// Pass 1: Python AST → ZigIR (intermediate representation)
/// Pass 2: ZigIR → MutationAnalysis (determine const vs var)
/// Pass 3: ZigIR + MutationAnalysis → Zig source code
///
/// Benefits:
/// - Correct const/var inference (analyzes mutations before emitting)
/// - Cleaner architecture (separation of concerns)
/// - Easier to add optimizations between passes
pub fn generateMultiPass(allocator: std.mem.Allocator, module: ast.Node.Module) ![]const u8 {
    std.debug.print("generateMultiPass(): Starting multi-pass code generation...\n", .{});

    // Pass 1: Generate IR from Python AST
    std.debug.print("generateMultiPass(): Pass 1 - Generating IR...\n", .{});
    const ir_stmts = try ir_gen.generateIR(module, allocator);
    defer {
        for (ir_stmts) |stmt| {
            ir.freeStmt(stmt, allocator);
        }
        allocator.free(ir_stmts);
    }
    std.debug.print("generateMultiPass(): Pass 1 complete - {d} IR statements\n", .{ir_stmts.len});

    // Debug: Print IR
    if (false) { // Set to true to enable IR debug output
        std.debug.print("\n=== Generated IR ===\n", .{});
        for (ir_stmts) |stmt| {
            ir.debugPrintStmt(stmt, std.io.getStdErr().writer(), 0) catch {};
        }
        std.debug.print("===================\n\n", .{});
    }

    // Pass 2: Analyze mutations
    std.debug.print("generateMultiPass(): Pass 2 - Analyzing mutations...\n", .{});
    var analysis = try pass_analysis.analyze(ir_stmts, allocator);
    defer analysis.deinit();
    std.debug.print("generateMultiPass(): Pass 2 complete - {d} mutated vars\n", .{analysis.mutated_vars.count()});

    // Pass 3: Emit final code
    std.debug.print("generateMultiPass(): Pass 3 - Emitting code...\n", .{});
    var output = std.ArrayList(u8){};
    errdefer output.deinit(allocator);

    try emit_pass.emit(ir_stmts, &analysis, &output, allocator);
    std.debug.print("generateMultiPass(): Pass 3 complete - {d} bytes generated\n", .{output.items.len});

    return output.toOwnedSlice(allocator);
}
