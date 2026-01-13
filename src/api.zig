/// Programmatic API for schema-aware Python compilation
///
/// This module provides an API for external tools (like LanceQL) to compile
/// Python @logic_table code with external type hints from a schema.
///
/// Usage:
///   const metal0 = @import("metal0");
///
///   // Define schema from Lance file
///   const schema = metal0.SchemaTypeHints{
///       .columns = &.{
///           .{ .name = "amount", .type = .f64 },
///           .{ .name = "days", .type = .i64 },
///           .{ .name = "fraud", .type = .bool },
///       },
///   };
///
///   // Compile with schema hints
///   const result = try metal0.compileWithSchema(allocator, python_source, schema, .{});
///
const std = @import("std");
const builtin = @import("builtin");
const native_types = @import("analysis/native_types.zig");
const lexer = @import("lexer.zig");
const parser = @import("parser.zig");
const compiler = @import("compiler.zig");
const native_codegen = @import("codegen/native/main.zig");
const semantic_types = @import("analysis/types.zig");
const lifetime_analysis = @import("analysis/lifetime.zig");
const c_interop = @import("c_interop");
const utils = @import("main/utils.zig");
const build_dirs = @import("build_dirs.zig");

/// Column type from external schema (e.g., Lance file)
pub const ColumnType = enum {
    i64,
    i32,
    i16,
    i8,
    u64,
    u32,
    u16,
    u8,
    f64,
    f32,
    bool,
    string,
    bytes,
    // Vector types for embeddings
    vec_f32,
    vec_f64,

    /// Convert to native Zig type string for codegen
    pub fn toZigType(self: ColumnType) []const u8 {
        return switch (self) {
            .i64 => "i64",
            .i32 => "i32",
            .i16 => "i16",
            .i8 => "i8",
            .u64 => "u64",
            .u32 => "u32",
            .u16 => "u16",
            .u8 => "u8",
            .f64 => "f64",
            .f32 => "f32",
            .bool => "bool",
            .string => "[]const u8",
            .bytes => "[]const u8",
            .vec_f32 => "[]const f32",
            .vec_f64 => "[]const f64",
        };
    }

    /// Convert to NativeType for type inference
    pub fn toNativeType(self: ColumnType) native_types.NativeType {
        return switch (self) {
            .i64, .i32, .i16, .i8, .u64, .u32, .u16, .u8 => .{ .int = .bounded },
            .f64, .f32 => .float,
            .bool => .bool,
            .string => .{ .string = .static },
            .bytes => .bytes,
            .vec_f32, .vec_f64 => .{ .list = &native_types.NativeType.float },
        };
    }
};

/// Column definition from external schema
pub const ColumnDef = struct {
    name: []const u8,
    type: ColumnType,
};

/// Function parameter type hint
pub const ParamHint = struct {
    name: []const u8,
    type: ColumnType,
};

/// Function signature hint
pub const FunctionHint = struct {
    name: []const u8,
    params: []const ParamHint,
    return_type: ColumnType,
};

/// Schema-based type hints for compilation
/// Passed from external tools (LanceQL) to inform type inference
pub const SchemaTypeHints = struct {
    /// Column types from Lance/Parquet schema
    columns: []const ColumnDef = &.{},

    /// Function signatures (for @logic_table methods)
    functions: []const FunctionHint = &.{},

    /// Class field types
    class_fields: []const ColumnDef = &.{},

    /// Force all types to be concrete (no PyValue fallback)
    force_concrete_types: bool = true,

    /// Get column type by name
    pub fn getColumnType(self: SchemaTypeHints, name: []const u8) ?ColumnType {
        for (self.columns) |col| {
            if (std.mem.eql(u8, col.name, name)) {
                return col.type;
            }
        }
        return null;
    }

    /// Get function signature by name
    pub fn getFunctionHint(self: SchemaTypeHints, name: []const u8) ?FunctionHint {
        for (self.functions) |func| {
            if (std.mem.eql(u8, func.name, name)) {
                return func;
            }
        }
        return null;
    }
};

/// Compilation options for schema-aware compilation
pub const SchemaCompileOptions = struct {
    /// Output format
    output: OutputFormat = .static_library,

    /// Optimization level
    optimize: OptimizeMode = .release_fast,

    /// Target platform
    target: Target = .native,

    /// Enable SIMD vectorization hints
    simd: bool = true,

    /// Inline all functions (for single fused kernel)
    inline_all: bool = true,

    pub const OutputFormat = enum {
        /// Static library (.a) - link into host program
        static_library,
        /// Shared library (.so/.dylib) - load at runtime
        shared_library,
        /// Zig source code - for inspection/debugging
        zig_source,
        /// Object file (.o) - for custom linking
        object,
    };

    pub const OptimizeMode = enum {
        debug,
        release_safe,
        release_fast,
        release_small,
    };

    pub const Target = enum {
        native,
        wasm,
        linux_x64,
        linux_arm64,
        macos_x64,
        macos_arm64,
    };
};

/// Result of schema-aware compilation
pub const CompileResult = struct {
    /// Generated Zig source code
    zig_source: []const u8,

    /// Path to compiled output (if not zig_source output)
    output_path: ?[]const u8,

    /// Exported function names
    exported_functions: []const []const u8,

    /// Any warnings during compilation
    warnings: []const []const u8,

    pub fn deinit(self: *CompileResult, allocator: std.mem.Allocator) void {
        allocator.free(self.zig_source);
        if (self.output_path) |path| {
            allocator.free(path);
        }
        for (self.exported_functions) |name| {
            allocator.free(name);
        }
        allocator.free(self.exported_functions);
        for (self.warnings) |warning| {
            allocator.free(warning);
        }
        allocator.free(self.warnings);
    }
};

