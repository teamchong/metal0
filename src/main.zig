const std = @import("std");
const ast = @import("ast.zig");
const lexer = @import("lexer.zig");
const parser = @import("parser.zig");
const compiler = @import("compiler.zig");
const native_types = @import("analysis/native_types.zig");
const native_codegen = @import("codegen/native/main.zig");

const CompileOptions = struct {
    input_file: []const u8,
    output_file: ?[]const u8 = null,
    mode: []const u8, // "run" or "build"
    binary: bool = false, // --binary flag
    force: bool = false, // --force/-f flag
};

pub fn main() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    // Parse command line arguments
    const args = try std.process.argsAlloc(allocator);
    defer std.process.argsFree(allocator, args);

    if (args.len < 2) {
        try printUsage();
        return;
    }

    var opts = CompileOptions{
        .input_file = undefined,
        .mode = "run",
    };

    var i: usize = 1;
    var is_build_command = false;

    // Parse command (build/test or direct file)
    if (std.mem.eql(u8, args[1], "build")) {
        is_build_command = true;
        opts.mode = "build";
        i = 2;
    } else if (std.mem.eql(u8, args[1], "test")) {
        // Run pytest for now (bridge to Python)
        std.debug.print("Running tests (bridge to Python)...\n", .{});
        _ = try std.process.Child.run(.{
            .allocator = allocator,
            .argv = &[_][]const u8{ "pytest", "-v" },
        });
        return;
    }

    // Parse flags and input file
    var input_file: ?[]const u8 = null;
    var output_file: ?[]const u8 = null;

    while (i < args.len) : (i += 1) {
        const arg = args[i];

        if (std.mem.eql(u8, arg, "--binary") or std.mem.eql(u8, arg, "-b")) {
            opts.binary = true;
        } else if (std.mem.eql(u8, arg, "--force") or std.mem.eql(u8, arg, "-f")) {
            opts.force = true;
        } else if (std.mem.startsWith(u8, arg, "--")) {
            std.debug.print("Unknown flag: {s}\n", .{arg});
            try printUsage();
            return;
        } else {
            // First non-flag is input file, second is output file
            if (input_file == null) {
                input_file = arg;
            } else if (output_file == null) {
                output_file = arg;
            } else {
                std.debug.print("Too many arguments\n", .{});
                try printUsage();
                return;
            }
        }
    }

    // If no input file and in build mode, build all .py in current directory
    if (input_file == null and is_build_command) {
        try buildDirectory(allocator, ".", opts);
        return;
    }

    if (input_file == null) {
        std.debug.print("Error: Missing input file\n", .{});
        try printUsage();
        return;
    }

    // Check if input is a directory
    const stat = std.fs.cwd().statFile(input_file.?) catch |err| {
        if (err == error.FileNotFound) {
            std.debug.print("Error: File not found: {s}\n", .{input_file.?});
            return;
        }
        return err;
    };

    if (stat.kind == .directory) {
        try buildDirectory(allocator, input_file.?, opts);
        return;
    }

    opts.input_file = input_file.?;
    opts.output_file = output_file;

    try compileFile(allocator, opts);
}

/// Build all .py files in a directory
fn buildDirectory(allocator: std.mem.Allocator, dir_path: []const u8, opts: CompileOptions) !void {
    var dir = try std.fs.cwd().openDir(dir_path, .{ .iterate = true });
    defer dir.close();

    var iter = dir.iterate();
    var file_count: usize = 0;
    var error_count: usize = 0;

    std.debug.print("Building all .py files in {s}/\n\n", .{dir_path});

    while (try iter.next()) |entry| {
        if (entry.kind != .file) continue;

        // Check if file ends with .py
        if (!std.mem.endsWith(u8, entry.name, ".py")) continue;

        // Build full path
        const full_path = try std.fs.path.join(allocator, &[_][]const u8{ dir_path, entry.name });
        defer allocator.free(full_path);

        file_count += 1;
        std.debug.print("=== Building {s} ===\n", .{entry.name});

        var file_opts = opts;
        file_opts.input_file = full_path;

        compileFile(allocator, file_opts) catch |err| {
            std.debug.print("✗ Failed: {s} - {any}\n\n", .{ entry.name, err });
            error_count += 1;
            continue;
        };

        std.debug.print("\n", .{});
    }

    std.debug.print("=== Summary ===\n", .{});
    std.debug.print("Total files: {d}\n", .{file_count});
    std.debug.print("Success: {d}\n", .{file_count - error_count});
    std.debug.print("Failed: {d}\n", .{error_count});
}

