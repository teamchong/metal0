/// Module function dispatchers (json, http, asyncio, numpy, pandas)
const std = @import("std");
const ast = @import("../../../ast.zig");
const NativeCodegen = @import("../main.zig").NativeCodegen;
const CodegenError = @import("../main.zig").CodegenError;

// Import specialized handlers
const json = @import("../json.zig");
const http = @import("../http.zig");
const async_mod = @import("../async.zig");
const numpy_mod = @import("../numpy.zig");
const pandas_mod = @import("../pandas.zig");

/// Try to dispatch module function call (e.g., json.loads, numpy.array)
/// Returns true if dispatched successfully
pub fn tryDispatch(self: *NativeCodegen, module_name: []const u8, func_name: []const u8, call: ast.Node.Call) CodegenError!bool {
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
        if (std.mem.eql(u8, func_name, "Queue")) {
            try async_mod.genAsyncioQueue(self, call.args);
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

    return false;
}
