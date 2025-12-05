/// Core compilation functions
const std = @import("std");
const hashmap_helper = @import("hashmap_helper");
const ast = @import("ast");
const lexer = @import("../lexer.zig");
const parser = @import("../parser.zig");
const compiler = @import("../compiler.zig");
const native_types = @import("../analysis/native_types.zig");
const semantic_types = @import("../analysis/types.zig");
const lifetime_analysis = @import("../analysis/lifetime.zig");
const native_codegen = @import("../codegen/native/main.zig");
const bytecode_codegen = @import("../codegen/bytecode.zig");
const js_glue = @import("../codegen/js_glue.zig");
const c_interop = @import("c_interop");
const notebook = @import("../notebook.zig");
const CompileOptions = @import("../main.zig").CompileOptions;
const utils = @import("utils.zig");
const import_resolver = @import("../import_resolver.zig");
const import_scanner = @import("../import_scanner.zig");
const import_registry = @import("../codegen/native/import_registry.zig");
const build_dirs = @import("../build_dirs.zig");
const debug_info = @import("debug_info");

// Submodules
const cache = @import("compile/cache.zig");
const output = @import("compile/output.zig");

/// Get module output path for a compiled .so file (delegates to output module)
fn getModuleOutputPath(allocator: std.mem.Allocator, module_path: []const u8) ![]const u8 {
    return output.getModuleOutputPath(allocator, module_path);
}

pub fn compileModule(allocator: std.mem.Allocator, module_path: []const u8, module_name: []const u8) !void {
    // Use arena allocator for all intermediate allocations to avoid leaks on parse errors
    var arena = std.heap.ArenaAllocator.init(allocator);
    defer arena.deinit();
    const aa = arena.allocator();

    // Read module source (handle absolute paths)
    const source = blk: {
        if (std.fs.path.isAbsolute(module_path)) {
            const file = try std.fs.openFileAbsolute(module_path, .{});
            defer file.close();
            break :blk try file.readToEndAlloc(aa, 10 * 1024 * 1024);
        } else {
            break :blk try std.fs.cwd().readFileAlloc(aa, module_path, 10 * 1024 * 1024);
        }
    };
    // No defer needed - arena handles cleanup

    // Use provided module_name if not empty, otherwise derive from path
    const mod_name = if (module_name.len > 0) module_name else blk: {
        const basename = std.fs.path.basename(module_path);
        // For __init__.py, use parent directory name
        if (std.mem.eql(u8, basename, "__init__.py")) {
            if (std.fs.path.dirname(module_path)) |dir| {
                break :blk std.fs.path.basename(dir);
            }
        }
        // Regular module: strip .py extension
        if (std.mem.lastIndexOf(u8, basename, ".")) |idx|
            break :blk basename[0..idx]
        else
            break :blk basename;
    };

    // Generate Zig code for this module
    std.debug.print("  Generating Zig for module: {s}\n", .{module_path});

    // Use existing compilation pipeline
    const lexer_mod = @import("../lexer.zig");
    const parser_mod = @import("../parser.zig");

    var lex = try lexer_mod.Lexer.init(aa, source);
    defer lex.deinit();
    const tokens = try lex.tokenize();
    // No defer needed for tokens - arena handles cleanup

    var p = parser_mod.Parser.init(aa, tokens);
    defer p.deinit();
    const tree = try p.parse();
    // No defer needed for tree - arena handles cleanup

    // Perform semantic analysis
    const semantic_types_mod = @import("../analysis/types.zig");
    const lifetime_analysis_mod = @import("../analysis/lifetime.zig");
    const native_types_mod = @import("../analysis/native_types.zig");

    var semantic_info = semantic_types_mod.SemanticInfo.init(aa);
    defer semantic_info.deinit();
    _ = try lifetime_analysis_mod.analyzeLifetimes(&semantic_info, tree, 1);

    var type_inferrer = try native_types_mod.TypeInferrer.init(aa);
    defer type_inferrer.deinit();
    if (tree == .module) {
        try type_inferrer.analyze(tree.module);
    }

    // Generate Zig code in module mode (top-level exports, no struct wrapper)
    var codegen = try native_codegen.NativeCodegen.init(aa, &type_inferrer, &semantic_info);
    defer codegen.deinit();

    codegen.mode = .module;
    codegen.module_name = null; // No struct wrapper - export functions at top level

    // Build call graph for unified function analysis
    if (tree == .module) {
        try codegen.buildCallGraph(tree.module);
    }

    const zig_code = if (tree == .module)
        try codegen.generate(tree.module)
    else
        return error.InvalidAST;
    // zig_code allocated by arena - no defer needed

    // Save to cache/module_name.zig (use arena)
    const output_path = try std.fmt.allocPrint(aa, build_dirs.CACHE ++ "/{s}.zig", .{mod_name});
    // output_path allocated by arena - no defer needed

    const file = try std.fs.cwd().createFile(output_path, .{});
    defer file.close();
    try file.writeAll(zig_code);

    std.debug.print("  ✓ Module Zig generated: {s}\n", .{output_path});
}

