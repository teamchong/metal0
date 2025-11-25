/// Core compilation functions
const std = @import("std");
const hashmap_helper = @import("../utils/hashmap_helper.zig");
const ast = @import("../ast.zig");
const lexer = @import("../lexer.zig");
const parser = @import("../parser.zig");
const compiler = @import("../compiler.zig");
const native_types = @import("../analysis/native_types.zig");
const semantic_types = @import("../analysis/types.zig");
const lifetime_analysis = @import("../analysis/lifetime.zig");
const native_codegen = @import("../codegen/native/main.zig");
const bytecode_codegen = @import("../codegen/bytecode.zig");
const c_interop = @import("c_interop");
const notebook = @import("../notebook.zig");
const CompileOptions = @import("../main.zig").CompileOptions;
const utils = @import("utils.zig");
const cache = @import("cache.zig");
const import_resolver = @import("../import_resolver.zig");
const import_scanner = @import("../import_scanner.zig");
const import_registry = @import("../codegen/native/import_registry.zig");

/// Get module output path for a compiled .so file
fn getModuleOutputPath(allocator: std.mem.Allocator, module_path: []const u8) ![]const u8 {
    const arch = utils.getArch();
    const platform_dir = try std.fmt.allocPrint(allocator, "build/lib.macosx-11.0-{s}", .{arch});
    defer allocator.free(platform_dir);

    // Create build directory
    std.fs.cwd().makePath(platform_dir) catch |err| {
        if (err != error.PathAlreadyExists) return err;
    };

    // Convert /path/to/module.py -> module
    const basename = std.fs.path.basename(module_path);
    const name_no_ext = if (std.mem.lastIndexOf(u8, basename, ".")) |idx|
        basename[0..idx]
    else
        basename;

    return try std.fmt.allocPrint(
        allocator,
        "{s}/{s}.cpython-312-darwin.so",
        .{ platform_dir, name_no_ext },
    );
}

