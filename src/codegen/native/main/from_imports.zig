const std = @import("std");
const core = @import("core.zig");
const NativeCodegen = core.NativeCodegen;
const hashmap_helper = @import("hashmap_helper");
const import_resolver = @import("../../../import_resolver.zig");
const zig_keywords = @import("zig_keywords");

/// Generate from-import symbol re-exports with deduplication
/// For "from json import loads", generates: const loads = json.loads;
pub fn generateFromImports(self: *NativeCodegen) !void {
    // Track generated symbols to avoid duplicates
    var generated_symbols = hashmap_helper.StringHashMap(void).init(self.allocator);
    defer generated_symbols.deinit();

    for (self.from_imports.items) |from_imp| {
        // Skip relative imports (starting with .) - these are internal package imports
        // that don't make sense in standalone compiled modules
        if (from_imp.module.len > 0 and from_imp.module[0] == '.') {
            continue;
        }

        // Skip builtin modules (they're not compiled, so can't reference them)
        if (import_resolver.isBuiltinModule(from_imp.module)) {
            continue;
        }

        // Handle inline-only modules (no zig_import, functions are generated inline)
        // These modules don't have a struct to reference - their functions are
        // directly generated at call sites via dispatch (e.g., from decimal import Decimal)
        if (self.import_registry.lookup(from_imp.module)) |info| {
            if (info.zig_import == null) {
                // Module is inline-only - register symbols for dispatch routing
                // This allows calls like Decimal(...) to be routed to decimal.Decimal dispatch
                for (from_imp.names, 0..) |name, i| {
                    // Skip import * for now
                    if (std.mem.eql(u8, name, "*")) continue;

                    const symbol_name = if (i < from_imp.asnames.len and from_imp.asnames[i] != null)
                        from_imp.asnames[i].?
                    else
                        name;

                    try self.local_from_imports.put(symbol_name, from_imp.module);
                }
                continue;
            }
        } else {
            // Module not in registry - mark all imported symbols as skipped
            // so functions that reference them can be detected and skipped
            for (from_imp.names) |name| {
                // Skip import * for now
                if (!std.mem.eql(u8, name, "*")) {
                    try self.skipped_modules.put(name, {});
                }
            }
            continue; // Skip from-import generation
        }

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
                    try self.emit("    const json_str_obj = try runtime.PyString.create(__global_allocator, json_str);\n");
                    try self.emit("    defer runtime.decref(json_str_obj, allocator);\n");
                    try self.emit("    return try runtime.json.loads(json_str_obj, allocator);\n");
                    try self.emit("}\n");
                    try generated_symbols.put(symbol_name, {});
                    continue; // Skip const generation for this one
                }
            }

            // Generate: const symbol_name = module.name;
            // Special case: if symbol_name == module name (e.g., "from time import time"),
            // we need to use the full path (e.g., runtime.time.time) to avoid duplicate
            // const declarations since PHASE 3.7 already emits "const time = runtime.time;"
            const same_as_module = std.mem.eql(u8, symbol_name, from_imp.module);

            try self.emit("const ");
            try zig_keywords.writeEscapedIdent(self.output.writer(self.allocator), symbol_name);
            try self.emit(" = ");

            if (same_as_module) {
                // Use full path from registry to avoid referencing the duplicate const
                if (self.import_registry.lookup(from_imp.module)) |info| {
                    if (info.zig_import) |zig_import| {
                        try self.emit(zig_import);
                        try self.emit(".");
                        try self.emit(name);
                    } else {
                        // Fallback: use module name (will still have duplicate issue but rare case)
                        try zig_keywords.writeEscapedDottedIdent(self.output.writer(self.allocator), from_imp.module);
                        try self.emit(".");
                        try self.emit(name);
                    }
                } else {
                    // Module not in registry - use module name
                    try zig_keywords.writeEscapedDottedIdent(self.output.writer(self.allocator), from_imp.module);
                    try self.emit(".");
                    try self.emit(name);
                }
            } else {
                // Normal case: use module const reference
                try zig_keywords.writeEscapedDottedIdent(self.output.writer(self.allocator), from_imp.module);
                try self.emit(".");
                try self.emit(name);
            }
            try self.emit(";\n");
            try generated_symbols.put(symbol_name, {});
        }
    }

    if (self.from_imports.items.len > 0) {
        try self.emit("\n");
    }
}
