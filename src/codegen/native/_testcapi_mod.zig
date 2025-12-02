/// Python _testcapi module - CPython internal test API
const std = @import("std");
const ast = @import("ast");
const CodegenError = @import("main.zig").CodegenError;
const NativeCodegen = @import("main.zig").NativeCodegen;

const ModuleHandler = *const fn (*NativeCodegen, []ast.Node) CodegenError!void;
pub const Funcs = std.StaticStringMap(ModuleHandler).initComptime(.{
    .{ "CHAR_MAX", genCHAR_MAX }, .{ "CHAR_MIN", genCHAR_MIN }, .{ "UCHAR_MAX", genUCHAR_MAX },
    .{ "SHRT_MAX", genSHRT_MAX }, .{ "SHRT_MIN", genSHRT_MIN }, .{ "USHRT_MAX", genUSHRT_MAX },
    .{ "INT_MAX", genINT_MAX }, .{ "INT_MIN", genINT_MIN }, .{ "UINT_MAX", genUINT_MAX },
    .{ "INT32_MAX", genINT_MAX }, .{ "INT32_MIN", genINT_MIN }, .{ "UINT32_MAX", genUINT_MAX },
    .{ "LONG_MAX", genI64_MAX }, .{ "LONG_MIN", genI64_MIN }, .{ "ULONG_MAX", genU64_MAX },
    .{ "LLONG_MAX", genI64_MAX }, .{ "LLONG_MIN", genI64_MIN }, .{ "ULLONG_MAX", genU64_MAX },
    .{ "INT64_MAX", genI64_MAX }, .{ "INT64_MIN", genI64_MIN }, .{ "UINT64_MAX", genU64_MAX },
    .{ "PY_SSIZE_T_MAX", genI64_MAX }, .{ "PY_SSIZE_T_MIN", genI64_MIN }, .{ "SIZE_MAX", genU64_MAX },
    .{ "FLT_MAX", genFLT_MAX }, .{ "FLT_MIN", genFLT_MIN }, .{ "DBL_MAX", genDBL_MAX }, .{ "DBL_MIN", genDBL_MIN },
    .{ "SIZEOF_VOID_P", genSIZEOF_VOID_P }, .{ "SIZEOF_WCHAR_T", gen4 }, .{ "SIZEOF_TIME_T", gen8 }, .{ "SIZEOF_PID_T", gen4 },
    .{ "Py_single_input", gen256 }, .{ "Py_file_input", gen257 }, .{ "Py_eval_input", gen258 },
    .{ "the_number_three", gen3 }, .{ "Py_Version", genPy_Version }, .{ "_Py_STACK_GROWS_DOWN", gen1 },
    .{ "test_string_to_double", genF64_0 }, .{ "test_unicode_compare_with_ascii", genTrue },
    .{ "test_empty_argparse", genUnit }, .{ "get_args", genEmpty }, .{ "get_kwargs", genEmptyDict },
    .{ "MyList", genMyList }, .{ "GenericAlias", genVoid }, .{ "Generic", genVoid },
    .{ "instancemethod", genVoid }, .{ "error", genError },
});

// Helper
fn genConst(self: *NativeCodegen, args: []ast.Node, value: []const u8) CodegenError!void { _ = args; try self.emit(value); }

// Common values
fn genUnit(self: *NativeCodegen, args: []ast.Node) CodegenError!void { try genConst(self, args, "{}"); }
fn genEmpty(self: *NativeCodegen, args: []ast.Node) CodegenError!void { try genConst(self, args, ".{}"); }
fn genVoid(self: *NativeCodegen, args: []ast.Node) CodegenError!void { try genConst(self, args, "void"); }
fn genTrue(self: *NativeCodegen, args: []ast.Node) CodegenError!void { try genConst(self, args, "true"); }
fn genF64_0(self: *NativeCodegen, args: []ast.Node) CodegenError!void { try genConst(self, args, "@as(f64, 0.0)"); }
fn gen1(self: *NativeCodegen, args: []ast.Node) CodegenError!void { try genConst(self, args, "@as(i64, 1)"); }
fn gen3(self: *NativeCodegen, args: []ast.Node) CodegenError!void { try genConst(self, args, "@as(i64, 3)"); }
fn gen4(self: *NativeCodegen, args: []ast.Node) CodegenError!void { try genConst(self, args, "@as(i64, 4)"); }
fn gen8(self: *NativeCodegen, args: []ast.Node) CodegenError!void { try genConst(self, args, "@as(i64, 8)"); }
fn gen256(self: *NativeCodegen, args: []ast.Node) CodegenError!void { try genConst(self, args, "@as(i64, 256)"); }
fn gen257(self: *NativeCodegen, args: []ast.Node) CodegenError!void { try genConst(self, args, "@as(i64, 257)"); }
fn gen258(self: *NativeCodegen, args: []ast.Node) CodegenError!void { try genConst(self, args, "@as(i64, 258)"); }

