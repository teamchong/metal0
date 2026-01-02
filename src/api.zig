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
const compile = @import("main/compile.zig");
const native_types = @import("analysis/native_types.zig");

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
    _ = options;

    // Generate type-annotated Python source by injecting schema hints
    const annotated_source = try injectSchemaAnnotations(allocator, python_source, schema);
    defer allocator.free(annotated_source);

    // Use existing compilation pipeline with schema-aware codegen
    var arena = std.heap.ArenaAllocator.init(allocator);
    defer arena.deinit();

    // For now, generate Zig source only (phase 1)
    // TODO: Add full compilation pipeline
    const zig_source = try generateZigWithSchema(arena.allocator(), annotated_source, schema);

    // Copy to caller's allocator
    const result_source = try allocator.dupe(u8, zig_source);

    return CompileResult{
        .zig_source = result_source,
        .output_path = null,
        .exported_functions = try allocator.alloc([]const u8, 0),
        .warnings = try allocator.alloc([]const u8, 0),
    };
}

/// Inject schema type annotations into Python source
fn injectSchemaAnnotations(
    allocator: std.mem.Allocator,
    source: []const u8,
    schema: SchemaTypeHints,
) ![]const u8 {
    // For now, return source unchanged
    // TODO: Parse and inject type annotations based on schema
    _ = schema;
    return try allocator.dupe(u8, source);
}

/// Generate Zig code with schema-aware types
fn generateZigWithSchema(
    allocator: std.mem.Allocator,
    python_source: []const u8,
    schema: SchemaTypeHints,
) ![]const u8 {
    _ = python_source;

    // Generate optimized Zig code with concrete types
    var code = std.ArrayListUnmanaged(u8){};
    const writer = code.writer(allocator);

    try writer.writeAll("// Generated by metal0 with schema hints\n");
    try writer.writeAll("// Schema columns:\n");

    for (schema.columns) |col| {
        try writer.print("//   {s}: {s}\n", .{ col.name, col.type.toZigType() });
    }

    try writer.writeAll("\nconst std = @import(\"std\");\n\n");

    // Generate column accessor struct
    try writer.writeAll("pub const Columns = struct {\n");
    for (schema.columns) |col| {
        try writer.print("    {s}: [*]const {s},\n", .{ col.name, col.type.toZigType() });
    }
    try writer.writeAll("};\n\n");

    // TODO: Generate actual function implementations from Python AST
    try writer.writeAll("// TODO: Generate functions from Python source\n");

    return code.toOwnedSlice(allocator);
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