/// Compile a Jupyter notebook (.ipynb file)
pub fn compileNotebook(allocator: std.mem.Allocator, opts: CompileOptions) !void {
    std.debug.print("Parsing notebook: {s}\n", .{opts.input_file});

    // Use arena for all intermediate allocations
    var arena = std.heap.ArenaAllocator.init(allocator);
    defer arena.deinit();
    const aa = arena.allocator();

    // Parse notebook
    var nb = try notebook.Notebook.parse(opts.input_file, aa);

    std.debug.print("Found {d} cells\n", .{nb.cells.items.len});

    // Count code cells
    var code_cell_count: usize = 0;
    for (nb.cells.items) |*cell| {
        if (std.mem.eql(u8, cell.cell_type, "code")) {
            code_cell_count += 1;
        }
    }

    std.debug.print("Code cells: {d}\n\n", .{code_cell_count});

    // Combine all code cells into a single Python module (for state sharing)
    const combined_source = try nb.combineCodeCells(aa);

    if (combined_source.len == 0) {
        std.debug.print("No code cells found in notebook\n", .{});
        return;
    }

    // Determine output path
    const bin_path = try output.getNotebookOutputPath(aa, opts.input_file, opts.output_file, opts.binary);

    // Compile combined source directly (skip temp file)
    try compilePythonSource(allocator, combined_source, bin_path, opts.mode, opts.binary);

    std.debug.print("✓ Compiled notebook to: {s}\n", .{bin_path});

    // Run if mode is "run"
    if (std.mem.eql(u8, opts.mode, "run")) {
        std.debug.print("\n", .{});
        var child = std.process.Child.init(&[_][]const u8{bin_path}, allocator);
        _ = try child.spawnAndWait();
    }
}

/// Compile Python source code directly (without reading from file)
pub fn compilePythonSource(allocator: std.mem.Allocator, source: []const u8, bin_path: []const u8, mode: []const u8, binary: bool) !void {
    _ = mode; // mode not used for now (no caching for notebooks)
    _ = binary; // binary flag passed but not checked (native codegen always produces binaries)

    // Use arena for all intermediate allocations
    var arena = std.heap.ArenaAllocator.init(allocator);
    defer arena.deinit();
    const aa = arena.allocator();

    // PHASE 1: Lexer - Tokenize source code
    std.debug.print("Lexing...\n", .{});
    var lex = try lexer.Lexer.init(aa, source);

    const tokens = try lex.tokenize();

    // PHASE 2: Parser - Build AST
    std.debug.print("Parsing...\n", .{});
    var p = parser.Parser.init(aa, tokens);
    defer p.deinit();
    const tree = try p.parse();

    // Ensure tree is a module
    if (tree != .module) {
        std.debug.print("Error: Expected module, got {s}\n", .{@tagName(tree)});
        return error.InvalidAST;
    }

    // PHASE 2.5: C Library Import Detection
    var import_ctx = c_interop.ImportContext.init(aa);
    try utils.detectImports(&import_ctx, tree);

    // PHASE 3: Semantic Analysis - Analyze variable lifetimes and mutations
    var semantic_info = semantic_types.SemanticInfo.init(aa);
    _ = try lifetime_analysis.analyzeLifetimes(&semantic_info, tree, 1);

    // PHASE 4: Type Inference - Infer native Zig types
    std.debug.print("Inferring types...\n", .{});
    var type_inferrer = try native_types.TypeInferrer.init(aa);

    // PHASE 4.5: Pre-compile imported modules to register function return types
    const source_file_dir_str = ".";
    const source_file_dir: ?[]const u8 = source_file_dir_str;

    const imports_mod = @import("../codegen/native/main/imports.zig");

    // Create registry to check for runtime modules
    var registry = try import_registry.createDefaultRegistry(aa);
    defer registry.deinit();

    for (tree.module.body) |stmt| {
        if (stmt == .import_stmt) {
            const module_name = stmt.import_stmt.module;

            // Skip builtin modules (stdlib modules with unsupported syntax)
            if (import_resolver.isBuiltinModule(module_name)) {
                continue;
            }

            // Skip runtime modules (they don't need Python compilation)
            if (registry.lookup(module_name)) |info| {
                if (info.strategy == .zig_runtime or info.strategy == .c_library) {
                    continue;
                }
            }

            _ = imports_mod.compileModuleAsStruct(module_name, source_file_dir, aa, &type_inferrer) catch |err| {
                std.debug.print("Warning: Could not pre-compile module {s}: {}\n", .{ module_name, err });
                continue;
            };
        }
    }

    try type_inferrer.analyze(tree.module);

    // PHASE 5: Native Codegen - Generate native Zig code (no PyObject overhead)
    std.debug.print("Generating native Zig code...\n", .{});
    var native_gen = try native_codegen.NativeCodegen.init(aa, &type_inferrer, &semantic_info);
    defer native_gen.deinit();

    // Pass import context to codegen
    native_gen.setImportContext(&import_ctx);

    // Build call graph for unified function analysis
    try native_gen.buildCallGraph(tree.module);

    const zig_code = try native_gen.generate(tree.module);

    // Native codegen always produces binaries (not shared libraries)
    std.debug.print("Compiling to native binary...\n", .{});

    // Get C libraries collected during import processing
    const c_libs = try native_gen.c_libraries.toOwnedSlice(aa);

    try compiler.compileZig(allocator, zig_code, bin_path, c_libs);
}

