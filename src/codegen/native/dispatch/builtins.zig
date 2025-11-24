/// Built-in function dispatchers (len, str, int, float, etc.)
const std = @import("std");
const ast = @import("../../../ast.zig");
const NativeCodegen = @import("../main.zig").NativeCodegen;
const CodegenError = @import("../main.zig").CodegenError;

const builtins = @import("../builtins.zig");

/// Try to dispatch built-in function call
/// Returns true if dispatched successfully
pub fn tryDispatch(self: *NativeCodegen, call: ast.Node.Call) CodegenError!bool {
    if (call.func.* != .name) return false;

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

    // eval() - detect comptime vs runtime
    if (std.mem.eql(u8, func_name, "eval")) {
        // Check if argument is a string literal (comptime eval candidate)
        if (call.args.len == 1 and call.args[0] == .constant) {
            const val = call.args[0].constant.value;
            if (val == .string) {
                // String literal - register as comptime eval and generate comptime code
                try builtins.genComptimeEval(self, val.string);
                return true;
            }
        }
        // Runtime eval - use AST executor
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

    return false;
}