// Character limits
fn genCHAR_MAX(self: *NativeCodegen, args: []ast.Node) CodegenError!void { try genConst(self, args, "@as(i64, 127)"); }
fn genCHAR_MIN(self: *NativeCodegen, args: []ast.Node) CodegenError!void { try genConst(self, args, "@as(i64, -128)"); }
fn genUCHAR_MAX(self: *NativeCodegen, args: []ast.Node) CodegenError!void { try genConst(self, args, "@as(i64, 255)"); }

// Short limits
fn genSHRT_MAX(self: *NativeCodegen, args: []ast.Node) CodegenError!void { try genConst(self, args, "@as(i64, 32767)"); }
fn genSHRT_MIN(self: *NativeCodegen, args: []ast.Node) CodegenError!void { try genConst(self, args, "@as(i64, -32768)"); }
fn genUSHRT_MAX(self: *NativeCodegen, args: []ast.Node) CodegenError!void { try genConst(self, args, "@as(i64, 65535)"); }

// Int32 limits
fn genINT_MAX(self: *NativeCodegen, args: []ast.Node) CodegenError!void { try genConst(self, args, "@as(i64, 2147483647)"); }
fn genINT_MIN(self: *NativeCodegen, args: []ast.Node) CodegenError!void { try genConst(self, args, "@as(i64, -2147483648)"); }
fn genUINT_MAX(self: *NativeCodegen, args: []ast.Node) CodegenError!void { try genConst(self, args, "@as(i64, 4294967295)"); }

// Int64 limits
fn genI64_MAX(self: *NativeCodegen, args: []ast.Node) CodegenError!void { try genConst(self, args, "@as(i64, 9223372036854775807)"); }
fn genI64_MIN(self: *NativeCodegen, args: []ast.Node) CodegenError!void { try genConst(self, args, "@as(i64, std.math.minInt(i64))"); }
fn genU64_MAX(self: *NativeCodegen, args: []ast.Node) CodegenError!void { try genConst(self, args, "@as(i128, 18446744073709551615)"); }

// Float limits
fn genFLT_MAX(self: *NativeCodegen, args: []ast.Node) CodegenError!void { try genConst(self, args, "@as(f64, 3.4028234663852886e+38)"); }
fn genFLT_MIN(self: *NativeCodegen, args: []ast.Node) CodegenError!void { try genConst(self, args, "@as(f64, 1.1754943508222875e-38)"); }
fn genDBL_MAX(self: *NativeCodegen, args: []ast.Node) CodegenError!void { try genConst(self, args, "@as(f64, 1.7976931348623157e+308)"); }
fn genDBL_MIN(self: *NativeCodegen, args: []ast.Node) CodegenError!void { try genConst(self, args, "@as(f64, 2.2250738585072014e-308)"); }

// Sizeof/misc
fn genSIZEOF_VOID_P(self: *NativeCodegen, args: []ast.Node) CodegenError!void { try genConst(self, args, "@as(i64, @sizeOf(*anyopaque))"); }
fn genPy_Version(self: *NativeCodegen, args: []ast.Node) CodegenError!void { try genConst(self, args, "@as(i64, 0x030C0000)"); }
fn genEmptyDict(self: *NativeCodegen, args: []ast.Node) CodegenError!void { try genConst(self, args, "hashmap_helper.StringHashMap(i64).init(__global_allocator)"); }
fn genMyList(self: *NativeCodegen, args: []ast.Node) CodegenError!void { try genConst(self, args, "std.ArrayList(i64){}"); }
fn genError(self: *NativeCodegen, args: []ast.Node) CodegenError!void { try genConst(self, args, "error.TestCAPIError"); }
