/// Built-in function dispatchers (len, str, int, float, etc.)
const std = @import("std");
const ast = @import("ast");
const NativeCodegen = @import("../main.zig").NativeCodegen;
const CodegenError = @import("../main.zig").CodegenError;

const builtins = @import("../builtins.zig");
const builtins_mod = @import("../builtins_mod.zig");
const io_mod = @import("../io.zig");
const collections_mod = @import("../collections_mod.zig");
const functools_mod = @import("../functools_mod.zig");
const itertools_mod = @import("../itertools_mod.zig");
const copy_mod = @import("../copy_mod.zig");
const struct_mod = @import("../struct_mod.zig");
const base64_mod = @import("../base64_mod.zig");
const random_mod = @import("../random_mod.zig");
const string_mod = @import("../string_mod.zig");
const inspect_mod = @import("../inspect_mod.zig");

/// Handler function type for builtin dispatchers
const BuiltinHandler = *const fn (*NativeCodegen, []ast.Node) CodegenError!void;

/// All builtin functions mapped to their handlers (O(1) lookup)
pub const BuiltinMap = std.StaticStringMap(BuiltinHandler).initComptime(.{
    // Type conversion
    .{ "len", builtins.genLen },
    .{ "str", builtins.genStr },
    .{ "repr", builtins.genRepr },
    .{ "int", builtins.genInt },
    .{ "float", builtins.genFloat },
    .{ "bool", builtins.genBool },
    .{ "hex", builtins.genHex },
    .{ "oct", builtins.genOct },
    .{ "bin", builtins.genBin },
    .{ "bytes", builtins.genBytes },
    .{ "bytearray", builtins.genBytearray },
    .{ "memoryview", builtins.genMemoryview },
    .{ "list", builtins.genList },
    .{ "tuple", builtins.genTuple },
    .{ "dict", builtins.genDict },
    .{ "set", builtins.genSet },
    .{ "frozenset", builtins.genFrozenset },
    // Math
    .{ "abs", builtins.genAbs },
    .{ "min", builtins.genMin },
    .{ "max", builtins.genMax },
    .{ "sum", builtins.genSum },
    .{ "round", builtins.genRound },
    .{ "pow", builtins.genPow },
    .{ "divmod", builtins.genDivmod },
    .{ "hash", builtins.genHash },
    // Collections
    .{ "all", builtins.genAll },
    .{ "any", builtins.genAny },
    .{ "sorted", builtins.genSorted },
    .{ "reversed", builtins.genReversed },
    .{ "map", builtins.genMap },
    .{ "filter", builtins.genFilter },
    // Iterator builtins
    .{ "iter", builtins.genIter },
    .{ "next", builtins.genNext },
    .{ "range", builtins.genRange },
    .{ "enumerate", builtins.genEnumerate },
    .{ "zip", builtins.genZip },
    // String/char
    .{ "chr", builtins.genChr },
    .{ "ord", builtins.genOrd },
    .{ "ascii", builtins.genAscii },
    .{ "format", builtins.genFormat },
    // Object functions
    .{ "id", builtins.genId },
    .{ "delattr", builtins.genDelattr },
    // Type functions
    .{ "type", builtins.genType },
    .{ "isinstance", builtins.genIsinstance },
    .{ "issubclass", builtins.genIssubclass },
    .{ "callable", builtins.genCallable },
    .{ "complex", builtins.genComplex },
    .{ "object", builtins.genObject },
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
    .{ "dir", builtins.genDir },
    // I/O
    .{ "open", builtins.genOpen },
    .{ "input", builtins.genInput },
    .{ "breakpoint", builtins.genBreakpoint },
    .{ "print", builtins.genPrint },
    .{ "aiter", builtins.genAiter },
    .{ "anext", builtins.genAnext },
    // Other builtins
    .{ "super", builtins_mod.genSuper },
    .{ "slice", builtins_mod.genSlice },
    // Decorators (pass through as identity for AOT)
    .{ "staticmethod", builtins.genStaticmethod },
    .{ "classmethod", builtins.genClassmethod },
    .{ "property", builtins.genProperty },
    // Interactive/REPL builtins (no-ops in AOT)
    .{ "help", builtins.genHelp },
    .{ "exit", builtins.genExit },
    .{ "quit", builtins.genQuit },
    .{ "license", builtins.genLicense },
    .{ "credits", builtins.genCredits },
    .{ "copyright", builtins.genCopyright },
    // io module (from io import StringIO, BytesIO)
    .{ "StringIO", io_mod.genStringIO },
    .{ "BytesIO", io_mod.genBytesIO },
    // collections module (from collections import Counter, deque)
    .{ "Counter", collections_mod.genCounter },
    .{ "defaultdict", collections_mod.genDefaultdict },
    .{ "deque", collections_mod.genDeque },
    .{ "OrderedDict", collections_mod.genOrderedDict },
    // functools module (from functools import partial, reduce)
    .{ "partial", functools_mod.genPartial },
    .{ "reduce", functools_mod.genReduce },
    .{ "lru_cache", functools_mod.genLruCache },
    .{ "cache", functools_mod.genCache },
    .{ "wraps", functools_mod.genWraps },
    // itertools module (from itertools import chain, repeat)
    .{ "chain", itertools_mod.genChain },
    .{ "repeat", itertools_mod.genRepeat },
    .{ "count", itertools_mod.genCount },
    .{ "islice", itertools_mod.genIslice },
    .{ "zip_longest", itertools_mod.genZipLongest },
    // copy module (from copy import copy, deepcopy)
    .{ "deepcopy", copy_mod.genDeepcopy },
    // struct module (from struct import pack, unpack, calcsize)
    .{ "pack", struct_mod.genPack },
    .{ "unpack", struct_mod.genUnpack },
    .{ "calcsize", struct_mod.genCalcsize },
    // base64 module (from base64 import b64encode, b64decode)
    .{ "b64encode", base64_mod.genB64encode },
    .{ "b64decode", base64_mod.genB64decode },
    .{ "urlsafe_b64encode", base64_mod.genUrlsafeB64encode },
    .{ "urlsafe_b64decode", base64_mod.genUrlsafeB64decode },
    // random module (from random import randint, choice)
    .{ "randint", random_mod.genRandint },
    .{ "randrange", random_mod.genRandrange },
    // string module (from string import ascii_letters, digits)
    .{ "ascii_letters", string_mod.genAsciiLetters },
    .{ "ascii_lowercase", string_mod.genAsciiLowercase },
    .{ "ascii_uppercase", string_mod.genAsciiUppercase },
    .{ "digits", string_mod.genDigits },
    .{ "punctuation", string_mod.genPunctuation },
    .{ "capwords", string_mod.genCapwords },
    // inspect module (from inspect import isabstract)
    .{ "isabstract", inspect_mod.genIsabstract },
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
        if (call.args.len == 0) {
            try self.emit("@compileError(\"__import__() requires module name argument\")");
            return true;
        }
        try self.emit("try runtime.dynamic_import(__global_allocator, ");
        try self.genExpr(call.args[0]);
        try self.emit(")");
        return true;
    }

    // Special handling for int() with keyword args (base=..., x=...)
    if (std.mem.eql(u8, func_name, "int") and call.keyword_args.len > 0) {
        // Python int() signature: int(x=0, base=10)
        // - int(base=10) without x → TypeError (missing required argument)
        // - int(x='10', base=2) → valid
        var combined_args = std.ArrayList(ast.Node){};
        defer combined_args.deinit(self.allocator);

        // Add positional args first
        for (call.args) |arg| {
            try combined_args.append(self.allocator, arg);
        }

        // Find x keyword arg (first positional)
        var has_x_kwarg = false;
        for (call.keyword_args) |kwarg| {
            if (std.mem.eql(u8, kwarg.name, "x")) {
                try combined_args.append(self.allocator, kwarg.value);
                has_x_kwarg = true;
                break;
            }
        }

        // Find and add 'base' keyword arg as second positional
        var has_base = false;
        for (call.keyword_args) |kwarg| {
            if (std.mem.eql(u8, kwarg.name, "base")) {
                try combined_args.append(self.allocator, kwarg.value);
                has_base = true;
                break;
            }
        }

        // If only base without x or positional arg → TypeError
        if (has_base and combined_args.items.len == 1 and call.args.len == 0 and !has_x_kwarg) {
            // int(base=N) without value → runtime TypeError
            try self.emit("runtime.builtins.intWithBaseOnly()");
            return true;
        }

        try builtins.genInt(self, combined_args.items);
        return true;
    }

    // Special handling for dict() with keyword args: dict(key="value", ...) -> {.key = "value", ...}
    // This creates a runtime.PyObject dict with string keys and string values
    if (std.mem.eql(u8, func_name, "dict") and call.keyword_args.len > 0) {
        try genDictFromKwargs(self, call.keyword_args);
        return true;
    }

    // Special handling for sorted(iterable, key=None, reverse=False)
    if (std.mem.eql(u8, func_name, "sorted")) {
        try genSortedWithKwargs(self, call.args, call.keyword_args);
        return true;
    }

    // O(1) lookup for all standard builtins
    if (BuiltinMap.get(func_name)) |handler| {
        try handler(self, call.args);
        return true;
    }

    return false;
}

