/// Python ctypes module - Foreign function library
const std = @import("std");
const ast = @import("ast");
const CodegenError = @import("main.zig").CodegenError;
const NativeCodegen = @import("main.zig").NativeCodegen;

const ModuleHandler = *const fn (*NativeCodegen, []ast.Node) CodegenError!void;
pub const Funcs = std.StaticStringMap(ModuleHandler).initComptime(.{
    .{ "CDLL", genCDLL }, .{ "WinDLL", genWinDLL }, .{ "OleDLL", genOleDLL }, .{ "PyDLL", genPyDLL },
    .{ "c_bool", genCBool }, .{ "c_char", genCChar }, .{ "c_wchar", genCWchar },
    .{ "c_byte", genCByte }, .{ "c_ubyte", genCUbyte }, .{ "c_short", genCShort },
    .{ "c_ushort", genCUshort }, .{ "c_int", genCInt }, .{ "c_uint", genCUint },
    .{ "c_long", genCLong }, .{ "c_ulong", genCUlong }, .{ "c_longlong", genCLonglong },
    .{ "c_ulonglong", genCUlonglong }, .{ "c_size_t", genCSizeT }, .{ "c_ssize_t", genCSSizeT },
    .{ "c_float", genCFloat }, .{ "c_double", genCDouble }, .{ "c_longdouble", genCLongdouble },
    .{ "c_char_p", genCCharP }, .{ "c_wchar_p", genCWcharP }, .{ "c_void_p", genCVoidP },
    .{ "Structure", genStructure }, .{ "Union", genUnion },
    .{ "BigEndianStructure", genBigEndianStructure }, .{ "LittleEndianStructure", genLittleEndianStructure },
    .{ "Array", genArrayType }, .{ "POINTER", genPOINTER }, .{ "pointer", genPointer },
    .{ "sizeof", genSizeof }, .{ "alignment", genAlignment }, .{ "addressof", genAddressof },
    .{ "byref", genByref }, .{ "cast", genCast }, .{ "create_string_buffer", genCreateStringBuffer },
    .{ "create_unicode_buffer", genCreateUnicodeBuffer }, .{ "get_errno", genGetErrno },
    .{ "set_errno", genSetErrno }, .{ "get_last_error", genGetLastError }, .{ "set_last_error", genSetLastError },
    .{ "memmove", genMemmove }, .{ "memset", genMemset }, .{ "string_at", genStringAt },
    .{ "wstring_at", genWstringAt }, .{ "CFUNCTYPE", genCFUNCTYPE }, .{ "WINFUNCTYPE", genWINFUNCTYPE },
    .{ "PYFUNCTYPE", genPYFUNCTYPE },
});

// Helpers
fn genConst(self: *NativeCodegen, args: []ast.Node, value: []const u8) CodegenError!void { _ = args; try self.emit(value); }
fn genDLL(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    try self.emit("struct { _name: []const u8 = ");
    if (args.len > 0) try self.genExpr(args[0]) else try self.emit("\"\"");
    try self.emit(", _handle: ?*anyopaque = null }{}");
}
fn genCType(self: *NativeCodegen, args: []ast.Node, zig_type: []const u8, default: []const u8, prefix: []const u8, suffix: []const u8) CodegenError!void {
    if (args.len > 0) { try self.emit(prefix); try self.genExpr(args[0]); try self.emit(suffix); }
    else { try self.emit("@as("); try self.emit(zig_type); try self.emit(", "); try self.emit(default); try self.emit(")"); }
}

// DLLs
pub fn genCDLL(self: *NativeCodegen, args: []ast.Node) CodegenError!void { try genDLL(self, args); }
pub fn genWinDLL(self: *NativeCodegen, args: []ast.Node) CodegenError!void { try genDLL(self, args); }
pub fn genOleDLL(self: *NativeCodegen, args: []ast.Node) CodegenError!void { try genDLL(self, args); }
pub fn genPyDLL(self: *NativeCodegen, args: []ast.Node) CodegenError!void { try genDLL(self, args); }

