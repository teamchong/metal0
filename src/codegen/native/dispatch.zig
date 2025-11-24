/// Call routing dispatcher - Routes function/method calls to appropriate handlers
/// Extracted from main.zig to reduce file size
const std = @import("std");
const ast = @import("../../ast.zig");
const NativeCodegen = @import("main.zig").NativeCodegen;
const CodegenError = @import("main.zig").CodegenError;

// Import specialized handlers
const json = @import("json.zig");
const http = @import("http.zig");
const async_mod = @import("async.zig");
const numpy_mod = @import("numpy.zig");
const pandas_mod = @import("pandas.zig");
const builtins = @import("builtins.zig");
const methods = @import("methods.zig");

/// Dispatch call to appropriate handler based on function/method name
/// Returns true if dispatched, false if should use fallback
pub fn dispatchCall(self: *NativeCodegen, call: ast.Node.Call) CodegenError!bool {
    // PRIORITY 1: Check C library mappings first (zero overhead!)
    if (call.func.* == .attribute) {
        const attr = call.func.attribute;
        if (attr.value.* == .name) {
            const module_name = attr.value.name.id;
            const func_name = attr.attr;

            // Check for importlib.import_module() (defensive - import already blocked)
            if (std.mem.eql(u8, module_name, "importlib") and
                std.mem.eql(u8, func_name, "import_module"))
            {
                std.debug.print("\nError: importlib.import_module() not supported in AOT compilation\n", .{});
                std.debug.print("   |\n", .{});
                std.debug.print("   = PyAOT resolves all imports at compile time\n", .{});
                std.debug.print("   = Dynamic runtime module loading not supported\n", .{});
                std.debug.print("   = Suggestion: Use static imports (import json) instead\n", .{});
                return error.OutOfMemory;
            }

            // Build full function name (e.g., "numpy.sum")
            var full_name_buf: [256]u8 = undefined;
            const full_name = std.fmt.bufPrint(
                &full_name_buf,
                "{s}.{s}",
                .{ module_name, func_name },
            ) catch return false;

            // Check if this maps to a C library function
            // Skip numpy - use Agent 2's custom codegen instead (PRIORITY 2 below)
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

            // PRIORITY 2: Fallback to hardcoded handlers

            // JSON module functions
            if (std.mem.eql(u8, module_name, "json")) {
                if (std.mem.eql(u8, func_name, "loads")) {
                    try json.genJsonLoads(self, call.args);
                    return true;
                }
                if (std.mem.eql(u8, func_name, "dumps")) {
                    try json.genJsonDumps(self, call.args);
                    return true;
                }
            }

            // HTTP module functions
            if (std.mem.eql(u8, module_name, "http")) {
                if (std.mem.eql(u8, func_name, "get")) {
                    try http.genHttpGet(self, call.args);
                    return true;
                }
                if (std.mem.eql(u8, func_name, "post")) {
                    try http.genHttpPost(self, call.args);
                    return true;
                }
            }

            // Asyncio module functions
            if (std.mem.eql(u8, module_name, "asyncio")) {
                if (std.mem.eql(u8, func_name, "run")) {
                    try async_mod.genAsyncioRun(self, call.args);
                    return true;
                }
                if (std.mem.eql(u8, func_name, "gather")) {
                    try async_mod.genAsyncioGather(self, call.args);
                    return true;
                }
                if (std.mem.eql(u8, func_name, "create_task")) {
                    try async_mod.genAsyncioCreateTask(self, call.args);
                    return true;
                }
                if (std.mem.eql(u8, func_name, "sleep")) {
                    try async_mod.genAsyncioSleep(self, call.args);
                    return true;
                }
            }

            // NumPy module functions
            if (std.mem.eql(u8, module_name, "numpy") or std.mem.eql(u8, module_name, "np")) {
                if (std.mem.eql(u8, func_name, "array")) {
                    try numpy_mod.genArray(self, call.args);
                    return true;
                }
                if (std.mem.eql(u8, func_name, "dot")) {
                    try numpy_mod.genDot(self, call.args);
                    return true;
                }
                if (std.mem.eql(u8, func_name, "sum")) {
                    try numpy_mod.genSum(self, call.args);
                    return true;
                }
                if (std.mem.eql(u8, func_name, "mean")) {
                    try numpy_mod.genMean(self, call.args);
                    return true;
                }
                if (std.mem.eql(u8, func_name, "transpose")) {
                    try numpy_mod.genTranspose(self, call.args);
                    return true;
                }
                if (std.mem.eql(u8, func_name, "matmul")) {
                    try numpy_mod.genMatmul(self, call.args);
                    return true;
                }
                if (std.mem.eql(u8, func_name, "zeros")) {
                    try numpy_mod.genZeros(self, call.args);
                    return true;
                }
                if (std.mem.eql(u8, func_name, "ones")) {
                    try numpy_mod.genOnes(self, call.args);
                    return true;
                }
            }

            // Pandas module functions
            if (std.mem.eql(u8, module_name, "pandas") or std.mem.eql(u8, module_name, "pd")) {
                if (std.mem.eql(u8, func_name, "DataFrame")) {
                    try pandas_mod.genDataFrame(self, call.args);
                    return true;
                }
            }
        }
    }

    // Handle method calls (obj.method())
    if (call.func.* == .attribute) {
        const method_name = call.func.attribute.attr;

        // String methods
        if (std.mem.eql(u8, method_name, "split")) {
            try methods.genSplit(self, call.func.attribute.value.*, call.args);
            return true;
        }
        if (std.mem.eql(u8, method_name, "upper")) {
            try methods.genUpper(self, call.func.attribute.value.*, call.args);
            return true;
        }
        if (std.mem.eql(u8, method_name, "lower")) {
            try methods.genLower(self, call.func.attribute.value.*, call.args);
            return true;
        }
        if (std.mem.eql(u8, method_name, "strip")) {
            try methods.genStrip(self, call.func.attribute.value.*, call.args);
            return true;
        }
        if (std.mem.eql(u8, method_name, "replace")) {
            try methods.genReplace(self, call.func.attribute.value.*, call.args);
            return true;
        }
        if (std.mem.eql(u8, method_name, "join")) {
            try methods.genJoin(self, call.func.attribute.value.*, call.args);
            return true;
        }
        if (std.mem.eql(u8, method_name, "startswith")) {
            try methods.genStartswith(self, call.func.attribute.value.*, call.args);
            return true;
        }
        if (std.mem.eql(u8, method_name, "endswith")) {
            try methods.genEndswith(self, call.func.attribute.value.*, call.args);
            return true;
        }
        if (std.mem.eql(u8, method_name, "find")) {
            try methods.genFind(self, call.func.attribute.value.*, call.args);
            return true;
        }
        if (std.mem.eql(u8, method_name, "count")) {
            try methods.genCount(self, call.func.attribute.value.*, call.args);
            return true;
        }
        if (std.mem.eql(u8, method_name, "isdigit")) {
            try methods.genIsdigit(self, call.func.attribute.value.*, call.args);
            return true;
        }
        if (std.mem.eql(u8, method_name, "isalpha")) {
            try methods.genIsalpha(self, call.func.attribute.value.*, call.args);
            return true;
        }
        if (std.mem.eql(u8, method_name, "isalnum")) {
            try methods.genIsalnum(self, call.func.attribute.value.*, call.args);
            return true;
        }
        if (std.mem.eql(u8, method_name, "isspace")) {
            try methods.genIsspace(self, call.func.attribute.value.*, call.args);
            return true;
        }
        if (std.mem.eql(u8, method_name, "islower")) {
            try methods.genIslower(self, call.func.attribute.value.*, call.args);
            return true;
        }
        if (std.mem.eql(u8, method_name, "isupper")) {
            try methods.genIsupper(self, call.func.attribute.value.*, call.args);
            return true;
        }

        // List methods
        if (std.mem.eql(u8, method_name, "append")) {
            try methods.genAppend(self, call.func.attribute.value.*, call.args);
            return true;
        }
        if (std.mem.eql(u8, method_name, "pop")) {
            try methods.genPop(self, call.func.attribute.value.*, call.args);
            return true;
        }
        if (std.mem.eql(u8, method_name, "extend")) {
            try methods.genExtend(self, call.func.attribute.value.*, call.args);
            return true;
        }
        if (std.mem.eql(u8, method_name, "insert")) {
            try methods.genInsert(self, call.func.attribute.value.*, call.args);
            return true;
        }
        if (std.mem.eql(u8, method_name, "remove")) {
            try methods.genRemove(self, call.func.attribute.value.*, call.args);
            return true;
        }
        if (std.mem.eql(u8, method_name, "index")) {
            try methods.genIndex(self, call.func.attribute.value.*, call.args);
            return true;
        }
        if (std.mem.eql(u8, method_name, "count")) {
            // Check if it's a list or string - lists use list.genCount, strings use string.genCount
            const obj = call.func.attribute.value.*;
            const is_list = blk: {
                if (obj == .name) {
                    const var_name = obj.name.id;
                    if (self.getSymbolType(var_name)) |var_type| {
                        break :blk switch (var_type) {
                            .list => true,
                            else => false,
                        };
                    }
                }
                break :blk false;
            };

            if (is_list) {
                const genListCount = @import("methods/list.zig").genCount;
                try genListCount(self, call.func.attribute.value.*, call.args);
            } else {
                // Default to string.genCount
                try methods.genCount(self, call.func.attribute.value.*, call.args);
            }
            return true;
        }
        if (std.mem.eql(u8, method_name, "reverse")) {
            try methods.genReverse(self, call.func.attribute.value.*, call.args);
            return true;
        }
        if (std.mem.eql(u8, method_name, "sort")) {
            try methods.genSort(self, call.func.attribute.value.*, call.args);
            return true;
        }
        if (std.mem.eql(u8, method_name, "clear")) {
            try methods.genClear(self, call.func.attribute.value.*, call.args);
            return true;
        }
        if (std.mem.eql(u8, method_name, "copy")) {
            try methods.genCopy(self, call.func.attribute.value.*, call.args);
            return true;
        }

        // Dict methods
        if (std.mem.eql(u8, method_name, "get") and call.args.len > 0) {
            // Only handle dict.get(key) - class methods with no args fall through
            try methods.genGet(self, call.func.attribute.value.*, call.args);
            return true;
        }
        if (std.mem.eql(u8, method_name, "keys")) {
            try methods.genKeys(self, call.func.attribute.value.*, call.args);
            return true;
        }
        if (std.mem.eql(u8, method_name, "values")) {
            try methods.genValues(self, call.func.attribute.value.*, call.args);
            return true;
        }
        if (std.mem.eql(u8, method_name, "items")) {
            try methods.genItems(self, call.func.attribute.value.*, call.args);
            return true;
        }

        // Pandas Column methods (DataFrame column operations)
        // Check if the object is a DataFrame column by looking for subscript on DataFrame
        const is_column_method = blk: {
            const obj = call.func.attribute.value.*;
            break :blk obj == .subscript; // df['col'].method()
        };

        if (is_column_method) {
            if (std.mem.eql(u8, method_name, "sum")) {
                try pandas_mod.genColumnSum(self, call.func.attribute.value.*);
                return true;
            }
            if (std.mem.eql(u8, method_name, "mean")) {
                try pandas_mod.genColumnMean(self, call.func.attribute.value.*);
                return true;
            }
            if (std.mem.eql(u8, method_name, "describe")) {
                try pandas_mod.genColumnDescribe(self, call.func.attribute.value.*);
                return true;
            }
            if (std.mem.eql(u8, method_name, "min")) {
                try pandas_mod.genColumnMin(self, call.func.attribute.value.*);
                return true;
            }
            if (std.mem.eql(u8, method_name, "max")) {
                try pandas_mod.genColumnMax(self, call.func.attribute.value.*);
                return true;
            }
            if (std.mem.eql(u8, method_name, "std")) {
                try pandas_mod.genColumnStd(self, call.func.attribute.value.*);
                return true;
            }
        }
    }

    // Check for built-in functions (len, str, int, float, etc.)
    if (call.func.* == .name) {
        const func_name = call.func.name.id;

        // Type conversion functions
        if (std.mem.eql(u8, func_name, "len")) {
            try builtins.genLen(self, call.args);
            return true;
        }
        if (std.mem.eql(u8, func_name, "str")) {
            try builtins.genStr(self, call.args);
            return true;
        }
        if (std.mem.eql(u8, func_name, "int")) {
            try builtins.genInt(self, call.args);
            return true;
        }
        if (std.mem.eql(u8, func_name, "float")) {
            try builtins.genFloat(self, call.args);
            return true;
        }
        if (std.mem.eql(u8, func_name, "bool")) {
            try builtins.genBool(self, call.args);
            return true;
        }

        // Math functions
        if (std.mem.eql(u8, func_name, "abs")) {
            try builtins.genAbs(self, call.args);
            return true;
        }
        if (std.mem.eql(u8, func_name, "min")) {
            try builtins.genMin(self, call.args);
            return true;
        }
        if (std.mem.eql(u8, func_name, "max")) {
            try builtins.genMax(self, call.args);
            return true;
        }
        if (std.mem.eql(u8, func_name, "sum")) {
            try builtins.genSum(self, call.args);
            return true;
        }
        if (std.mem.eql(u8, func_name, "round")) {
            try builtins.genRound(self, call.args);
            return true;
        }
        if (std.mem.eql(u8, func_name, "pow")) {
            try builtins.genPow(self, call.args);
            return true;
        }

        // Collection functions
        if (std.mem.eql(u8, func_name, "all")) {
            try builtins.genAll(self, call.args);
            return true;
        }
        if (std.mem.eql(u8, func_name, "any")) {
            try builtins.genAny(self, call.args);
            return true;
        }
        if (std.mem.eql(u8, func_name, "sorted")) {
            try builtins.genSorted(self, call.args);
            return true;
        }
        if (std.mem.eql(u8, func_name, "reversed")) {
            try builtins.genReversed(self, call.args);
            return true;
        }
        if (std.mem.eql(u8, func_name, "map")) {
            try builtins.genMap(self, call.args);
            return true;
        }
        if (std.mem.eql(u8, func_name, "filter")) {
            try builtins.genFilter(self, call.args);
            return true;
        }

        // String/char functions
        if (std.mem.eql(u8, func_name, "chr")) {
            try builtins.genChr(self, call.args);
            return true;
        }
        if (std.mem.eql(u8, func_name, "ord")) {
            try builtins.genOrd(self, call.args);
            return true;
        }

        // Type functions
        if (std.mem.eql(u8, func_name, "type")) {
            try builtins.genType(self, call.args);
            return true;
        }
        if (std.mem.eql(u8, func_name, "isinstance")) {
            try builtins.genIsinstance(self, call.args);
            return true;
        }

        // eval() - wire to AST executor
        if (std.mem.eql(u8, func_name, "eval")) {
            try builtins.genEval(self, call.args);
            return true;
        }

        // exec() - similar to eval but no return value
        if (std.mem.eql(u8, func_name, "exec")) {
            try builtins.genExec(self, call.args);
            return true;
        }

        // compile() - compile source code to bytecode
        if (std.mem.eql(u8, func_name, "compile")) {
            try builtins.genCompile(self, call.args);
            return true;
        }

        // Dynamic attribute access
        inline for (.{
            .{ "getattr", builtins.genGetattr },
            .{ "setattr", builtins.genSetattr },
            .{ "hasattr", builtins.genHasattr },
            .{ "vars", builtins.genVars },
            .{ "globals", builtins.genGlobals },
            .{ "locals", builtins.genLocals },
        }) |entry| {
            if (std.mem.eql(u8, func_name, entry[0])) {
                try entry[1](self, call.args);
                return true;
            }
        }

        // __import__() - dynamic module import
        if (std.mem.eql(u8, func_name, "__import__")) {
            try self.output.appendSlice(self.allocator, "try runtime.dynamic_import(allocator, ");
            try self.genExpr(call.args[0]);
            try self.output.appendSlice(self.allocator, ")");
            return true;
        }
    }

    // No dispatch handler found - use fallback
    return false;
}

/// Report user-friendly error for dynamic features not supported in AOT
fn reportDynamicFeatureError(func_name: []const u8) void {
    std.debug.print("\n", .{});
    std.debug.print("Error: {s}() not supported in AOT compilation\n", .{func_name});
    std.debug.print("\n", .{});

    // Emit specific error message based on function
    if (std.mem.eql(u8, func_name, "eval") or std.mem.eql(u8, func_name, "exec") or std.mem.eql(u8, func_name, "compile")) {
        std.debug.print("  PyAOT compiles to native code ahead-of-time.\n", .{});
        std.debug.print("  {s}() requires Python runtime at execution time.\n", .{func_name});
        std.debug.print("\n", .{});
        std.debug.print("  Suggestion: Use compile-time constants or refactor code.\n", .{});
    } else if (std.mem.eql(u8, func_name, "__import__")) {
        std.debug.print("  PyAOT resolves all imports at compile time.\n", .{});
        std.debug.print("  Dynamic runtime module loading not supported.\n", .{});
        std.debug.print("\n", .{});
        std.debug.print("  Suggestion: Use static imports (import module_name).\n", .{});
    }
    std.debug.print("\n", .{});
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
