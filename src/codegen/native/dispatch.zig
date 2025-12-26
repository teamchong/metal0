/// Call routing dispatcher - Routes function/method calls to appropriate handlers
/// MIGRATED TO ZIGBUILDER
/// Extracted from main.zig to reduce file size
const std = @import("std");
const ast = @import("analysis.ast");
const NativeCodegen = @import("main.zig").NativeCodegen;
const CodegenError = @import("main.zig").CodegenError;

// Helper for simple constant output
fn emitConst(self: *NativeCodegen, val: []const u8) CodegenError!void {
    const b = try self.getBuilder();
    try b.write(val);
    const output = b.getBodyAndClear();
    try self.output.appendSlice(self.allocator, output);
}
// Helper for formatted output
fn emitFmtConst(self: *NativeCodegen, comptime fmt: []const u8, args: anytype) CodegenError!void {
    const b = try self.getBuilder();
    try b.writeFmt(fmt, args);
    const output = b.getBodyAndClear();
    try self.output.appendSlice(self.allocator, output);
}


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
                    try emitConst(self,"{}");
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

            // Check if module_name is a from-import that maps to a module class
            // e.g., "from datetime import datetime" -> datetime.now() should dispatch to datetime.datetime.now
            // e.g., "from datetime import date" -> date.today() should dispatch to datetime.date.today
            if (self.local_from_imports.get(module_name)) |actual_module| {
                // Build compound name: actual_module.module_name (e.g., datetime.datetime, datetime.date)
                var compound_buf2: [256]u8 = undefined;
                const compound_name = std.fmt.bufPrint(
                    &compound_buf2,
                    "{s}.{s}",
                    .{ actual_module, module_name },
                ) catch return false;
                if (try module_functions.tryDispatch(self, compound_name, func_name, call)) {
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

            // Check if this is a skipped (unsupported) module - use VM fallback
            if (self.isSkippedModule(module_name)) {
                // Use VM fallback for unsupported modules (drop-in CPython compatibility)
                const core = @import("main/core.zig");
                try core.emitVMFallbackFromAST(self, .{ .call = call });
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
            // Special handling for typing.cast - just emit the second argument
            // cast(Type, value) -> value (identity function)
            if (std.mem.eql(u8, module_name, "typing") and std.mem.eql(u8, func_name, "cast")) {
                if (call.args.len >= 2) {
                    const expressions = @import("expressions.zig");
                    try expressions.genExpr(self, call.args[1]);
                    return true;
                }
            }

            // Check if module is skipped - use VM fallback for drop-in CPython replacement
            if (self.isSkippedModule(module_name)) {
                const core = @import("main/core.zig");
                try core.emitVMFallbackFromAST(self, .{ .call = call });
                return true;
            }

            // Route to module function dispatch
            if (try module_functions.tryDispatch(self, module_name, func_name, call)) {
                return true;
            }
        }

        // Special handling for itertools.product imported via "from itertools import product"
        // This generates inline code instead of calling runtime function because:
        // 1. product() can take variable number of iterables with complex types
        // 2. Runtime function can't handle all type combinations
        if (std.mem.eql(u8, func_name, "product")) {
            // Check if this is from module-level or local imports
            if (self.module_level_from_imports.contains("product") or
                self.local_from_imports.contains("product"))
            {
                const itertools_mod = @import("itertools_mod.zig");
                try itertools_mod.genProduct(self, call.args);
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
    try emitConst(self,"@as(*runtime.PyObject, @ptrCast(c_interop.callModuleFunction(\"");
    try emitConst(self,actual_module_name);
    try emitConst(self,"\", \"");
    try emitConst(self,func_name);
    try emitConst(self,"\", .{");

    // Generate arguments as tuple
    for (call.args, 0..) |arg, i| {
        if (i > 0) try emitConst(self,", ");
        try expressions.genExpr(self, arg);
    }

    try emitConst(self,"}).?))");
}

/// Generate direct C library call (zero PyObject* overhead)
fn generateCLibraryCall(
    self: *NativeCodegen,
    call: ast.Node.Call,
    mapping: *const @import("c_interop").FunctionMapping,
) CodegenError!void {
    // Emit C function call
    try emitConst(self,"c.");
    try emitConst(self,mapping.c_name);
    try emitConst(self,"(");

    // Generate arguments based on mapping
    for (mapping.arg_mappings, 0..) |arg_map, i| {
        if (i > 0) {
            try emitConst(self,", ");
        }

        // Get Python argument
        if (arg_map.python_index >= call.args.len) {
            // Use default value if available
            if (arg_map.default_value) |default| {
                try emitConst(self,default);
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
                try emitConst(self,pp.pointer_path);
            },
            .custom => |code| {
                // Custom conversion code
                try emitConst(self,code);
                try emitConst(self,"(");
                const expressions = @import("expressions.zig");
                try expressions.genExpr(self, py_arg);
                try emitConst(self,")");
            },
            else => {
                // Unsupported conversion - fall back to direct
                const expressions = @import("expressions.zig");
                try expressions.genExpr(self, py_arg);
            },
        }
    }

    try emitConst(self,")");
}