/// Emit bytecode to stdout (for runtime eval subprocess)
fn emitBytecode(allocator: std.mem.Allocator, source: []const u8) !void {
    var program = try bytecode_codegen.compileSource(allocator, source);
    defer program.deinit();

    const bytes = try program.serialize(allocator);
    defer allocator.free(bytes);

    // Write to stdout using posix
    _ = try std.posix.write(std.posix.STDOUT_FILENO, bytes);
}

/// Fast codegen-only mode - skips import scanning, produces just .zig file
pub fn compileFileCodegenOnly(allocator: std.mem.Allocator, input_file: []const u8) !void {
    var arena = std.heap.ArenaAllocator.init(allocator);
    defer arena.deinit();
    const aa = arena.allocator();

    // Read source file
    const source = try std.fs.cwd().readFileAlloc(aa, input_file, 10 * 1024 * 1024);

    // Lexer
    var lex = try lexer.Lexer.init(aa, source);
    defer lex.deinit();
    const tokens = try lex.tokenize();

    // Parser
    var p = parser.Parser.init(aa, tokens);
    defer p.deinit();
    const tree = try p.parse();

    if (tree != .module) return error.InvalidAST;

    // Skip all import scanning/compilation for speed

    // Semantic analysis (required for codegen)
    var semantic_info = semantic_types.SemanticInfo.init(aa);
    _ = try lifetime_analysis.analyzeLifetimes(&semantic_info, tree, 1);

    // Type inference
    var type_inferrer = try native_types.TypeInferrer.init(aa);
    try type_inferrer.analyze(tree.module);

    // Codegen
    var native_gen = try native_codegen.NativeCodegen.init(aa, &type_inferrer, &semantic_info);
    defer native_gen.deinit();
    try native_gen.buildCallGraph(tree.module);
    const zig_code = try native_gen.generate(tree.module);

    // Write .zig file to cache
    try build_dirs.init();
    const basename = std.fs.path.basename(input_file);
    const stem = if (std.mem.lastIndexOf(u8, basename, ".")) |idx| basename[0..idx] else basename;
    const zig_path = try std.fmt.allocPrint(aa, build_dirs.CACHE ++ "/{s}.zig", .{stem});
    const file = try std.fs.cwd().createFile(zig_path, .{});
    defer file.close();
    try file.writeAll(zig_code);
}

