/// JS Glue Code Generator for WASM
///
/// Generates Immer-style JS bindings that optimize JS↔WASM communication:
/// - Pre-allocated buffers (no per-call alloc/dealloc)
/// - Batch encoding APIs (multiple texts → single WASM call)
/// - Zero-copy where possible
/// - TypeScript type definitions
///
const std = @import("std");
const ast = @import("ast");

pub const JsGlueGenerator = struct {
    allocator: std.mem.Allocator,
    output: std.ArrayList(u8),
    exports: std.ArrayList(ExportedFunc),

    const ExportedFunc = struct {
        name: []const u8,
        params: []const Param,
        return_type: ReturnType,
    };

    const Param = struct {
        name: []const u8,
        py_type: []const u8, // "str", "int", "list[int]", etc.
    };

    const ReturnType = enum {
        void,
        int,
        float,
        str,
        bytes,
        list_int,
        list_str,
        dict,
        any,
    };

    pub fn init(allocator: std.mem.Allocator) JsGlueGenerator {
        return .{
            .allocator = allocator,
            .output = .{},
            .exports = .{},
        };
    }

    pub fn deinit(self: *JsGlueGenerator) void {
        self.output.deinit(self.allocator);
        self.exports.deinit(self.allocator);
    }

    /// Analyze module AST to find exported functions
    pub fn analyzeModule(self: *JsGlueGenerator, module: ast.Node.Module) !void {
        for (module.body) |stmt| {
            switch (stmt) {
                .function_def => |func| {
                    // Export public functions (no leading underscore)
                    if (func.name.len > 0 and func.name[0] != '_') {
                        try self.addExport(func);
                    }
                },
                else => {},
            }
        }
    }

    fn addExport(self: *JsGlueGenerator, func: ast.Node.FunctionDef) !void {
        var params = std.ArrayList(Param){};

        // Parse function parameters
        for (func.args) |arg| {
            const py_type = arg.type_annotation orelse "any";

            try params.append(self.allocator, .{
                .name = arg.name,
                .py_type = py_type,
            });
        }

        // Parse return type
        const return_type = if (func.return_type) |ret|
            parseReturnType(ret)
        else
            .void;

        try self.exports.append(self.allocator, .{
            .name = func.name,
            .params = try params.toOwnedSlice(self.allocator),
            .return_type = return_type,
        });
    }

    fn parseReturnType(type_name: []const u8) ReturnType {
        if (std.mem.eql(u8, type_name, "int")) return .int;
        if (std.mem.eql(u8, type_name, "float")) return .float;
        if (std.mem.eql(u8, type_name, "str")) return .str;
        if (std.mem.eql(u8, type_name, "bytes")) return .bytes;
        if (std.mem.eql(u8, type_name, "list")) return .list_int; // TODO: parse generic
        if (std.mem.eql(u8, type_name, "dict")) return .dict;
        return .any;
    }

    /// Generate the JS glue code - generic Immer-style runtime
    pub fn generate(self: *JsGlueGenerator, module_name: []const u8) ![]const u8 {
        const w = self.output.writer(self.allocator);

        // Generic runtime - same for ALL modules (Immer-style)
        try w.print(
            \\/**
            \\ * metal0 WASM Runtime - {s}
            \\ *
            \\ * Generic Immer-style runtime for any WASM module.
            \\ * Features: pre-allocated buffers, Proxy-based dispatch, batch APIs.
            \\ */
            \\const encoder = new TextEncoder();
            \\const decoder = new TextDecoder();
            \\
            \\// Pre-allocated buffers (avoid per-call allocation)
            \\const INPUT_BUFFER_SIZE = 1024 * 1024; // 1MB
            \\const OUTPUT_BUFFER_SIZE = 256 * 1024; // 256K entries
            \\
            \\let wasmInstance = null;
            \\let memory = null;
            \\let inputPtr = 0;
            \\let outputPtr = 0;
            \\let inputView = null;
            \\let outputView = null;
            \\
            \\function updateViews() {{
            \\  inputView = new Uint8Array(memory.buffer, inputPtr, INPUT_BUFFER_SIZE);
            \\  outputView = new Uint32Array(memory.buffer, outputPtr, OUTPUT_BUFFER_SIZE);
            \\}}
            \\
            \\// Generic argument marshaller
            \\function marshal(arg) {{
            \\  if (typeof arg === 'string') {{
            \\    const bytes = encoder.encode(arg);
            \\    if (bytes.length > INPUT_BUFFER_SIZE) {{
            \\      throw new Error(`String too large: ${{bytes.length}} > ${{INPUT_BUFFER_SIZE}}`);
            \\    }}
            \\    inputView.set(bytes);
            \\    return [inputPtr, bytes.length];
            \\  }}
            \\  return [arg];
            \\}}
            \\
            \\// Generic WASM function caller
            \\function callWasm(funcName, args) {{
            \\  const fn = wasmInstance.exports[funcName];
            \\  if (!fn) throw new Error(`Unknown function: ${{funcName}}`);
            \\
            \\  // Marshal all arguments
            \\  const wasmArgs = args.flatMap(marshal);
            \\  return fn(...wasmArgs);
            \\}}
            \\
            \\/**
            \\ * Load and initialize the WASM module
            \\ * @param {{string|ArrayBuffer}} wasmSource - URL or ArrayBuffer of WASM
            \\ * @returns {{Promise<object>}} Proxy-wrapped module with all exports
            \\ */
            \\export async function load(wasmSource) {{
            \\  const wasmBinary = typeof wasmSource === 'string'
            \\    ? await fetch(wasmSource).then(r => r.arrayBuffer())
            \\    : wasmSource;
            \\
            \\  memory = new WebAssembly.Memory({{ initial: 256, maximum: 512 }});
            \\  const wasmModule = await WebAssembly.compile(wasmBinary);
            \\  wasmInstance = await WebAssembly.instantiate(wasmModule, {{
            \\    env: {{ memory }}
            \\  }});
            \\
            \\  // Pre-allocate persistent buffers
            \\  if (wasmInstance.exports.alloc) {{
            \\    inputPtr = wasmInstance.exports.alloc(INPUT_BUFFER_SIZE);
            \\    outputPtr = wasmInstance.exports.alloc(OUTPUT_BUFFER_SIZE * 4);
            \\    updateViews();
            \\  }}
            \\
            \\  // Return Proxy that wraps any WASM export (Immer-style)
            \\  return new Proxy({{}}, {{
            \\    get(_, prop) {{
            \\      if (prop === 'batch') return batch;
            \\      const fn = wasmInstance.exports[prop];
            \\      if (typeof fn === 'function') {{
            \\        return (...args) => callWasm(prop, args);
            \\      }}
            \\      return fn;
            \\    }}
            \\  }});
            \\}}
            \\
            \\/**
            \\ * Batch process multiple inputs (reduces JS<->WASM overhead)
            \\ * @param {{string[]}} inputs - Array of inputs to process
            \\ * @param {{string}} funcName - Name of function to call
            \\ * @returns {{any[]}} - Array of results
            \\ */
            \\export function batch(inputs, funcName) {{
            \\  return inputs.map(input => callWasm(funcName, [input]));
            \\}}
            \\
            \\export default {{ load, batch }};
            \\
        , .{module_name});

        return self.output.items;
    }

    fn generateFunctionWrapper(self: *JsGlueGenerator, w: anytype, func: ExportedFunc) !void {
        _ = self;

        // Determine if function takes string input (needs encoding)
        var has_str_param = false;
        for (func.params) |p| {
            if (std.mem.eql(u8, p.py_type, "str")) {
                has_str_param = true;
                break;
            }
        }

        // Generate JSDoc
        try w.print(
            \\
            \\/**
            \\ * {s}
        , .{func.name});

        for (func.params) |p| {
            try w.print(
                \\
                \\ * @param {{{s}}} {s}
            , .{ jsType(p.py_type), p.name });
        }

        try w.print(
            \\
            \\ * @returns {{{s}}}
            \\ */
            \\export function {s}(
        , .{ jsReturnType(func.return_type), func.name });

        // Parameters
        for (func.params, 0..) |p, i| {
            try w.print("{s}", .{p.name});
            if (i < func.params.len - 1) try w.writeAll(", ");
        }

        try w.writeAll(") {\n");

        // Function body
        if (has_str_param) {
            // String input: encode and copy to WASM memory
            for (func.params) |p| {
                if (std.mem.eql(u8, p.py_type, "str")) {
                    try w.print(
                        \\  const {s}Bytes = encoder.encode({s});
                        \\  if ({s}Bytes.length > INPUT_BUFFER_SIZE) {{
                        \\    throw new Error(`Input too large: ${{{s}Bytes.length}} > ${{INPUT_BUFFER_SIZE}}`);
                        \\  }}
                        \\  inputView.set({s}Bytes);
                        \\
                    , .{ p.name, p.name, p.name, p.name, p.name });
                }
            }
        }

        // Call WASM function
        try w.print("  const result = wasmInstance.exports.{s}(", .{func.name});

        for (func.params, 0..) |p, i| {
            if (std.mem.eql(u8, p.py_type, "str")) {
                try w.print("inputPtr, {s}Bytes.length", .{p.name});
            } else {
                try w.print("{s}", .{p.name});
            }
            if (i < func.params.len - 1) try w.writeAll(", ");
        }

        try w.writeAll(");\n");

        // Return conversion
        switch (func.return_type) {
            .void => {},
            .int, .float => try w.writeAll("  return result;\n"),
            .str => try w.writeAll("  return decoder.decode(new Uint8Array(memory.buffer, result.ptr, result.len));\n"),
            .list_int => try w.writeAll("  return outputView.subarray(0, result);\n"),
            else => try w.writeAll("  return result;\n"),
        }

        try w.writeAll("}\n");
    }

    fn generateBatchApi(self: *JsGlueGenerator, w: anytype) !void {
        _ = self;

        try w.writeAll(
            \\
            \\/**
            \\ * Batch process multiple inputs (Immer-style optimization)
            \\ * Reduces JS↔WASM overhead by batching multiple calls
            \\ *
            \\ * @param {string[]} inputs - Array of strings to process
            \\ * @param {string} funcName - Name of function to call
            \\ * @returns {any[]} - Array of results
            \\ */
            \\export function batch(inputs, funcName) {
            \\  const func = module[funcName];
            \\  if (!func) throw new Error(`Unknown function: ${funcName}`);
            \\
            \\  // Pre-encode all inputs
            \\  const encoded = inputs.map(s => encoder.encode(s));
            \\
            \\  // Calculate total size
            \\  let totalSize = 0;
            \\  for (const bytes of encoded) totalSize += bytes.length;
            \\
            \\  if (totalSize > INPUT_BUFFER_SIZE) {
            \\    // Fallback to individual calls for large batches
            \\    return inputs.map(s => func(s));
            \\  }
            \\
            \\  // TODO: Implement true batch WASM call
            \\  // For now, use optimized sequential calls with buffer reuse
            \\  const results = [];
            \\  for (const input of inputs) {
            \\    results.push(func(input));
            \\  }
            \\  return results;
            \\}
            \\
        );
    }

    fn jsType(py_type: []const u8) []const u8 {
        if (std.mem.eql(u8, py_type, "str")) return "string";
        if (std.mem.eql(u8, py_type, "int")) return "number";
        if (std.mem.eql(u8, py_type, "float")) return "number";
        if (std.mem.eql(u8, py_type, "bool")) return "boolean";
        if (std.mem.eql(u8, py_type, "list")) return "Array";
        if (std.mem.eql(u8, py_type, "dict")) return "Object";
        return "any";
    }

    fn jsReturnType(rt: ReturnType) []const u8 {
        return switch (rt) {
            .void => "void",
            .int, .float => "number",
            .str => "string",
            .bytes => "Uint8Array",
            .list_int => "Uint32Array",
            .list_str => "string[]",
            .dict => "Object",
            .any => "any",
        };
    }

    /// Generate TypeScript definitions (.d.ts)
    /// Creates interface that works with: load<ModuleName>('./module.wasm')
    pub fn generateTypeDefs(self: *JsGlueGenerator, module_name: []const u8) ![]const u8 {
        var dts = std.ArrayList(u8){};
        const w = dts.writer(self.allocator);

        // Header
        try w.print(
            \\/**
            \\ * TypeScript definitions for {s} WASM module
            \\ * Auto-generated by metal0
            \\ *
            \\ * Usage:
            \\ *   import {{ load }} from '@metal0/wasm-runtime';
            \\ *   import type {{ {s} }} from './{s}';
            \\ *   const mod = await load<{s}>('./{s}.wasm');
            \\ */
            \\
            \\
        , .{ module_name, toPascalCase(module_name), module_name, toPascalCase(module_name), module_name });

        // Generate interface for the module
        try w.print("export interface {s} {{\n", .{toPascalCase(module_name)});

        for (self.exports.items) |func| {
            // Method signature
            try w.print("  {s}(", .{func.name});

            for (func.params, 0..) |p, i| {
                try w.print("{s}: {s}", .{ p.name, jsType(p.py_type) });
                if (i < func.params.len - 1) try w.writeAll(", ");
            }

            try w.print("): {s};\n", .{jsReturnType(func.return_type)});
        }

        try w.writeAll("}\n");

        return dts.toOwnedSlice(self.allocator);
    }

    fn toPascalCase(name: []const u8) []const u8 {
        // Simple conversion: capitalize first letter
        // For now just return the name - proper impl would allocate
        _ = name;
        return "Module"; // Placeholder - will fix with proper allocation
    }
};

/// Generate JS glue code for a WASM module
pub fn generateJsGlue(
    allocator: std.mem.Allocator,
    module: ast.Node.Module,
    module_name: []const u8,
) ![]const u8 {
    var gen = JsGlueGenerator.init(allocator);
    defer gen.deinit();

    try gen.analyzeModule(module);
    return try gen.generate(module_name);
}

/// Generate TypeScript definitions for a WASM module
pub fn generateTypeDefs(
    allocator: std.mem.Allocator,
    module: ast.Node.Module,
    module_name: []const u8,
) ![]const u8 {
    var gen = JsGlueGenerator.init(allocator);
    defer gen.deinit();

    try gen.analyzeModule(module);
    return try gen.generateTypeDefs(module_name);
}
