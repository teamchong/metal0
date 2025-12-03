/// Call routing dispatcher - Routes function/method calls to appropriate handlers
/// Extracted from main.zig to reduce file size
const std = @import("std");
const ast = @import("ast");
const NativeCodegen = @import("main.zig").NativeCodegen;
const CodegenError = @import("main.zig").CodegenError;

// Import specialized dispatchers
const module_functions = @import("dispatch/module_functions.zig");
const method_calls = @import("dispatch/method_calls.zig");
const builtin_dispatch = @import("dispatch/builtins.zig");

const NumbersAbcTypes = std.StaticStringMap(void).initComptime(.{
    .{ "Number", {} }, .{ "Complex", {} }, .{ "Real", {} }, .{ "Rational", {} }, .{ "Integral", {} },
});

/// Dispatch call to appropriate handler based on function/method name
/// Returns true if dispatched, false if should use fallback
pub fn dispatchCall(self: *NativeCodegen, call: ast.Node.Call) CodegenError!bool {
    // PRIORITY 1: Check C library mappings first (zero overhead!)
    if (call.func.* == .attribute) {
        const attr = call.func.attribute;

        // Handle nested attributes: datetime.datetime.now(), datetime.date.today()
        // Structure: attr.attr = "now", attr.value = attribute("datetime", name("datetime"))
        if (attr.value.* == .attribute) {
            const inner_attr = attr.value.attribute;
            if (inner_attr.value.* == .name) {
                const root_module = inner_attr.value.name.id;
                const sub_module = inner_attr.attr;
                const func_name = attr.attr;

                // Handle numbers ABC registration: numbers.Rational.register(cls) -> no-op
                // ABC.register() is a runtime-only concept with no meaning at compile time
                if (std.mem.eql(u8, root_module, "numbers") and std.mem.eql(u8, func_name, "register") and NumbersAbcTypes.has(sub_module)) {
                    try self.emit("{}");
                    return true;
                }

                // Build compound module name: "datetime.datetime" or "datetime.date"
                var compound_buf: [256]u8 = undefined;
                const compound_name = std.fmt.bufPrint(
                    &compound_buf,
                    "{s}.{s}",
                    .{ root_module, sub_module },
                ) catch return false;

                // Try dispatch with compound module name
                if (try module_functions.tryDispatch(self, compound_name, func_name, call)) {
                    return true;
                }
            }
        }

        if (attr.value.* == .name) {
            const module_name = attr.value.name.id;
            const func_name = attr.attr;

            // Build full function name (e.g., "json.loads")
            var full_name_buf: [256]u8 = undefined;
            const full_name = std.fmt.bufPrint(
                &full_name_buf,
                "{s}.{s}",
                .{ module_name, func_name },
            ) catch return false;

            // Check if this maps to a C library function (CPython stdlib only)
            if (self.import_ctx) |ctx| {
                if (ctx.shouldMapFunction(full_name)) |mapping| {
                    // Generate direct C library call
                    try generateCLibraryCall(self, call, mapping);
                    return true;
                }
            }

            // Fallback to module function handlers
            if (try module_functions.tryDispatch(self, module_name, func_name, call)) {
                return true;
            }

            // Check if this is a C extension module (numpy, pandas, etc.)
            if (self.isCExtensionModule(module_name)) {
                // Generate call via Python C API
                try generateCExtensionCall(self, module_name, func_name, call);
                return true;
            }

            // Check if this is a skipped (unsupported) module
            if (self.isSkippedModule(module_name)) {
                // Emit compile error for unsupported third-party module
                try self.emitFmt("@compileError(\"Module '{s}' is not supported. External module not found.\")", .{module_name});
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

    // Check for local from-imports (e.g., from random import getrandbits)
    // These functions were imported locally and need to be routed to module dispatch
    if (call.func.* == .name) {
        const func_name = call.func.name.id;
        if (self.local_from_imports.get(func_name)) |module_name| {
            // Route to module function dispatch
            if (try module_functions.tryDispatch(self, module_name, func_name, call)) {
                return true;
            }
        }
    }

    // No dispatch handler found - use fallback
    return false;
}

/// Generate call to C extension module via Python C API
/// Example: np.array([1, 2, 3]) -> c_interop.callModuleFunction("numpy", "array", .{args}).?
fn generateCExtensionCall(
    self: *NativeCodegen,
    module_alias: []const u8,
    func_name: []const u8,
    call: ast.Node.Call,
) CodegenError!void {
    const expressions = @import("expressions.zig");

    // Resolve alias to actual module name (e.g., "np" -> "numpy")
    const actual_module_name = self.c_extension_modules.get(module_alias) orelse module_alias;

    // Generate: c_interop.callModuleFunction("module_name", "func_name", .{args...}).?
    // Use .? to unwrap optional - if null, it means Python call failed
    try self.emit("@as(*runtime.PyObject, @ptrCast(c_interop.callModuleFunction(\"");
    try self.emit(actual_module_name);
    try self.emit("\", \"");
    try self.emit(func_name);
    try self.emit("\", .{");

    // Generate arguments as tuple
    for (call.args, 0..) |arg, i| {
        if (i > 0) try self.emit(", ");
        try expressions.genExpr(self, arg);
    }

    try self.emit("}).?))");
}

/// Generate direct C library call (zero PyObject* overhead)
fn generateCLibraryCall(
    self: *NativeCodegen,
    call: ast.Node.Call,
    mapping: *const @import("c_interop").FunctionMapping,
) CodegenError!void {
    // Emit C function call
    try self.emit("c.");
    try self.emit(mapping.c_name);
    try self.emit("(");

    // Generate arguments based on mapping
    for (mapping.arg_mappings, 0..) |arg_map, i| {
        if (i > 0) {
            try self.emit(", ");
        }

        // Get Python argument
        if (arg_map.python_index >= call.args.len) {
            // Use default value if available
            if (arg_map.default_value) |default| {
                try self.emit(default);
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
                try self.emit(pp.pointer_path);
            },
            .custom => |code| {
                // Custom conversion code
                try self.emit(code);
                try self.emit("(");
                const expressions = @import("expressions.zig");
                try expressions.genExpr(self, py_arg);
                try self.emit(")");
            },
            else => {
                // Unsupported conversion - fall back to direct
                const expressions = @import("expressions.zig");
                try expressions.genExpr(self, py_arg);
            },
        }
    }

    try self.emit(")");
}
