/// Core compilation functions
const std = @import("std");
const ast = @import("../ast.zig");
const lexer = @import("../lexer.zig");
const parser = @import("../parser.zig");
const compiler = @import("../compiler.zig");
const native_types = @import("../analysis/native_types.zig");
const semantic_types = @import("../analysis/types.zig");
const lifetime_analysis = @import("../analysis/lifetime.zig");
const native_codegen = @import("../codegen/native/main.zig");
const c_interop = @import("c_interop");
const notebook = @import("../notebook.zig");
const CompileOptions = @import("../main.zig").CompileOptions;
const utils = @import("utils.zig");
const cache = @import("cache.zig");

pub fn compileModule(allocator: std.mem.Allocator, module_path: []const u8, module_name: []const u8) !void {
    // Stub for now - compile imported modules as separate shared libraries
    _ = allocator;
    _ = module_path;
    _ = module_name;
    // TODO: Implement module compilation
}

/// Compile a Jupyter notebook (.ipynb file)
pub fn compileNotebook(allocator: std.mem.Allocator, opts: CompileOptions) !void {
    std.debug.print("Parsing notebook: {s}\n", .{opts.input_file});

    // Parse notebook
    var nb = try notebook.Notebook.parse(opts.input_file, allocator);
    defer nb.deinit();

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
    const combined_source = try nb.combineCodeCells(allocator);
    defer allocator.free(combined_source);

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

    // Determine output path
    const bin_path_allocated = opts.output_file == null;
    const bin_path = opts.output_file orelse blk: {
        // Create .pyaot/ directory if it doesn't exist
        std.fs.cwd().makeDir(".pyaot") catch |err| {
            if (err != error.PathAlreadyExists) return err;
        };

        const arch = utils.getArch();
        const path = if (opts.binary)
            try std.fmt.allocPrint(allocator, ".pyaot/{s}", .{name_no_ext})
        else
            try std.fmt.allocPrint(allocator, ".pyaot/{s}_{s}.so", .{ name_no_ext, arch });
        break :blk path;
    };
    defer if (bin_path_allocated) allocator.free(bin_path);

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

    // PHASE 1: Lexer - Tokenize source code
    std.debug.print("Lexing...\n", .{});
    var lex = try lexer.Lexer.init(allocator, source);
    defer lex.deinit();

    const tokens = try lex.tokenize();
    defer allocator.free(tokens);

    // PHASE 2: Parser - Build AST
    std.debug.print("Parsing...\n", .{});
    var p = parser.Parser.init(allocator, tokens);
    var tree = try p.parse();
    defer tree.deinit(allocator);

    // Ensure tree is a module
    if (tree != .module) {
        std.debug.print("Error: Expected module, got {s}\n", .{@tagName(tree)});
        return error.InvalidAST;
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

    try type_inferrer.analyze(tree.module);

    // PHASE 5: Native Codegen - Generate native Zig code (no PyObject overhead)
    std.debug.print("Generating native Zig code...\n", .{});
    var native_gen = try native_codegen.NativeCodegen.init(allocator, &type_inferrer, &semantic_info);
    defer native_gen.deinit();

    // Pass import context to codegen
    native_gen.setImportContext(&import_ctx);

    const zig_code = try native_gen.generate(tree.module);
    defer allocator.free(zig_code);

    // Native codegen always produces binaries (not shared libraries)
    std.debug.print("Compiling to native binary...\n", .{});
    try compiler.compileZig(allocator, zig_code, bin_path);
}

pub fn compileFile(allocator: std.mem.Allocator, opts: CompileOptions) !void {
    // Check if input is a Jupyter notebook
    if (std.mem.endsWith(u8, opts.input_file, ".ipynb")) {
        return try compileNotebook(allocator, opts);
    }

    // Read source file
    const source = try std.fs.cwd().readFileAlloc(allocator, opts.input_file, 10 * 1024 * 1024); // 10MB max
    defer allocator.free(source);

    // Determine output path
    const bin_path_allocated = opts.output_file == null;
    const bin_path = opts.output_file orelse blk: {
        const basename = std.fs.path.basename(opts.input_file);
        const name_no_ext = if (std.mem.lastIndexOf(u8, basename, ".")) |idx|
            basename[0..idx]
        else
            basename;

        // Create .pyaot/ directory if it doesn't exist
        std.fs.cwd().makeDir(".pyaot") catch |err| {
            if (err != error.PathAlreadyExists) return err;
        };

        // Generate output filename with architecture
        // Binary: name (or name.exe on Windows)
        // Shared lib: name_x86_64.so (or name_x86_64.dylib on macOS)
        const arch = utils.getArch();
        const path = if (opts.binary)
            try std.fmt.allocPrint(allocator, ".pyaot/{s}", .{name_no_ext})
        else
            try std.fmt.allocPrint(allocator, ".pyaot/{s}_{s}.so", .{ name_no_ext, arch });
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
    var tree = try p.parse();
    defer tree.deinit(allocator);

    // Ensure tree is a module
    if (tree != .module) {
        std.debug.print("Error: Expected module, got {s}\n", .{@tagName(tree)});
        return error.InvalidAST;
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

    try type_inferrer.analyze(tree.module);

    // PHASE 5: Native Codegen - Generate native Zig code (no PyObject overhead)
    std.debug.print("Generating native Zig code...\n", .{});
    var native_gen = try native_codegen.NativeCodegen.init(allocator, &type_inferrer, &semantic_info);
    defer native_gen.deinit();

    // Pass import context to codegen
    native_gen.setImportContext(&import_ctx);

    const zig_code = try native_gen.generate(tree.module);
    defer allocator.free(zig_code);

    // Native codegen always produces binaries (not shared libraries)
    std.debug.print("Compiling to native binary...\n", .{});
    try compiler.compileZig(allocator, zig_code, bin_path);

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