pub fn compileFile(allocator: std.mem.Allocator, opts: CompileOptions) !void {
    // Check if input is a Jupyter notebook
    if (std.mem.endsWith(u8, opts.input_file, ".ipynb")) {
        return try compileNotebook(allocator, opts);
    }

    // Fast codegen-only mode for batch testing
    if (opts.emit_zig_only) {
        return try compileFileCodegenOnly(allocator, opts.input_file);
    }

    // Use arena allocator for all intermediate allocations to avoid leaks on errors
    var arena = std.heap.ArenaAllocator.init(allocator);
    defer arena.deinit();
    const aa = arena.allocator();

    // Read source file
    const source = try std.fs.cwd().readFileAlloc(aa, opts.input_file, 10 * 1024 * 1024); // 10MB max

    // Handle --emit-bytecode: compile to bytecode and output to stdout
    if (opts.emit_bytecode) {
        return try emitBytecode(aa, source);
    }

    // Determine output path
    const bin_path = try output.getFileOutputPath(aa, opts.input_file, opts.output_file, opts.binary);

    // Check if binary is up-to-date using content hash (unless --force)
    const should_compile = opts.force or try cache.shouldRecompile(aa, source, bin_path);

    if (!should_compile) {
        // Output is up-to-date, skip compilation
        if (std.mem.eql(u8, opts.mode, "run")) {
            std.debug.print("\n", .{});
            if (opts.binary) {
                // Run binary directly
                var child = std.process.Child.init(&[_][]const u8{bin_path}, allocator);
                _ = try child.spawnAndWait();
            } else {
                // Load and run shared library
                try utils.runSharedLib(allocator, bin_path);
            }
        } else {
            std.debug.print("✓ Output up-to-date: {s}\n", .{bin_path});
        }
        return;
    }

    // PHASE 0: Initialize debug info writer (if --debug flag set)
    var debug_writer: ?debug_info.DebugInfoWriter = if (opts.debug)
        debug_info.DebugInfoWriter.init(aa, opts.input_file, source)
    else
        null;
    defer if (debug_writer) |*dw| dw.deinit();

    // PHASE 1: Lexer - Tokenize source code
    std.debug.print("Lexing...\n", .{});
    var lex = try lexer.Lexer.init(aa, source);
    defer lex.deinit();

    const tokens = try lex.tokenize();

    // PHASE 2: Parser - Build AST
    std.debug.print("Parsing...\n", .{});
    var p = parser.Parser.init(aa, tokens);
    defer p.deinit();
    const tree = try p.parse();

    // Ensure tree is a module
    if (tree != .module) {
        std.debug.print("Error: Expected module, got {s}\n", .{@tagName(tree)});
        return error.InvalidAST;
    }

    // PHASE 2.1: Collect debug symbols from AST (if --debug flag set)
    if (debug_writer) |*dw| {
        try collectDebugSymbols(dw, tree.module, tokens);
    }

    // PHASE 2.3: Import Dependency Scanning
    std.debug.print("Scanning imports recursively...\n", .{});

    // Create registry to skip zig_runtime/c_library modules during scanning
    var scan_registry = try import_registry.createDefaultRegistry(aa);

    var import_graph = import_scanner.ImportGraph.initWithRegistry(aa, &scan_registry);

    var visited = hashmap_helper.StringHashMap(void).init(aa);

    // Scan all imports recursively
    try import_graph.scanRecursive(opts.input_file, &visited);

    // Check for unresolved (external) imports that need installation
    const unresolved = import_graph.getUnresolved();
    defer aa.free(unresolved);
    if (unresolved.len > 0) {
        std.debug.print("\n\x1b[33m⚠ Missing packages detected:\x1b[0m\n", .{});
        for (unresolved) |pkg_name| {
            std.debug.print("  - {s}\n", .{pkg_name});
        }
        std.debug.print("\nRun \x1b[1mmetal0 install", .{});
        for (unresolved) |pkg_name| {
            std.debug.print(" {s}", .{pkg_name});
        }
        std.debug.print("\x1b[0m to install them.\n\n", .{});
    }

    // Compile each imported module in dependency order
    // Ensure build directories exist
    try build_dirs.init();
    std.debug.print("Compiling {d} imported modules...\n", .{import_graph.modules.count()});
    var iter = import_graph.modules.iterator();
    while (iter.next()) |entry| {
        const module_path = entry.key_ptr.*;
        const module_info = entry.value_ptr.*;

        // Skip the main file itself
        if (std.mem.eql(u8, module_path, opts.input_file)) continue;

        // Compile module using the proper module name
        std.debug.print("  Compiling module: {s} (as {s})\n", .{ module_path, module_info.module_name });
        compileModule(aa, module_path, module_info.module_name) catch |err| {
            std.debug.print("  Warning: Failed to compile module {s}: {}\n", .{ module_path, err });
            continue;
        };
    }

    // PHASE 2.5: C Library Import Detection
    var import_ctx = c_interop.ImportContext.init(aa);
    try utils.detectImports(&import_ctx, tree);

    // PHASE 3: Semantic Analysis - Analyze variable lifetimes and mutations
    var semantic_info = semantic_types.SemanticInfo.init(aa);
    _ = try lifetime_analysis.analyzeLifetimes(&semantic_info, tree, 1);

    // PHASE 4: Type Inference - Infer native Zig types
    std.debug.print("Inferring types...\n", .{});
    var type_inferrer = try native_types.TypeInferrer.init(aa);

    // PHASE 4.5: Pre-compile imported modules to register function return types
    // Derive source file directory from input file path
    const source_file_dir: ?[]const u8 = if (std.fs.path.dirname(opts.input_file)) |dir|
        if (dir.len > 0) dir else "."
    else
        ".";

    const imports_mod = @import("../codegen/native/main/imports.zig");

    // Create registry to check for runtime modules
    var registry2 = try import_registry.createDefaultRegistry(aa);

    // Track modules that failed to compile so we can skip them in codegen
    var failed_modules = hashmap_helper.StringHashMap(void).init(aa);

    for (tree.module.body) |stmt| {
        if (stmt == .import_stmt) {
            const module_name = stmt.import_stmt.module;

            // Skip builtin modules (stdlib modules with unsupported syntax)
            if (import_resolver.isBuiltinModule(module_name)) {
                continue;
            }

            // Skip runtime modules (they don't need Python compilation)
            if (registry2.lookup(module_name)) |info| {
                if (info.strategy == .zig_runtime or info.strategy == .c_library) {
                    continue;
                }
            }

            const compiled = imports_mod.compileModuleAsStruct(module_name, source_file_dir, aa, &type_inferrer) catch |err| {
                std.debug.print("Warning: Could not pre-compile module {s}: {}\n", .{ module_name, err });
                // Track this failed module so codegen can skip it
                try failed_modules.put(module_name, {});
                continue;
            };
            _ = compiled; // Arena will free
        }
    }

    try type_inferrer.analyze(tree.module);

    // PHASE 5: Native Codegen - Generate native Zig code (no PyObject overhead)
    std.debug.print("Generating native Zig code...\n", .{});
    var native_gen = try native_codegen.NativeCodegen.init(aa, &type_inferrer, &semantic_info);
    defer native_gen.deinit();

    // Set mode: shared library (.so) = module mode, binary/run/wasm = script mode
    // WASM needs script mode (with main/_start entry point)
    if (!opts.binary and !opts.wasm and std.mem.eql(u8, opts.mode, "build")) {
        native_gen.mode = .module;
        native_gen.module_name = output.getBaseName(opts.input_file);
    }

    // Pass import context to codegen
    native_gen.setImportContext(&import_ctx);

    // Set source file path for import resolution
    native_gen.setSourceFilePath(opts.input_file);

    // Pass debug writer and tokens to codegen (if --debug flag set)
    if (debug_writer) |*dw| {
        native_gen.setDebugWriter(dw);
        native_gen.setTokens(tokens);
    }

    // Mark failed modules as skipped so functions using them are skipped entirely
    for (failed_modules.keys()) |module_name| {
        try native_gen.markSkippedModule(module_name);
    }

    // Build call graph for unified function analysis (before codegen)
    try native_gen.buildCallGraph(tree.module);

    const zig_code = try native_gen.generate(tree.module);

    // Get C libraries collected during import processing
    const c_libs = try native_gen.c_libraries.toOwnedSlice(aa);

    // Compile to WASM, shared library (.so), or binary
    if (opts.wasm) {
        std.debug.print("Compiling to WebAssembly...\n", .{});
        const wasm_path = try output.getWasmOutputPath(aa, opts.input_file, opts.output_file);
        try compiler.compileWasm(aa, zig_code, wasm_path);
        std.debug.print("✓ Compiled successfully to: {s}\n", .{wasm_path});

        // Generate TypeScript definitions (module-specific)
        const module_name = std.fs.path.stem(opts.input_file);
        const base_path = wasm_path[0 .. wasm_path.len - 5]; // remove .wasm
        const type_defs = try js_glue.generateTypeDefs(aa, tree.module, module_name);
        const dts_path = try std.fmt.allocPrint(aa, "{s}.d.ts", .{base_path});
        const dts_file = try std.fs.cwd().createFile(dts_path, .{});
        defer dts_file.close();
        try dts_file.writeAll(type_defs);
        std.debug.print("✓ Generated TypeScript defs: {s}\n", .{dts_path});
        std.debug.print("  Use with: import {{ load }} from '@metal0/wasm-runtime'\n", .{});

        // WASM cannot be run directly, skip cache and run
        return;
    } else if (!opts.binary and std.mem.eql(u8, opts.mode, "build")) {
        std.debug.print("Compiling to shared library...\n", .{});
        try compiler.compileZigSharedLib(aa, zig_code, bin_path, c_libs);
    } else {
        std.debug.print("Compiling to native binary...\n", .{});
        try compiler.compileZig(aa, zig_code, bin_path, c_libs);
    }

    std.debug.print("✓ Compiled successfully to: {s}\n", .{bin_path});

    // Update cache with new hash
    try cache.updateCache(aa, source, bin_path);

    // Write debug info file (if --debug flag set)
    if (debug_writer) |*dw| {
        const debug_path = try std.fmt.allocPrint(aa, "{s}.metal0.dbg", .{bin_path});
        try dw.writeBinary(debug_path);
        std.debug.print("✓ Debug info written to: {s}\n", .{debug_path});

        // Also write JSON version for human inspection
        const json_path = try std.fmt.allocPrint(aa, "{s}.metal0.dbg.json", .{bin_path});
        var json_buf = std.ArrayList(u8){};
        defer json_buf.deinit(aa);
        try dw.writeJson(json_buf.writer(aa));

        const json_file = try std.fs.cwd().createFile(json_path, .{});
        defer json_file.close();
        try json_file.writeAll(json_buf.items);
        std.debug.print("✓ Debug info (JSON) written to: {s}\n", .{json_path});
    }

    // Run if mode is "run"
    if (std.mem.eql(u8, opts.mode, "run")) {
        std.debug.print("\n", .{});
        // Native codegen always produces binaries
        var child = std.process.Child.init(&[_][]const u8{bin_path}, allocator);
        _ = try child.spawnAndWait();
    }
}

