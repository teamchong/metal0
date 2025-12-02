/// Python _ctypes module - Internal ctypes support (C accelerator)
const std = @import("std");
const ast = @import("ast");
const CodegenError = @import("main.zig").CodegenError;
const NativeCodegen = @import("main.zig").NativeCodegen;

const ModuleHandler = *const fn (*NativeCodegen, []ast.Node) CodegenError!void;
pub const Funcs = std.StaticStringMap(ModuleHandler).initComptime(.{
    .{ "CDLL", genDLL }, .{ "PyDLL", genDLL }, .{ "WinDLL", genDLL }, .{ "OleDLL", genDLL },
    .{ "dlopen", genNull }, .{ "dlclose", genI32_0 }, .{ "dlsym", genNull },
    .{ "FUNCFLAG_CDECL", genI32_1 }, .{ "FUNCFLAG_USE_ERRNO", genI32_8 },
    .{ "FUNCFLAG_USE_LASTERROR", genI32_16 }, .{ "FUNCFLAG_PYTHONAPI", genI32_4 },
    .{ "sizeof", genUsize0 }, .{ "alignment", genUsize1 }, .{ "byref", genEmpty }, .{ "addressof", genUsize0 },
    .{ "POINTER", genPtrType }, .{ "pointer", genEmpty }, .{ "cast", genEmpty },
    .{ "set_errno", genI32_0 }, .{ "get_errno", genI32_0 }, .{ "resize", genUnit },
    .{ "c_void_p", genCVoidP }, .{ "c_char_p", genCCharP }, .{ "c_wchar_p", genCWcharP },
    .{ "c_bool", genBool }, .{ "c_char", genU8 }, .{ "c_wchar", genU16 },
    .{ "c_byte", genI8 }, .{ "c_ubyte", genU8 }, .{ "c_short", genI16 }, .{ "c_ushort", genU16 },
    .{ "c_int", genI32 }, .{ "c_uint", genU32 }, .{ "c_long", genI64 }, .{ "c_ulong", genU64 },
    .{ "c_longlong", genI64 }, .{ "c_ulonglong", genU64 },
    .{ "c_size_t", genUsize0 }, .{ "c_ssize_t", genIsize0 },
    .{ "c_float", genF32 }, .{ "c_double", genF64 }, .{ "c_longdouble", genF64 },
    .{ "Structure", genEmpty }, .{ "Union", genEmpty }, .{ "Array", genEmpty },
    .{ "ArgumentError", genArgumentError },
});

// Helpers
fn genConst(self: *NativeCodegen, args: []ast.Node, value: []const u8) CodegenError!void { _ = args; try self.emit(value); }
fn genUnit(self: *NativeCodegen, args: []ast.Node) CodegenError!void { try genConst(self, args, "{}"); }
fn genEmpty(self: *NativeCodegen, args: []ast.Node) CodegenError!void { try genConst(self, args, ".{}"); }
fn genNull(self: *NativeCodegen, args: []ast.Node) CodegenError!void { try genConst(self, args, "null"); }
fn genI32_0(self: *NativeCodegen, args: []ast.Node) CodegenError!void { try genConst(self, args, "@as(i32, 0)"); }
fn genI32_1(self: *NativeCodegen, args: []ast.Node) CodegenError!void { try genConst(self, args, "@as(i32, 1)"); }
fn genI32_4(self: *NativeCodegen, args: []ast.Node) CodegenError!void { try genConst(self, args, "@as(i32, 4)"); }
fn genI32_8(self: *NativeCodegen, args: []ast.Node) CodegenError!void { try genConst(self, args, "@as(i32, 8)"); }
fn genI32_16(self: *NativeCodegen, args: []ast.Node) CodegenError!void { try genConst(self, args, "@as(i32, 16)"); }
fn genUsize0(self: *NativeCodegen, args: []ast.Node) CodegenError!void { try genConst(self, args, "@as(usize, 0)"); }
fn genUsize1(self: *NativeCodegen, args: []ast.Node) CodegenError!void { try genConst(self, args, "@as(usize, 1)"); }
fn genIsize0(self: *NativeCodegen, args: []ast.Node) CodegenError!void { try genConst(self, args, "@as(isize, 0)"); }
fn genBool(self: *NativeCodegen, args: []ast.Node) CodegenError!void { try genConst(self, args, "@as(bool, false)"); }
fn genI8(self: *NativeCodegen, args: []ast.Node) CodegenError!void { try genConst(self, args, "@as(i8, 0)"); }
fn genU8(self: *NativeCodegen, args: []ast.Node) CodegenError!void { try genConst(self, args, "@as(u8, 0)"); }
fn genI16(self: *NativeCodegen, args: []ast.Node) CodegenError!void { try genConst(self, args, "@as(i16, 0)"); }
fn genU16(self: *NativeCodegen, args: []ast.Node) CodegenError!void { try genConst(self, args, "@as(u16, 0)"); }
fn genI32(self: *NativeCodegen, args: []ast.Node) CodegenError!void { try genConst(self, args, "@as(i32, 0)"); }
fn genU32(self: *NativeCodegen, args: []ast.Node) CodegenError!void { try genConst(self, args, "@as(u32, 0)"); }
fn genI64(self: *NativeCodegen, args: []ast.Node) CodegenError!void { try genConst(self, args, "@as(i64, 0)"); }
fn genU64(self: *NativeCodegen, args: []ast.Node) CodegenError!void { try genConst(self, args, "@as(u64, 0)"); }
fn genF32(self: *NativeCodegen, args: []ast.Node) CodegenError!void { try genConst(self, args, "@as(f32, 0.0)"); }
fn genF64(self: *NativeCodegen, args: []ast.Node) CodegenError!void { try genConst(self, args, "@as(f64, 0.0)"); }
fn genCVoidP(self: *NativeCodegen, args: []ast.Node) CodegenError!void { try genConst(self, args, "@as(?*anyopaque, null)"); }
fn genCCharP(self: *NativeCodegen, args: []ast.Node) CodegenError!void { try genConst(self, args, "@as(?[*:0]const u8, null)"); }
fn genCWcharP(self: *NativeCodegen, args: []ast.Node) CodegenError!void { try genConst(self, args, "@as(?[*:0]const u16, null)"); }
fn genPtrType(self: *NativeCodegen, args: []ast.Node) CodegenError!void { try genConst(self, args, "@TypeOf(.{})"); }
fn genDLL(self: *NativeCodegen, args: []ast.Node) CodegenError!void { try genConst(self, args, ".{ .handle = null, .name = null }"); }
fn genArgumentError(self: *NativeCodegen, args: []ast.Node) CodegenError!void { try genConst(self, args, "error.ArgumentError"); }
