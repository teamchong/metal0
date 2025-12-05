/// WASM Bindings Analysis
///
/// Detects @wasm_import and @wasm_export decorators and generates:
/// 1. Optimized Zig externs (only what user declared)
/// 2. Minimal JS loader (only declared handlers)
/// 3. TypeScript .d.ts definitions
///
/// Usage in Python:
/// ```python
/// from metal0 import wasm_import, wasm_export
///
/// @wasm_import("js")
/// def fetch(url: str) -> str: ...
///
/// @wasm_export
/// def process(data: str) -> list[int]:
///     return [ord(c) for c in data]
/// ```
const std = @import("std");
const ast = @import("../ast/core.zig");

/// Represents a WASM import declaration
pub const WasmImport = struct {
    /// Function name in Python
    name: []const u8,
    /// Import namespace (e.g., "js", "wasi", "env")
    namespace: []const u8,
    /// Parameter types
    params: []const ParamType,
    /// Return type
    return_type: WasmType,
    /// Source line for error messages
    line: u32,
};

/// Represents a WASM export declaration
pub const WasmExport = struct {
    /// Function name in Python (also export name)
    name: []const u8,
    /// Optional custom export name
    export_name: ?[]const u8,
    /// Parameter types
    params: []const ParamType,
    /// Return type
    return_type: WasmType,
    /// Source line for error messages
    line: u32,
};

/// Parameter with name and type
pub const ParamType = struct {
    name: []const u8,
    wasm_type: WasmType,
};

/// Python type mapped to WASM representation
pub const WasmType = enum {
    void,
    int, // i64
    float, // f64
    bool, // i32 (0/1)
    str, // {ptr, len} - UTF-8 in memory
    bytes, // {ptr, len} - raw bytes
    list_int, // {ptr, len} - i64 array
    list_float, // {ptr, len} - f64 array
    list_str, // {ptr, len} - encoded string array
    dict, // {ptr, len} - MessagePack/CBOR encoded
    any, // {ptr, len} - JSON encoded

    /// Get Zig type representation
    pub fn toZigType(self: WasmType) []const u8 {
        return switch (self) {
            .void => "void",
            .int => "i64",
            .float => "f64",
            .bool => "i32",
            .str, .bytes, .list_int, .list_float, .list_str, .dict, .any => "extern struct { ptr: [*]u8, len: usize }",
        };
    }

    /// Get Zig return type (for extern functions)
    pub fn toZigReturnType(self: WasmType) []const u8 {
        return switch (self) {
            .void => "void",
            .int => "i64",
            .float => "f64",
            .bool => "i32",
            .str, .bytes, .list_int, .list_float, .list_str, .dict, .any => "PtrLen",
        };
    }

    /// Get TypeScript type
    pub fn toTsType(self: WasmType) []const u8 {
        return switch (self) {
            .void => "void",
            .int, .float => "number",
            .bool => "boolean",
            .str => "string",
            .bytes => "Uint8Array",
            .list_int => "number[]",
            .list_float => "number[]",
            .list_str => "string[]",
            .dict, .any => "any",
        };
    }

    /// Parse from Python type annotation string
    pub fn fromPythonType(type_str: ?[]const u8) WasmType {
        const t = type_str orelse return .any;

        if (std.mem.eql(u8, t, "int")) return .int;
        if (std.mem.eql(u8, t, "float")) return .float;
        if (std.mem.eql(u8, t, "bool")) return .bool;
        if (std.mem.eql(u8, t, "str")) return .str;
        if (std.mem.eql(u8, t, "bytes")) return .bytes;
        if (std.mem.eql(u8, t, "None")) return .void;

        // Generic types
        if (std.mem.startsWith(u8, t, "list[int]")) return .list_int;
        if (std.mem.startsWith(u8, t, "list[float]")) return .list_float;
        if (std.mem.startsWith(u8, t, "list[str]")) return .list_str;
        if (std.mem.startsWith(u8, t, "list[")) return .list_int; // default
        if (std.mem.startsWith(u8, t, "dict[") or std.mem.eql(u8, t, "dict")) return .dict;

        return .any;
    }
};

/// Analysis result containing all WASM bindings
pub const WasmBindings = struct {
    imports: std.ArrayList(WasmImport),
    exports: std.ArrayList(WasmExport),
    allocator: std.mem.Allocator,

    pub fn init(allocator: std.mem.Allocator) WasmBindings {
        return .{
            .imports = std.ArrayList(WasmImport).init(allocator),
            .exports = std.ArrayList(WasmExport).init(allocator),
            .allocator = allocator,
        };
    }

    pub fn deinit(self: *WasmBindings) void {
        for (self.imports.items) |imp| {
            self.allocator.free(imp.params);
        }
        self.imports.deinit();
        for (self.exports.items) |exp| {
            self.allocator.free(exp.params);
        }
        self.exports.deinit();
    }

    /// Check if any WASM bindings are declared
    pub fn hasBindings(self: *const WasmBindings) bool {
        return self.imports.items.len > 0 or self.exports.items.len > 0;
    }
};

