const std = @import("std");
const core = @import("core.zig");
const NativeCodegen = core.NativeCodegen;
const hashmap_helper = @import("../../../utils/hashmap_helper.zig");

/// Generate from-import symbol re-exports with deduplication
/// For "from json import loads", generates: const loads = json.loads;
pub fn generateFromImports(self: *NativeCodegen) !void {
    // Track generated symbols to avoid duplicates
    var generated_symbols = hashmap_helper.StringHashMap(void).init(self.allocator);
    defer generated_symbols.deinit();

    for (self.from_imports.items) |from_imp| {
        // Check if this is a Tier 1 runtime module (functions need allocator)
        const is_runtime_module = self.import_registry.lookup(from_imp.module) != null and
            (std.mem.eql(u8, from_imp.module, "json") or
            std.mem.eql(u8, from_imp.module, "http") or
            std.mem.eql(u8, from_imp.module, "asyncio"));

        for (from_imp.names, 0..) |name, i| {
            // Get the symbol name (use alias if provided)
            const symbol_name = if (i < from_imp.asnames.len and from_imp.asnames[i] != null)
                from_imp.asnames[i].?
            else
                name;

            // Skip import * for now (complex to implement)
            if (std.mem.eql(u8, name, "*")) {
                std.debug.print("Warning: 'from {s} import *' not supported yet\n", .{from_imp.module});
                continue;
            }

            // Skip if this symbol was already generated
            if (generated_symbols.contains(symbol_name)) {
                continue;
            }

            // Track if this symbol needs allocator (runtime module functions)
            if (is_runtime_module) {
                try self.from_import_needs_allocator.put(symbol_name, {});

                // For json.loads, generate a wrapper function that accepts string literals
                if (std.mem.eql(u8, from_imp.module, "json") and std.mem.eql(u8, name, "loads")) {
                    try self.emit("fn ");
                    try self.emit(symbol_name);
                    try self.emit("(json_str: []const u8, allocator: std.mem.Allocator) !*runtime.PyObject {\n");
                    try self.emit("    const json_str_obj = try runtime.PyString.create(allocator, json_str);\n");
                    try self.emit("    defer runtime.decref(json_str_obj, allocator);\n");
                    try self.emit("    return try runtime.json.loads(json_str_obj, allocator);\n");
                    try self.emit("}\n");
                    try generated_symbols.put(symbol_name, {});
                    continue; // Skip const generation for this one
                }
            }

            // Generate: const symbol_name = module.name;
            try self.emit("const ");
            try self.emit(symbol_name);
            try self.emit(" = ");
            try self.emit(from_imp.module);
            try self.emit(".");
            try self.emit(name);
            try self.emit(";\n");
            try generated_symbols.put(symbol_name, {});
        }
    }

    if (self.from_imports.items.len > 0) {
        try self.emit("\n");
    }
}