/// Collect debug symbols from AST
/// Walks the AST and records function/class definitions with their source locations
fn collectDebugSymbols(dw: *debug_info.DebugInfoWriter, module: ast.Node.Module, tokens: []const lexer.Token) !void {
    // Find line numbers for each statement by scanning tokens
    // Since AST doesn't store line info, we find tokens by name matching

    // Create a token index for quick name lookup
    var token_lines = std.StringHashMap(u32).init(dw.allocator);
    defer token_lines.deinit();

    // First pass: collect all identifier tokens with their line numbers
    for (tokens) |tok| {
        if (tok.type == .Ident or tok.type == .Def or tok.type == .Class) {
            // Store the line for this identifier
            // Note: this is imperfect but gives us approximate locations
            try token_lines.put(tok.lexeme, @intCast(tok.line));
        }
    }

    // Second pass: walk AST and record symbols
    var stmt_index: u32 = 0;
    for (module.body) |stmt| {
        stmt_index += 1;

        switch (stmt) {
            .function_def => |func| {
                const line = token_lines.get(func.name) orelse 1;
                _ = try dw.addSymbol(func.name, .function, debug_info.SourceLoc.single(line, 1));
            },
            .class_def => |class| {
                const line = token_lines.get(class.name) orelse 1;
                const class_idx = try dw.addSymbol(class.name, .class, debug_info.SourceLoc.single(line, 1));

                // Record methods within class
                try dw.enterScope(class_idx);
                for (class.body) |class_stmt| {
                    if (class_stmt == .function_def) {
                        const method = class_stmt.function_def;
                        const method_line = token_lines.get(method.name) orelse line;
                        _ = try dw.addSymbol(method.name, .method, debug_info.SourceLoc.single(method_line, 1));
                    }
                }
                dw.exitScope();
            },
            .assign => {
                // Record top-level variable assignments
                for (stmt.assign.targets) |target| {
                    if (target == .name) {
                        const line = token_lines.get(target.name.id) orelse 1;
                        _ = try dw.addSymbol(target.name.id, .variable, debug_info.SourceLoc.single(line, 1));
                    }
                }
            },
            .import_stmt => |imp| {
                const line = token_lines.get(imp.module) orelse 1;
                _ = try dw.addSymbol(imp.module, .import, debug_info.SourceLoc.single(line, 1));
            },
            else => {},
        }

        // Record statement location (approximate)
        const approx_line: u32 = @intCast(@min(stmt_index, tokens.len));
        if (approx_line > 0 and approx_line <= tokens.len) {
            try dw.recordStmt(debug_info.SourceLoc.single(@intCast(tokens[approx_line - 1].line), 1));
        }
    }
}