/// Analyze module AST for @wasm_import and @wasm_export decorators
pub fn analyzeModule(allocator: std.mem.Allocator, module: ast.Node.Module) !WasmBindings {
    var bindings = WasmBindings.init(allocator);
    errdefer bindings.deinit();

    for (module.body) |stmt| {
        switch (stmt) {
            .function_def => |func| {
                try analyzeFunction(allocator, &bindings, func);
            },
            else => {},
        }
    }

    return bindings;
}

/// Analyze a function for WASM decorators
fn analyzeFunction(allocator: std.mem.Allocator, bindings: *WasmBindings, func: ast.Node.FunctionDef) !void {
    for (func.decorators) |dec| {
        switch (dec) {
            .call => |call| {
                // @wasm_import("js") - decorator with argument
                if (call.func.* == .name) {
                    const name = call.func.name.id;
                    if (std.mem.eql(u8, name, "wasm_import")) {
                        const namespace = extractNamespace(call) orelse "js";
                        try addImport(allocator, bindings, func, namespace);
                    }
                }
            },
            .name => |name| {
                // @wasm_export - simple decorator
                if (std.mem.eql(u8, name.id, "wasm_export")) {
                    try addExport(allocator, bindings, func, null);
                }
            },
            .attribute => |attr| {
                // Handle metal0.wasm_import style
                if (attr.attr != null) {
                    const attr_name = attr.attr.?;
                    if (std.mem.eql(u8, attr_name, "wasm_import") or std.mem.eql(u8, attr_name, "wasm_export")) {
                        // Will be handled by call case for wasm_import("namespace")
                    }
                }
            },
            else => {},
        }
    }
}

/// Extract namespace from @wasm_import("namespace") call
fn extractNamespace(call: ast.Node.Call) ?[]const u8 {
    if (call.args.len > 0) {
        if (call.args[0] == .constant) {
            const c = call.args[0].constant;
            if (c == .string) {
                return c.string;
            }
        }
    }
    return null;
}

/// Add a WASM import binding
fn addImport(allocator: std.mem.Allocator, bindings: *WasmBindings, func: ast.Node.FunctionDef, namespace: []const u8) !void {
    var params = std.ArrayList(ParamType).init(allocator);
    errdefer params.deinit();

    for (func.args) |arg| {
        try params.append(.{
            .name = arg.name,
            .wasm_type = WasmType.fromPythonType(arg.type_annotation),
        });
    }

    try bindings.imports.append(.{
        .name = func.name,
        .namespace = namespace,
        .params = try params.toOwnedSlice(),
        .return_type = WasmType.fromPythonType(func.return_type),
        .line = 0, // TODO: get from AST
    });
}

/// Add a WASM export binding
fn addExport(allocator: std.mem.Allocator, bindings: *WasmBindings, func: ast.Node.FunctionDef, export_name: ?[]const u8) !void {
    var params = std.ArrayList(ParamType).init(allocator);
    errdefer params.deinit();

    for (func.args) |arg| {
        try params.append(.{
            .name = arg.name,
            .wasm_type = WasmType.fromPythonType(arg.type_annotation),
        });
    }

    try bindings.exports.append(.{
        .name = func.name,
        .export_name = export_name,
        .params = try params.toOwnedSlice(),
        .return_type = WasmType.fromPythonType(func.return_type),
        .line = 0, // TODO: get from AST
    });
}

// ============================================================================
// Code Generation
// ============================================================================