/// Generate dict from keyword arguments: dict(key="value", ...) -> StringHashMap
/// This is used when dict() is called with keyword args instead of an iterable
fn genDictFromKwargs(self: *NativeCodegen, kwargs: []const ast.Node.KeywordArg) CodegenError!void {
    // Generate a labeled block that creates and populates a StringHashMap
    const id = self.block_label_counter;
    self.block_label_counter += 1;

    try self.emitFmt("dict_{d}: {{\n", .{id});
    self.indent();

    // Create the dict with string values on stack - will be copied on break
    try self.emitIndent();
    try self.emit("var _map = hashmap_helper.StringHashMap([]const u8).init(__global_allocator);\n");

    // Insert each keyword argument
    for (kwargs) |kwarg| {
        try self.emitIndent();
        try self.emitFmt("_map.put(\"{s}\", ", .{kwarg.name});
        try self.genExpr(kwarg.value);
        try self.emit(") catch unreachable;\n");
    }

    // Return the map value - gets copied to the assignment target
    try self.emitIndent();
    try self.emitFmt("break :dict_{d} _map;\n", .{id});
    self.dedent();
    try self.emitIndent();
    try self.emit("}");
}

/// Generate sorted(iterable, key=None, reverse=False)
/// Supports the reverse keyword argument for descending sort
fn genSortedWithKwargs(self: *NativeCodegen, args: []ast.Node, kwargs: []const ast.Node.KeywordArg) CodegenError!void {
    if (args.len == 0) {
        try self.emit("return error.TypeError");
        return;
    }

    // Check for reverse keyword argument
    var reverse_arg: ?ast.Node = null;
    for (kwargs) |kwarg| {
        if (std.mem.eql(u8, kwarg.name, "reverse")) {
            reverse_arg = kwarg.value;
            break;
        }
    }

    const alloc_name = "__global_allocator";
    const id = self.block_label_counter;
    self.block_label_counter += 1;

    try self.emitFmt("sorted_{d}: {{\n", .{id});

    // Generate the iterable expression
    try self.emitFmt("const __sorted_copy = try {s}.dupe(i64, ", .{alloc_name});
    try self.genExpr(args[0]);
    try self.emit(");\n");

    // Determine sort order - check if reverse is a constant true/false or a variable
    if (reverse_arg) |rev| {
        // Check if it's a literal true/false constant
        if (rev == .constant and rev.constant.value == .bool) {
            if (rev.constant.value.bool) {
                // reverse=True -> descending
                try self.emit("std.mem.sort(i64, __sorted_copy, {}, comptime std.sort.desc(i64));\n");
            } else {
                // reverse=False -> ascending
                try self.emit("std.mem.sort(i64, __sorted_copy, {}, comptime std.sort.asc(i64));\n");
            }
        } else {
            // reverse is a variable - need runtime check
            try self.emit("if (");
            try self.genExpr(rev);
            try self.emit(") {\n");
            try self.emit("std.mem.sort(i64, __sorted_copy, {}, comptime std.sort.desc(i64));\n");
            try self.emit("} else {\n");
            try self.emit("std.mem.sort(i64, __sorted_copy, {}, comptime std.sort.asc(i64));\n");
            try self.emit("}\n");
        }
    } else {
        // No reverse arg -> default to ascending
        try self.emit("std.mem.sort(i64, __sorted_copy, {}, comptime std.sort.asc(i64));\n");
    }

    try self.emitFmt("break :sorted_{d} __sorted_copy;\n}}", .{id});
}