/// Get current architecture string (e.g., "x86_64", "arm64")
fn getArch() []const u8 {
    const builtin = @import("builtin");
    return switch (builtin.cpu.arch) {
        .x86_64 => "x86_64",
        .aarch64 => "arm64",
        .arm => "arm",
        .riscv64 => "riscv64",
        else => "unknown",
    };
}

fn compileFile(allocator: std.mem.Allocator, opts: CompileOptions) !void {
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
        const arch = getArch();
        const path = if (opts.binary)
            try std.fmt.allocPrint(allocator, ".pyaot/{s}", .{name_no_ext})
        else
            try std.fmt.allocPrint(allocator, ".pyaot/{s}_{s}.so", .{ name_no_ext, arch });
        break :blk path;
    };
    defer if (bin_path_allocated) allocator.free(bin_path);

    // Check if binary is up-to-date using content hash (unless --force)
    const should_compile = opts.force or try shouldRecompile(allocator, source, bin_path);

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
                try runSharedLib(allocator, bin_path);
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

    // PHASE 3: Type Inference - Infer native Zig types
    std.debug.print("Inferring types...\n", .{});
    var type_inferrer = try native_types.TypeInferrer.init(allocator);
    defer type_inferrer.deinit();

    try type_inferrer.analyze(tree.module);

    // PHASE 4: Native Codegen - Generate native Zig code (no PyObject overhead)
    std.debug.print("Generating native Zig code...\n", .{});
    var native_gen = try native_codegen.NativeCodegen.init(allocator, &type_inferrer);
    defer native_gen.deinit();

    const zig_code = try native_gen.generate(tree.module);
    defer allocator.free(zig_code);

    // Native codegen always produces binaries (not shared libraries)
    std.debug.print("Compiling to native binary...\n", .{});
    try compiler.compileZig(allocator, zig_code, bin_path);

    std.debug.print("✓ Compiled successfully to: {s}\n", .{bin_path});

    // Update cache with new hash
    try updateCache(allocator, source, bin_path);

    // Run if mode is "run"
    if (std.mem.eql(u8, opts.mode, "run")) {
        std.debug.print("\n", .{});
        // Native codegen always produces binaries
        var child = std.process.Child.init(&[_][]const u8{bin_path}, allocator);
        _ = try child.spawnAndWait();
    }
}

/// Load and execute a shared library (.so/.dylib)
fn runSharedLib(allocator: std.mem.Allocator, lib_path: []const u8) !void {
    // Get absolute path for dlopen (need null-terminated string)
    const abs_path = try std.fs.cwd().realpathAlloc(allocator, lib_path);
    defer allocator.free(abs_path);

    // Create null-terminated version for dlopen
    const abs_path_z = try allocator.dupeZ(u8, abs_path);
    defer allocator.free(abs_path_z);

    // Load the shared library (LAZY = deferred binding)
    const handle = std.c.dlopen(abs_path_z.ptr, .{ .LAZY = true }) orelse {
        const err = std.c.dlerror();
        const err_str = if (err) |e| std.mem.span(e) else "unknown error";
        std.debug.print("Failed to load library: {s}\n", .{err_str});
        return error.DlopenFailed;
    };
    defer _ = std.c.dlclose(handle);

    // Find the pyaot_main function
    const pyaot_main = std.c.dlsym(handle, "pyaot_main") orelse {
        const err = std.c.dlerror();
        const err_str = if (err) |e| std.mem.span(e) else "pyaot_main not found";
        std.debug.print("Failed to find pyaot_main: {s}\n", .{err_str});
        return error.DlsymFailed;
    };

    // Cast to function pointer and call
    const main_fn: *const fn () callconv(.c) c_int = @ptrCast(@alignCast(pyaot_main));
    const result = main_fn();

    if (result != 0) {
        std.debug.print("pyaot_main returned non-zero: {d}\n", .{result});
        return error.MainFailed;
    }
}