pub fn compileModule(allocator: std.mem.Allocator, module_path: []const u8, module_name: []const u8) !void {
    _ = module_name; // Not used, inferred from path

    // Read module source
    const source = try std.fs.cwd().readFileAlloc(allocator, module_path, 10 * 1024 * 1024);
    defer allocator.free(source);

    // Get module name from path
    const basename = std.fs.path.basename(module_path);
    const mod_name = if (std.mem.lastIndexOf(u8, basename, ".")) |idx|
        basename[0..idx]
    else
        basename;

    // Generate Zig code for this module
    std.debug.print("  Generating Zig for module: {s}\n", .{module_path});

    // Use existing compilation pipeline
    const lexer_mod = @import("../lexer.zig");
    const parser_mod = @import("../parser.zig");

    var lex = try lexer_mod.Lexer.init(allocator, source);
    defer lex.deinit();
    const tokens = try lex.tokenize();
    defer allocator.free(tokens);

    var p = parser_mod.Parser.init(allocator, tokens);
    const tree = try p.parse();
    defer tree.deinit(allocator);

    // Perform semantic analysis
    const semantic_types_mod = @import("../analysis/types.zig");
    const lifetime_analysis_mod = @import("../analysis/lifetime.zig");
    const native_types_mod = @import("../analysis/native_types.zig");

    var semantic_info = semantic_types_mod.SemanticInfo.init(allocator);
    defer semantic_info.deinit();
    _ = try lifetime_analysis_mod.analyzeLifetimes(&semantic_info, tree, 1);

    var type_inferrer = try native_types_mod.TypeInferrer.init(allocator);
    defer type_inferrer.deinit();
    if (tree == .module) {
        try type_inferrer.analyze(tree.module);
    }

    // Generate Zig code in module mode (top-level exports, no struct wrapper)
    var codegen = try native_codegen.NativeCodegen.init(allocator, &type_inferrer, &semantic_info);
    defer codegen.deinit();

    codegen.mode = .module;
    codegen.module_name = null; // No struct wrapper - export functions at top level

    const zig_code = if (tree == .module)
        try codegen.generate(tree.module)
    else
        return error.InvalidAST;
    defer allocator.free(zig_code);

    // Save to .build/module_name.zig
    const output_path = try std.fmt.allocPrint(allocator, ".build/{s}.zig", .{mod_name});
    defer allocator.free(output_path);

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

    // Create a temporary .py file with combined source
    const basename = std.fs.path.basename(opts.input_file);
    const name_no_ext = if (std.mem.lastIndexOf(u8, basename, ".")) |idx|
        basename[0..idx]
    else
        basename;

    // Determine output path (industry standard: build/lib.{platform}/)
    const bin_path = opts.output_file orelse blk: {
        const arch = utils.getArch();
        const platform_dir = try std.fmt.allocPrint(aa, "build/lib.macosx-11.0-{s}", .{arch});

        // Create build/lib.{platform}/ directory if it doesn't exist
        std.fs.cwd().makePath(platform_dir) catch |err| {
            if (err != error.PathAlreadyExists) return err;
        };

        // Standard naming: module.cpython-{version}-{platform}.so
        const path = if (opts.binary)
            try std.fmt.allocPrint(aa, "{s}/{s}", .{ platform_dir, name_no_ext })
        else
            try std.fmt.allocPrint(aa, "{s}/{s}.cpython-312-darwin.so", .{ platform_dir, name_no_ext });
        break :blk path;
    };

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

    // Pass import context to codegen
    native_gen.setImportContext(&import_ctx);

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

pub fn compileFile(allocator: std.mem.Allocator, opts: CompileOptions) !void {
    // Check if input is a Jupyter notebook
    if (std.mem.endsWith(u8, opts.input_file, ".ipynb")) {
        return try compileNotebook(allocator, opts);
    }

    // Read source file
    const source = try std.fs.cwd().readFileAlloc(allocator, opts.input_file, 10 * 1024 * 1024); // 10MB max
    defer allocator.free(source);

    // Handle --emit-bytecode: compile to bytecode and output to stdout
    if (opts.emit_bytecode) {
        return try emitBytecode(allocator, source);
    }

    // Determine output path
    const bin_path_allocated = opts.output_file == null;
    const bin_path = opts.output_file orelse blk: {
        const basename = std.fs.path.basename(opts.input_file);
        const name_no_ext = if (std.mem.lastIndexOf(u8, basename, ".")) |idx|
            basename[0..idx]
        else
            basename;

        // Create build/lib.{platform}/ directory (industry standard)
        const arch = utils.getArch();
        const platform_dir = try std.fmt.allocPrint(allocator, "build/lib.macosx-11.0-{s}", .{arch});
        defer allocator.free(platform_dir);

        std.fs.cwd().makePath(platform_dir) catch |err| {
            if (err != error.PathAlreadyExists) return err;
        };

        // Standard naming: module.cpython-{version}-{platform}.so
        const path = if (opts.binary)
            try std.fmt.allocPrint(allocator, "{s}/{s}", .{ platform_dir, name_no_ext })
        else
            try std.fmt.allocPrint(allocator, "{s}/{s}.cpython-312-darwin.so", .{ platform_dir, name_no_ext });
        break :blk path;
    };
    defer if (bin_path_allocated) allocator.free(bin_path);

    // Check if binary is up-to-date using content hash (unless --force)
    const should_compile = opts.force or try cache.shouldRecompile(allocator, source, bin_path);

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

    // PHASE 1: Lexer - Tokenize source code
    std.debug.print("Lexing...\n", .{});
    var lex = try lexer.Lexer.init(allocator, source);
    defer lex.deinit();

    const tokens = try lex.tokenize();
    defer allocator.free(tokens);

    // PHASE 2: Parser - Build AST
    std.debug.print("Parsing...\n", .{});
    var p = parser.Parser.init(allocator, tokens);
    const tree = try p.parse();
    defer tree.deinit(allocator);

    // Ensure tree is a module
    if (tree != .module) {
        std.debug.print("Error: Expected module, got {s}\n", .{@tagName(tree)});
        return error.InvalidAST;
    }

    // PHASE 2.3: Import Dependency Scanning
    std.debug.print("Scanning imports recursively...\n", .{});
    var import_graph = import_scanner.ImportGraph.init(allocator);
    defer import_graph.deinit();

    var visited = hashmap_helper.StringHashMap(void).init(allocator);
    defer visited.deinit();

    // Scan all imports recursively
    try import_graph.scanRecursive(opts.input_file, &visited);

    // Compile each imported module in dependency order
    std.debug.print("Compiling {d} imported modules...\n", .{import_graph.modules.count()});
    var iter = import_graph.modules.iterator();
    while (iter.next()) |entry| {
        const module_path = entry.key_ptr.*;

        // Skip the main file itself
        if (std.mem.eql(u8, module_path, opts.input_file)) continue;

        // Compile module
        std.debug.print("  Compiling module: {s}\n", .{module_path});
        compileModule(allocator, module_path, "") catch |err| {
            std.debug.print("  Warning: Failed to compile module {s}: {}\n", .{ module_path, err });
            continue;
        };
    }

    // PHASE 2.5: C Library Import Detection
    var import_ctx = c_interop.ImportContext.init(allocator);
    defer import_ctx.deinit();
    try utils.detectImports(&import_ctx, tree);

    // PHASE 3: Semantic Analysis - Analyze variable lifetimes and mutations
    var semantic_info = semantic_types.SemanticInfo.init(allocator);
    defer semantic_info.deinit();
    _ = try lifetime_analysis.analyzeLifetimes(&semantic_info, tree, 1);

    // PHASE 4: Type Inference - Infer native Zig types
    std.debug.print("Inferring types...\n", .{});
    var type_inferrer = try native_types.TypeInferrer.init(allocator);
    defer type_inferrer.deinit();

    // PHASE 4.5: Pre-compile imported modules to register function return types
    const source_file_dir_str = ".";
    const source_file_dir: ?[]const u8 = source_file_dir_str;

    const imports_mod = @import("../codegen/native/main/imports.zig");

    // Create registry to check for runtime modules
    var registry2 = try import_registry.createDefaultRegistry(allocator);
    defer registry2.deinit();

    for (tree.module.body) |stmt| {
        if (stmt == .import_stmt) {
            const module_name = stmt.import_stmt.module;

            // Skip runtime modules (they don't need Python compilation)
            if (registry2.lookup(module_name)) |info| {
                if (info.strategy == .zig_runtime or info.strategy == .c_library) {
                    continue;
                }
            }

            const compiled = imports_mod.compileModuleAsStruct(module_name, source_file_dir, allocator, &type_inferrer) catch |err| {
                std.debug.print("Warning: Could not pre-compile module {s}: {}\n", .{ module_name, err });
                continue;
            };
            allocator.free(compiled);
        }
    }

    try type_inferrer.analyze(tree.module);

    // PHASE 5: Native Codegen - Generate native Zig code (no PyObject overhead)
    std.debug.print("Generating native Zig code...\n", .{});
    var native_gen = try native_codegen.NativeCodegen.init(allocator, &type_inferrer, &semantic_info);
    defer native_gen.deinit();

    // Set mode: shared library (.so) = module mode, binary/run/wasm = script mode
    // WASM needs script mode (with main/_start entry point)
    if (!opts.binary and !opts.wasm and std.mem.eql(u8, opts.mode, "build")) {
        native_gen.mode = .module;
        // Extract module name from input file
        const basename = std.fs.path.basename(opts.input_file);
        const mod_name = if (std.mem.lastIndexOf(u8, basename, ".")) |idx|
            basename[0..idx]
        else
            basename;
        native_gen.module_name = mod_name;
    }

    // Pass import context to codegen
    native_gen.setImportContext(&import_ctx);

    // Set source file path for import resolution
    native_gen.setSourceFilePath(opts.input_file);

    const zig_code = try native_gen.generate(tree.module);
    defer allocator.free(zig_code);

    // Get C libraries collected during import processing
    const c_libs = try native_gen.c_libraries.toOwnedSlice(allocator);
    defer allocator.free(c_libs);

    // Compile to WASM, shared library (.so), or binary
    if (opts.wasm) {
        std.debug.print("Compiling to WebAssembly...\n", .{});
        // Adjust output path to .wasm extension if not explicitly set
        const wasm_path = if (opts.output_file != null)
            bin_path
        else blk: {
            const basename = std.fs.path.basename(opts.input_file);
            const name_no_ext = if (std.mem.lastIndexOf(u8, basename, ".")) |idx|
                basename[0..idx]
            else
                basename;
            break :blk try std.fmt.allocPrint(allocator, "{s}.wasm", .{name_no_ext});
        };
        defer if (opts.output_file == null) allocator.free(wasm_path);
        try compiler.compileWasm(allocator, zig_code, wasm_path);
        std.debug.print("✓ Compiled successfully to: {s}\n", .{wasm_path});
        // WASM cannot be run directly, skip cache and run
        return;
    } else if (!opts.binary and std.mem.eql(u8, opts.mode, "build")) {
        std.debug.print("Compiling to shared library...\n", .{});
        try compiler.compileZigSharedLib(allocator, zig_code, bin_path, c_libs);
    } else {
        std.debug.print("Compiling to native binary...\n", .{});
        try compiler.compileZig(allocator, zig_code, bin_path, c_libs);
    }

    std.debug.print("✓ Compiled successfully to: {s}\n", .{bin_path});

    // Update cache with new hash
    try cache.updateCache(allocator, source, bin_path);

    // Run if mode is "run"
    if (std.mem.eql(u8, opts.mode, "run")) {
        std.debug.print("\n", .{});
        // Native codegen always produces binaries
        var child = std.process.Child.init(&[_][]const u8{bin_path}, allocator);
        _ = try child.spawnAndWait();
    }
}