// Simple C types
pub fn genCBool(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    if (args.len > 0) { try self.emit("@as(bool, "); try self.genExpr(args[0]); try self.emit(" != 0)"); } else try self.emit("false");
}
pub fn genCChar(self: *NativeCodegen, args: []ast.Node) CodegenError!void { try genCType(self, args, "u8", "0", "@as(u8, @truncate(@as(usize, @intCast(", "))))"); }
pub fn genCWchar(self: *NativeCodegen, args: []ast.Node) CodegenError!void { try genCType(self, args, "u32", "0", "@as(u32, @intCast(", "))"); }
pub fn genCByte(self: *NativeCodegen, args: []ast.Node) CodegenError!void { try genCType(self, args, "i8", "0", "@as(i8, @truncate(@as(i64, ", ")))"); }
pub fn genCUbyte(self: *NativeCodegen, args: []ast.Node) CodegenError!void { try genCType(self, args, "u8", "0", "@as(u8, @truncate(@as(u64, @intCast(", "))))"); }
pub fn genCShort(self: *NativeCodegen, args: []ast.Node) CodegenError!void { try genCType(self, args, "i16", "0", "@as(i16, @truncate(@as(i64, ", ")))"); }
pub fn genCUshort(self: *NativeCodegen, args: []ast.Node) CodegenError!void { try genCType(self, args, "u16", "0", "@as(u16, @truncate(@as(u64, @intCast(", "))))"); }
pub fn genCInt(self: *NativeCodegen, args: []ast.Node) CodegenError!void { try genCType(self, args, "i32", "0", "@as(i32, @truncate(@as(i64, ", ")))"); }
pub fn genCUint(self: *NativeCodegen, args: []ast.Node) CodegenError!void { try genCType(self, args, "u32", "0", "@as(u32, @truncate(@as(u64, @intCast(", "))))"); }
pub fn genCLong(self: *NativeCodegen, args: []ast.Node) CodegenError!void { try genCType(self, args, "i64", "0", "@as(i64, ", ")"); }
pub fn genCUlong(self: *NativeCodegen, args: []ast.Node) CodegenError!void { try genCType(self, args, "u64", "0", "@as(u64, @intCast(", "))"); }
pub fn genCLonglong(self: *NativeCodegen, args: []ast.Node) CodegenError!void { try genCType(self, args, "i64", "0", "@as(i64, ", ")"); }
pub fn genCUlonglong(self: *NativeCodegen, args: []ast.Node) CodegenError!void { try genCType(self, args, "u64", "0", "@as(u64, @intCast(", "))"); }
pub fn genCSizeT(self: *NativeCodegen, args: []ast.Node) CodegenError!void { try genCType(self, args, "usize", "0", "@as(usize, @intCast(", "))"); }
pub fn genCSSizeT(self: *NativeCodegen, args: []ast.Node) CodegenError!void { try genCType(self, args, "isize", "0", "@as(isize, @intCast(", "))"); }
pub fn genCFloat(self: *NativeCodegen, args: []ast.Node) CodegenError!void { try genCType(self, args, "f32", "0.0", "@as(f32, @floatCast(", "))"); }
pub fn genCDouble(self: *NativeCodegen, args: []ast.Node) CodegenError!void { try genCType(self, args, "f64", "0.0", "@as(f64, ", ")"); }
pub fn genCLongdouble(self: *NativeCodegen, args: []ast.Node) CodegenError!void { try genCType(self, args, "f128", "0.0", "@as(f128, ", ")"); }

// Pointer types
pub fn genCCharP(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    if (args.len > 0) try self.genExpr(args[0]) else try self.emit("@as(?[*:0]const u8, null)");
}
pub fn genCWcharP(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    if (args.len > 0) try self.genExpr(args[0]) else try self.emit("@as(?[*:0]const u32, null)");
}
pub fn genCVoidP(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    if (args.len > 0) { try self.emit("@as(*anyopaque, @ptrFromInt(@as(usize, @intCast("); try self.genExpr(args[0]); try self.emit("))))"); }
    else try self.emit("@as(?*anyopaque, null)");
}