/// Generate Zig extern declarations for all imports
pub fn generateZigExterns(allocator: std.mem.Allocator, bindings: *const WasmBindings) ![]const u8 {
    var output = std.ArrayList(u8).init(allocator);
    errdefer output.deinit();
    const w = output.writer();

    try w.writeAll(
        \\// Auto-generated WASM imports by metal0
        \\// DO NOT EDIT - regenerate with: metal0 --emit-wasm-bindings
        \\
        \\const std = @import("std");
        \\
        \\/// Pointer + length for complex types
        \\pub const PtrLen = extern struct {
        \\    ptr: [*]u8,
        \\    len: usize,
        \\};
        \\
        \\
    );

    // Group imports by namespace
    var namespaces = std.StringHashMap(std.ArrayList(WasmImport)).init(allocator);
    defer {
        var it = namespaces.valueIterator();
        while (it.next()) |list| {
            list.deinit();
        }
        namespaces.deinit();
    }

    for (bindings.imports.items) |imp| {
        var list = namespaces.get(imp.namespace) orelse std.ArrayList(WasmImport).init(allocator);
        try list.append(imp);
        try namespaces.put(imp.namespace, list);
    }

    // Generate extern declarations per namespace
    var ns_it = namespaces.iterator();
    while (ns_it.next()) |entry| {
        const ns = entry.key_ptr.*;
        const imports = entry.value_ptr.*.items;

        try w.print("// Namespace: {s}\n", .{ns});
        try w.print("pub const {s} = struct {{\n", .{ns});

        for (imports) |imp| {
            // extern "namespace" fn name(params) return_type;
            try w.print("    pub extern \"{s}\" fn {s}(", .{ ns, imp.name });

            for (imp.params, 0..) |param, i| {
                if (param.wasm_type == .str or param.wasm_type == .bytes) {
                    // String/bytes: pass as ptr + len
                    try w.print("{s}_ptr: [*]const u8, {s}_len: usize", .{ param.name, param.name });
                } else {
                    try w.print("{s}: {s}", .{ param.name, param.wasm_type.toZigType() });
                }
                if (i < imp.params.len - 1) try w.writeAll(", ");
            }

            try w.print(") {s};\n", .{imp.return_type.toZigReturnType()});
        }

        try w.writeAll("};\n\n");
    }

    // Generate wrapper functions for ergonomic use
    try w.writeAll("// Wrapper functions with Zig-friendly signatures\n");
    for (bindings.imports.items) |imp| {
        try generateZigWrapper(w, imp);
    }

    return output.toOwnedSlice();
}

/// Generate a Zig wrapper function for an import
fn generateZigWrapper(w: anytype, imp: WasmImport) !void {
    // pub fn fetch(url: []const u8) ![]const u8 {
    try w.print("pub fn {s}(", .{imp.name});

    for (imp.params, 0..) |param, i| {
        const zig_type = switch (param.wasm_type) {
            .str, .bytes => "[]const u8",
            .list_int => "[]const i64",
            .list_float => "[]const f64",
            else => param.wasm_type.toZigType(),
        };
        try w.print("{s}: {s}", .{ param.name, zig_type });
        if (i < imp.params.len - 1) try w.writeAll(", ");
    }

    const return_zig = switch (imp.return_type) {
        .void => "void",
        .str => "[]const u8",
        .bytes => "[]const u8",
        .list_int => "[]i64",
        else => imp.return_type.toZigType(),
    };
    try w.print(") {s} {{\n", .{return_zig});

    // Call the extern
    try w.print("    const result = {s}.{s}(", .{ imp.namespace, imp.name });

    for (imp.params, 0..) |param, i| {
        if (param.wasm_type == .str or param.wasm_type == .bytes) {
            try w.print("{s}.ptr, {s}.len", .{ param.name, param.name });
        } else {
            try w.print("{s}", .{param.name});
        }
        if (i < imp.params.len - 1) try w.writeAll(", ");
    }

    try w.writeAll(");\n");

    // Convert result
    switch (imp.return_type) {
        .void => {},
        .str, .bytes => try w.writeAll("    return result.ptr[0..result.len];\n"),
        .int, .float, .bool => try w.writeAll("    return result;\n"),
        else => try w.writeAll("    return result;\n"),
    }

    try w.writeAll("}\n\n");
}

