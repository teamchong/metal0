/// Built-in function dispatchers (len, str, int, float, etc.)
const std = @import("std");
const ast = @import("../../../ast.zig");
const NativeCodegen = @import("../main.zig").NativeCodegen;
const CodegenError = @import("../main.zig").CodegenError;

const builtins = @import("../builtins.zig");

/// Handler function type for builtin dispatchers
const BuiltinHandler = *const fn (*NativeCodegen, []ast.Node) CodegenError!void;

/// All builtin functions mapped to their handlers (O(1) lookup)
const BuiltinMap = std.StaticStringMap(BuiltinHandler).initComptime(.{
    // Type conversion
    .{ "len", builtins.genLen },
    .{ "str", builtins.genStr },
    .{ "repr", builtins.genRepr },
    .{ "int", builtins.genInt },
    .{ "float", builtins.genFloat },
    .{ "bool", builtins.genBool },
    // Math
    .{ "abs", builtins.genAbs },
    .{ "min", builtins.genMin },
    .{ "max", builtins.genMax },
    .{ "sum", builtins.genSum },
    .{ "round", builtins.genRound },
    .{ "pow", builtins.genPow },
    .{ "divmod", builtins.genDivmod },
    // Collections
    .{ "all", builtins.genAll },
    .{ "any", builtins.genAny },
    .{ "sorted", builtins.genSorted },
    .{ "reversed", builtins.genReversed },
    .{ "map", builtins.genMap },
    .{ "filter", builtins.genFilter },
    // String/char
    .{ "chr", builtins.genChr },
    .{ "ord", builtins.genOrd },
    // Type functions
    .{ "type", builtins.genType },
    .{ "isinstance", builtins.genIsinstance },
    // Dynamic code execution
    .{ "exec", builtins.genExec },
    .{ "compile", builtins.genCompile },
    // Dynamic attribute access
    .{ "getattr", builtins.genGetattr },
    .{ "setattr", builtins.genSetattr },
    .{ "hasattr", builtins.genHasattr },
    .{ "vars", builtins.genVars },
    .{ "globals", builtins.genGlobals },
    .{ "locals", builtins.genLocals },
});

/// Try to dispatch built-in function call
/// Returns true if dispatched successfully
pub fn tryDispatch(self: *NativeCodegen, call: ast.Node.Call) CodegenError!bool {
    if (call.func.* != .name) return false;

    const func_name = call.func.name.id;

    // eval() needs special handling for comptime vs runtime detection
    if (std.mem.eql(u8, func_name, "eval")) {
        if (call.args.len == 1 and call.args[0] == .constant) {
            const val = call.args[0].constant.value;
            if (val == .string) {
                try builtins.genComptimeEval(self, val.string);
                return true;
            }
        }
        try builtins.genEval(self, call.args);
        return true;
    }

    // __import__() needs special inline codegen
    if (std.mem.eql(u8, func_name, "__import__")) {
        try self.emit("try runtime.dynamic_import(allocator, ");
        try self.genExpr(call.args[0]);
        try self.emit(")");
        return true;
    }

    // O(1) lookup for all standard builtins
    if (BuiltinMap.get(func_name)) |handler| {
        try handler(self, call.args);
        return true;
    }

    return false;
}