/// Compile Python source with external schema type hints
///
/// This is the main entry point for schema-aware compilation.
/// It allows external tools to provide type information that Python
/// source code alone cannot express (e.g., column types from Lance schema).
///
/// Parameters:
///   - allocator: Memory allocator for results
///   - python_source: Python source code (with @logic_table decorators)
///   - schema: Type hints from external schema
///   - options: Compilation options
///
/// Returns:
///   - CompileResult with generated code and/or compiled output
///
pub fn compileWithSchema(
    allocator: std.mem.Allocator,
    python_source: []const u8,
    schema: SchemaTypeHints,
    options: SchemaCompileOptions,
) !CompileResult {
    _ = schema; // Schema hints for future type inference enhancement

    // Use arena for all intermediate allocations
    var arena = std.heap.ArenaAllocator.init(allocator);
    defer arena.deinit();
    const aa = arena.allocator();

    // PHASE 1: Lexer - Tokenize source code
    var lex = try lexer.Lexer.init(aa, python_source);
    const tokens = try lex.tokenize();

    // PHASE 2: Parser - Build AST
    var p = parser.Parser.init(aa, tokens);
    defer p.deinit();
    const tree = try p.parse();

    if (tree != .module) {
        return error.InvalidAST;
    }

    // PHASE 2.5: C Library Import Detection
    var import_ctx = c_interop.ImportContext.init(aa);
    try utils.detectImports(&import_ctx, tree);

    // PHASE 3: Semantic Analysis - Analyze variable lifetimes and mutations
    var semantic_info = semantic_types.SemanticInfo.init(aa);
    _ = try lifetime_analysis.analyzeLifetimes(&semantic_info, tree, 1);

    // PHASE 4: Type Inference
    var type_inferrer = try native_types.TypeInferrer.init(aa);
    try type_inferrer.analyze(tree.module);

    // PHASE 5: Native Codegen - Generate native Zig code
    var native_gen = try native_codegen.NativeCodegen.init(aa, &type_inferrer, &semantic_info, "/tmp/logic_table.py");
    defer native_gen.deinit();

    // Enable @logic_table export wrappers
    native_gen.emit_logic_table_exports = true;
    native_gen.mode = .module;
    native_gen.module_name = null; // No struct wrapper - exports at module level

    // Pass import context to codegen
    native_gen.setImportContext(&import_ctx);

    // Build call graph for unified function analysis
    try native_gen.buildCallGraph(tree.module);

    // Generate Zig code
    const zig_code = try native_gen.generate(tree.module);

    // Copy Zig source to caller's allocator
    const result_source = try allocator.dupe(u8, zig_code);

    // Extract exported function names from generated code
    var exports = std.array_list.Managed([]const u8).init(allocator);
    errdefer {
        for (exports.items) |name| allocator.free(name);
        exports.deinit();
    }
    try extractExportedFunctions(allocator, zig_code, &exports);

    // Compile to output format if requested
    var output_path: ?[]const u8 = null;
    if (options.output == .shared_library) {
        // Generate unique temp path for shared library
        const timestamp = std.time.milliTimestamp();
        const lib_ext = switch (builtin.os.tag) {
            .macos => ".dylib",
            .windows => ".dll",
            else => ".so",
        };
        const lib_path = try std.fmt.allocPrint(aa, "/tmp/logic_table_{d}{s}", .{ timestamp, lib_ext });

        // Initialize build directories
        try build_dirs.init();

        // Get C libraries from codegen
        const c_libs = try native_gen.c_libraries.toOwnedSlice(aa);

        // Compile to shared library
        try compiler.compileZigSharedLib(aa, zig_code, lib_path, c_libs, null);

        // Copy path to caller's allocator
        output_path = try allocator.dupe(u8, lib_path);
    }

    return CompileResult{
        .zig_source = result_source,
        .output_path = output_path,
        .exported_functions = try exports.toOwnedSlice(),
        .warnings = try allocator.alloc([]const u8, 0),
    };
}

/// Extract exported function names from generated Zig code
/// Looks for patterns like: export fn ClassName_methodName(
fn extractExportedFunctions(allocator: std.mem.Allocator, zig_code: []const u8, exports: *std.array_list.Managed([]const u8)) !void {
    const export_marker = "export fn ";
    var pos: usize = 0;

    while (std.mem.indexOfPos(u8, zig_code, pos, export_marker)) |start| {
        const name_start = start + export_marker.len;
        // Find end of function name (opening paren)
        if (std.mem.indexOfPos(u8, zig_code, name_start, "(")) |paren_pos| {
            const name = zig_code[name_start..paren_pos];
            try exports.append(try allocator.dupe(u8, name));
            pos = paren_pos;
        } else {
            break;
        }
    }
}

// Tests
test "ColumnType.toZigType" {
    try std.testing.expectEqualStrings("f64", ColumnType.f64.toZigType());
    try std.testing.expectEqualStrings("i64", ColumnType.i64.toZigType());
    try std.testing.expectEqualStrings("bool", ColumnType.bool.toZigType());
    try std.testing.expectEqualStrings("[]const u8", ColumnType.string.toZigType());
}

test "SchemaTypeHints.getColumnType" {
    const schema = SchemaTypeHints{
        .columns = &.{
            .{ .name = "amount", .type = .f64 },
            .{ .name = "count", .type = .i64 },
        },
    };

    try std.testing.expectEqual(ColumnType.f64, schema.getColumnType("amount").?);
    try std.testing.expectEqual(ColumnType.i64, schema.getColumnType("count").?);
    try std.testing.expectEqual(@as(?ColumnType, null), schema.getColumnType("unknown"));
}