/// Generate minimal JS loader with only declared imports
pub fn generateJsLoader(allocator: std.mem.Allocator, bindings: *const WasmBindings, module_name: []const u8) ![]const u8 {
    var output = std.ArrayList(u8).init(allocator);
    errdefer output.deinit();
    const w = output.writer();

    try w.print(
        \\// Auto-generated WASM loader for {s}
        \\// Only includes handlers for declared @wasm_import functions
        \\
        \\const decoder = new TextDecoder();
        \\const encoder = new TextEncoder();
        \\let memory, alloc, free;
        \\
        \\function allocString(str) {{
        \\  const bytes = encoder.encode(str);
        \\  const ptr = alloc(bytes.length);
        \\  new Uint8Array(memory.buffer, ptr, bytes.length).set(bytes);
        \\  return {{ ptr, len: bytes.length }};
        \\}}
        \\
        \\function readString(ptr, len) {{
        \\  return decoder.decode(new Uint8Array(memory.buffer, ptr, len));
        \\}}
        \\
        \\export async function load(wasmPath) {{
        \\  const imports = {{
        \\
    , .{module_name});

    // Group by namespace
    var seen_ns = std.StringHashMap(void).init(allocator);
    defer seen_ns.deinit();

    for (bindings.imports.items) |imp| {
        if (!seen_ns.contains(imp.namespace)) {
            try seen_ns.put(imp.namespace, {});
            try w.print("    {s}: {{\n", .{imp.namespace});

            // Add all imports for this namespace
            for (bindings.imports.items) |imp2| {
                if (std.mem.eql(u8, imp2.namespace, imp.namespace)) {
                    try generateJsHandler(w, imp2);
                }
            }

            try w.writeAll("    },\n");
        }
    }

    try w.writeAll(
        \\  };
        \\
        \\  const wasmBinary = typeof wasmPath === 'string'
        \\    ? await fetch(wasmPath).then(r => r.arrayBuffer())
        \\    : wasmPath;
        \\
        \\  const { instance } = await WebAssembly.instantiate(wasmBinary, imports);
        \\  memory = instance.exports.memory;
        \\  alloc = instance.exports.alloc;
        \\  free = instance.exports.free;
        \\
        \\  return instance.exports;
        \\}
        \\
    );

    // Generate TypeScript types for exports
    try w.print(
        \\
        \\// TypeScript interface
        \\/**
        \\ * @typedef {{{s}Exports}} Module exports
        \\
    , .{module_name});

    for (bindings.exports.items) |exp| {
        try w.print(" * @property {{function({s}): {s}}} {s}\n", .{
            tsParamList(exp.params),
            exp.return_type.toTsType(),
            exp.name,
        });
    }

    try w.writeAll(" */\n");

    return output.toOwnedSlice();
}

/// Generate a JS handler for an import
fn generateJsHandler(w: anytype, imp: WasmImport) !void {
    // Function signature
    try w.print("      {s}: (", .{imp.name});

    for (imp.params, 0..) |param, i| {
        if (param.wasm_type == .str or param.wasm_type == .bytes) {
            try w.print("{s}_ptr, {s}_len", .{ param.name, param.name });
        } else {
            try w.print("{s}", .{param.name});
        }
        if (i < imp.params.len - 1) try w.writeAll(", ");
    }

    try w.writeAll(") => {\n");

    // Decode string parameters
    for (imp.params) |param| {
        if (param.wasm_type == .str) {
            try w.print("        const {s} = readString({s}_ptr, {s}_len);\n", .{ param.name, param.name, param.name });
        }
    }

    // Generate handler body based on common patterns
    try w.print("        // TODO: Implement {s} handler\n", .{imp.name});

    // Handle return type
    switch (imp.return_type) {
        .void => {},
        .int, .float, .bool => try w.writeAll("        return 0;\n"),
        .str => try w.writeAll("        return allocString('');\n"),
        else => try w.writeAll("        return { ptr: 0, len: 0 };\n"),
    }

    try w.writeAll("      },\n");
}

/// Generate TypeScript definitions
pub fn generateTypeDefs(allocator: std.mem.Allocator, bindings: *const WasmBindings, module_name: []const u8) ![]const u8 {
    var output = std.ArrayList(u8).init(allocator);
    errdefer output.deinit();
    const w = output.writer();

    try w.print(
        \\// Auto-generated TypeScript definitions for {s}
        \\// Generated by metal0
        \\
        \\export interface {s}Exports {{
        \\
    , .{ module_name, toPascalCase(module_name) });

    for (bindings.exports.items) |exp| {
        try w.print("  {s}(", .{exp.name});

        for (exp.params, 0..) |param, i| {
            try w.print("{s}: {s}", .{ param.name, param.wasm_type.toTsType() });
            if (i < exp.params.len - 1) try w.writeAll(", ");
        }

        try w.print("): {s};\n", .{exp.return_type.toTsType()});
    }

    try w.writeAll(
        \\}
        \\
        \\export function load(wasmPath: string | ArrayBuffer): Promise<
    );
    try w.print("{s}Exports>;\n", .{toPascalCase(module_name)});

    return output.toOwnedSlice();
}

fn toPascalCase(name: []const u8) []const u8 {
    // Simple version - just return as-is for now
    // Full impl would capitalize first letter
    return name;
}

fn tsParamList(params: []const ParamType) []const u8 {
    // Simplified - return generic for now
    _ = params;
    return "...args: any[]";
}

// ============================================================================
// Tests
// ============================================================================

test "WasmType.fromPythonType" {
    try std.testing.expectEqual(WasmType.int, WasmType.fromPythonType("int"));
    try std.testing.expectEqual(WasmType.str, WasmType.fromPythonType("str"));
    try std.testing.expectEqual(WasmType.list_int, WasmType.fromPythonType("list[int]"));
    try std.testing.expectEqual(WasmType.void, WasmType.fromPythonType("None"));
    try std.testing.expectEqual(WasmType.any, WasmType.fromPythonType(null));
}

test "WasmType.toZigType" {
    try std.testing.expectEqualStrings("i64", WasmType.int.toZigType());
    try std.testing.expectEqualStrings("f64", WasmType.float.toZigType());
    try std.testing.expectEqualStrings("void", WasmType.void.toZigType());
}
