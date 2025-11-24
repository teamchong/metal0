/// Call routing dispatcher - Routes function/method calls to appropriate handlers
/// Extracted from main.zig to reduce file size
const std = @import("std");
const ast = @import("../../ast.zig");
const NativeCodegen = @import("main.zig").NativeCodegen;
const CodegenError = @import("main.zig").CodegenError;

// Import specialized dispatchers
const module_functions = @import("dispatch/module_functions.zig");
const method_calls = @import("dispatch/method_calls.zig");
const builtin_dispatch = @import("dispatch/builtins.zig");

/// Dispatch call to appropriate handler based on function/method name
/// Returns true if dispatched, false if should use fallback
pub fn dispatchCall(self: *NativeCodegen, call: ast.Node.Call) CodegenError!bool {
    // PRIORITY 1: Check C library mappings first (zero overhead!)
    if (call.func.* == .attribute) {
        const attr = call.func.attribute;
        if (attr.value.* == .name) {
            const module_name = attr.value.name.id;
            const func_name = attr.attr;

            // Build full function name (e.g., "numpy.sum")
            var full_name_buf: [256]u8 = undefined;
            const full_name = std.fmt.bufPrint(
                &full_name_buf,
                "{s}.{s}",
                .{ module_name, func_name },
            ) catch return false;

            // Check if this maps to a C library function
            // Skip numpy - use custom codegen instead (PRIORITY 2 below)
            const is_numpy = std.mem.eql(u8, module_name, "numpy") or std.mem.eql(u8, module_name, "np");
            if (!is_numpy) {
                if (self.import_ctx) |ctx| {
                    if (ctx.shouldMapFunction(full_name)) |mapping| {
                        // Generate direct C library call
                        try generateCLibraryCall(self, call, mapping);
                        return true;
                    }
                }
            }

            // PRIORITY 2: Fallback to hardcoded module function handlers
            if (try module_functions.tryDispatch(self, module_name, func_name, call)) {
                return true;
            }
        }
    }

    // Handle method calls (obj.method())
    if (try method_calls.tryDispatch(self, call)) {
        return true;
    }

    // Check for built-in functions (len, str, int, float, etc.)
    if (try builtin_dispatch.tryDispatch(self, call)) {
        return true;
    }

    // No dispatch handler found - use fallback
    return false;
}

/// Generate direct C library call (zero PyObject* overhead)
fn generateCLibraryCall(
    self: *NativeCodegen,
    call: ast.Node.Call,
    mapping: *const @import("c_interop").FunctionMapping,
) CodegenError!void {
    // Emit C function call
    try self.output.appendSlice(self.allocator, "c.");
    try self.output.appendSlice(self.allocator, mapping.c_name);
    try self.output.appendSlice(self.allocator, "(");

    // Generate arguments based on mapping
    for (mapping.arg_mappings, 0..) |arg_map, i| {
        if (i > 0) {
            try self.output.appendSlice(self.allocator, ", ");
        }

        // Get Python argument
        if (arg_map.python_index >= call.args.len) {
            // Use default value if available
            if (arg_map.default_value) |default| {
                try self.output.appendSlice(self.allocator, default);
                continue;
            }
            return error.OutOfMemory; // Missing required argument
        }

        const py_arg = call.args[arg_map.python_index];

        // Apply conversion strategy
        switch (arg_map.conversion) {
            .direct => {
                // Direct pass-through
                const expressions = @import("expressions.zig");
                try expressions.genExpr(self, py_arg);
            },
            .pass_pointer => |pp| {
                // Pass pointer to data (e.g., array.ptr)
                const expressions = @import("expressions.zig");
                try expressions.genExpr(self, py_arg);
                try self.output.appendSlice(self.allocator, pp.pointer_path);
            },
            .custom => |code| {
                // Custom conversion code
                try self.output.appendSlice(self.allocator, code);
                try self.output.appendSlice(self.allocator, "(");
                const expressions = @import("expressions.zig");
                try expressions.genExpr(self, py_arg);
                try self.output.appendSlice(self.allocator, ")");
            },
            else => {
                // Unsupported conversion - fall back to direct
                const expressions = @import("expressions.zig");
                try expressions.genExpr(self, py_arg);
            },
        }
    }

    try self.output.appendSlice(self.allocator, ")");
}
