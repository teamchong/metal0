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
const builtins = @import("builtins.zig");
const methods = @import("methods.zig");

/// Dispatch call to appropriate handler based on function/method name
/// Returns true if dispatched, false if should use fallback
pub fn dispatchCall(self: *NativeCodegen, call: ast.Node.Call) CodegenError!bool {
    // Check for module.function() calls (json.loads, http.get, etc.)
    if (call.func.* == .attribute) {
        const attr = call.func.attribute;
        if (attr.value.* == .name) {
            const module_name = attr.value.name.id;
            const func_name = attr.attr;

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
            try methods.genCount(self, call.func.attribute.value.*, call.args);
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
    }

    // No dispatch handler found - use fallback
    return false;
}