fn printUsage() !void {
    std.debug.print(
        \\Usage:
        \\  pyaot <file.py>                    # Compile .so and run
        \\  pyaot <file.py> --force            # Force recompile
        \\  pyaot <file.py> --binary           # Compile to binary and run
        \\  pyaot build                        # Build all .py in current directory
        \\  pyaot build <dir/>                 # Build all .py in directory
        \\  pyaot build <file.py>              # Build .so only
        \\  pyaot build <file.py> --binary     # Build standalone binary
        \\  pyaot build <file.py> <out>        # Custom output path
        \\  pyaot build <file.py> -f           # Force rebuild
        \\  pyaot test                         # Run test suite
        \\
        \\Flags:
        \\  --binary, -b  Build standalone binary (default: shared library)
        \\  --force, -f   Force recompile (ignore cache)
        \\
        \\Examples:
        \\  pyaot myapp.py                     # Fast: builds myapp_x86_64.so
        \\  pyaot build                        # Build all .py in current dir
        \\  pyaot build examples/              # Build all .py in examples/
        \\  pyaot build --binary myapp.py      # Deploy: builds myapp binary
        \\
    , .{});
}

/// Compute SHA256 hash of source content
fn computeHash(source: []const u8) [32]u8 {
    var hash: [32]u8 = undefined;
    std.crypto.hash.sha2.Sha256.hash(source, &hash, .{});
    return hash;
}

/// Get cache file path for a binary
fn getCachePath(allocator: std.mem.Allocator, bin_path: []const u8) ![]const u8 {
    // Cache file next to binary: .pyaot/fibonacci.hash
    return try std.fmt.allocPrint(allocator, "{s}.hash", .{bin_path});
}

/// Check if recompilation is needed (compare source hash with cached hash)
fn shouldRecompile(allocator: std.mem.Allocator, source: []const u8, bin_path: []const u8) !bool {
    // Check if binary exists
    std.fs.cwd().access(bin_path, .{}) catch return true; // Binary missing, must compile

    // Compute current source hash
    const current_hash = computeHash(source);

    // Read cached hash
    const cache_path = try getCachePath(allocator, bin_path);
    defer allocator.free(cache_path);

    const cached_hash_hex = std.fs.cwd().readFileAlloc(allocator, cache_path, 1024) catch {
        return true; // Cache missing, must compile
    };
    defer allocator.free(cached_hash_hex);

    // Convert hex string back to bytes
    if (cached_hash_hex.len != 64) return true; // Invalid cache

    var cached_hash: [32]u8 = undefined;
    for (0..32) |i| {
        cached_hash[i] = std.fmt.parseInt(u8, cached_hash_hex[i * 2 .. i * 2 + 2], 16) catch return true;
    }

    // Compare hashes
    return !std.mem.eql(u8, &current_hash, &cached_hash);
}

/// Update cache with new source hash
fn updateCache(allocator: std.mem.Allocator, source: []const u8, bin_path: []const u8) !void {
    const hash = computeHash(source);

    // Convert hash to hex string (manually)
    var hex_buf: [64]u8 = undefined;
    const hex_chars = "0123456789abcdef";
    for (hash, 0..) |byte, i| {
        hex_buf[i * 2] = hex_chars[byte >> 4];
        hex_buf[i * 2 + 1] = hex_chars[byte & 0x0F];
    }

    // Write to cache file
    const cache_path = try getCachePath(allocator, bin_path);
    defer allocator.free(cache_path);

    const file = try std.fs.cwd().createFile(cache_path, .{});
    defer file.close();

    try file.writeAll(&hex_buf);
}