// Structure types
pub fn genStructure(self: *NativeCodegen, args: []ast.Node) CodegenError!void { try genConst(self, args, "struct {}{}"); }
pub fn genUnion(self: *NativeCodegen, args: []ast.Node) CodegenError!void { try genConst(self, args, "union {}{}"); }
pub fn genBigEndianStructure(self: *NativeCodegen, args: []ast.Node) CodegenError!void { try genConst(self, args, "struct {}{}"); }
pub fn genLittleEndianStructure(self: *NativeCodegen, args: []ast.Node) CodegenError!void { try genConst(self, args, "struct {}{}"); }

// Arrays and pointers
pub fn genArrayType(self: *NativeCodegen, args: []ast.Node) CodegenError!void { try genConst(self, args, "[]anyopaque"); }
pub fn genPOINTER(self: *NativeCodegen, args: []ast.Node) CodegenError!void { try genConst(self, args, "*anyopaque"); }
pub fn genPointer(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    if (args.len > 0) { try self.emit("@as(*anyopaque, @ptrCast(&"); try self.genExpr(args[0]); try self.emit("))"); }
    else try self.emit("@as(?*anyopaque, null)");
}

// Utility functions
pub fn genSizeof(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    if (args.len > 0) { try self.emit("@sizeOf(@TypeOf("); try self.genExpr(args[0]); try self.emit("))"); } else try self.emit("0");
}
pub fn genAlignment(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    if (args.len > 0) { try self.emit("@alignOf(@TypeOf("); try self.genExpr(args[0]); try self.emit("))"); } else try self.emit("1");
}
pub fn genAddressof(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    if (args.len > 0) { try self.emit("@intFromPtr(&"); try self.genExpr(args[0]); try self.emit(")"); } else try self.emit("0");
}
pub fn genByref(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    if (args.len > 0) { try self.emit("&"); try self.genExpr(args[0]); } else try self.emit("null");
}
pub fn genCast(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    if (args.len > 0) { try self.emit("@as(*anyopaque, @ptrCast("); try self.genExpr(args[0]); try self.emit("))"); } else try self.emit("null");
}
pub fn genCreateStringBuffer(self: *NativeCodegen, args: []ast.Node) CodegenError!void { try genConst(self, args, "@as([]u8, __global_allocator.alloc(u8, 256) catch &[_]u8{})"); }
pub fn genCreateUnicodeBuffer(self: *NativeCodegen, args: []ast.Node) CodegenError!void { try genConst(self, args, "@as([]u32, __global_allocator.alloc(u32, 256) catch &[_]u32{})"); }
pub fn genGetErrno(self: *NativeCodegen, args: []ast.Node) CodegenError!void { try genConst(self, args, "@as(i32, 0)"); }
pub fn genSetErrno(self: *NativeCodegen, args: []ast.Node) CodegenError!void { try genConst(self, args, "@as(i32, 0)"); }
pub fn genGetLastError(self: *NativeCodegen, args: []ast.Node) CodegenError!void { try genConst(self, args, "@as(i32, 0)"); }
pub fn genSetLastError(self: *NativeCodegen, args: []ast.Node) CodegenError!void { try genConst(self, args, "@as(i32, 0)"); }
pub fn genMemmove(self: *NativeCodegen, args: []ast.Node) CodegenError!void { try genConst(self, args, "{}"); }
pub fn genMemset(self: *NativeCodegen, args: []ast.Node) CodegenError!void { try genConst(self, args, "{}"); }
pub fn genStringAt(self: *NativeCodegen, args: []ast.Node) CodegenError!void { try genConst(self, args, "\"\""); }
pub fn genWstringAt(self: *NativeCodegen, args: []ast.Node) CodegenError!void { try genConst(self, args, "\"\""); }

// Function types
pub fn genCFUNCTYPE(self: *NativeCodegen, args: []ast.Node) CodegenError!void { try genConst(self, args, "*const fn() callconv(.c) void"); }
pub fn genWINFUNCTYPE(self: *NativeCodegen, args: []ast.Node) CodegenError!void { try genConst(self, args, "*const fn() callconv(.stdcall) void"); }
pub fn genPYFUNCTYPE(self: *NativeCodegen, args: []ast.Node) CodegenError!void { try genConst(self, args, "*const fn() void"); }
