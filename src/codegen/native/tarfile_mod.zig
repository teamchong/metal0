/// Python tarfile module - Read and write tar archive files
const std = @import("std");
const ast = @import("ast");
const CodegenError = @import("main.zig").CodegenError;
const NativeCodegen = @import("main.zig").NativeCodegen;

const ModuleHandler = *const fn (*NativeCodegen, []ast.Node) CodegenError!void;
pub const Funcs = std.StaticStringMap(ModuleHandler).initComptime(.{
    .{ "open", genOpen },
    .{ "is_tarfile", genIs_tarfile },
    .{ "TarFile", genTarFile },
    .{ "TarInfo", genTarInfo },
    .{ "REGTYPE", genREGTYPE },
    .{ "AREGTYPE", genAREGTYPE },
    .{ "LNKTYPE", genLNKTYPE },
    .{ "SYMTYPE", genSYMTYPE },
    .{ "CHRTYPE", genCHRTYPE },
    .{ "BLKTYPE", genBLKTYPE },
    .{ "DIRTYPE", genDIRTYPE },
    .{ "FIFOTYPE", genFIFOTYPE },
    .{ "CONTTYPE", genCONTTYPE },
    .{ "GNUTYPE_LONGNAME", genGNUTYPE_LONGNAME },
    .{ "GNUTYPE_LONGLINK", genGNUTYPE_LONGLINK },
    .{ "GNUTYPE_SPARSE", genGNUTYPE_SPARSE },
    .{ "USTAR_FORMAT", genUSTAR_FORMAT },
    .{ "GNU_FORMAT", genGNU_FORMAT },
    .{ "PAX_FORMAT", genPAX_FORMAT },
    .{ "DEFAULT_FORMAT", genDEFAULT_FORMAT },
    .{ "BLOCKSIZE", genBLOCKSIZE },
    .{ "RECORDSIZE", genRECORDSIZE },
    .{ "ENCODING", genENCODING },
});

/// Generate tarfile.open(name=None, mode='r', fileobj=None, ...)
pub fn genOpen(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    _ = args;
    try self.emit("@as(?*anyopaque, null)");
}

/// Generate tarfile.is_tarfile(name)
pub fn genIs_tarfile(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    _ = args;
    try self.emit("false");
}

/// Generate tarfile.TarFile class constructor
pub fn genTarFile(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    _ = args;
    try self.emit("@as(?*anyopaque, null)");
}

/// Generate tarfile.TarInfo(name="")
pub fn genTarInfo(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    _ = args;
    try self.emit(".{ .name = \"\", .size = @as(i64, 0), .mtime = @as(i64, 0), .mode = @as(i32, 0o644), .uid = @as(i32, 0), .gid = @as(i32, 0), .type = @as(u8, '0'), .linkname = \"\", .uname = \"\", .gname = \"\" }");
}

// ============================================================================
// Tar entry type constants
// ============================================================================

pub fn genREGTYPE(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    _ = args;
    try self.emit("@as(u8, '0')");
}

pub fn genAREGTYPE(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    _ = args;
    try self.emit("@as(u8, '\\x00')");
}

pub fn genLNKTYPE(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    _ = args;
    try self.emit("@as(u8, '1')");
}

pub fn genSYMTYPE(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    _ = args;
    try self.emit("@as(u8, '2')");
}

pub fn genCHRTYPE(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    _ = args;
    try self.emit("@as(u8, '3')");
}

pub fn genBLKTYPE(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    _ = args;
    try self.emit("@as(u8, '4')");
}

pub fn genDIRTYPE(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    _ = args;
    try self.emit("@as(u8, '5')");
}

pub fn genFIFOTYPE(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    _ = args;
    try self.emit("@as(u8, '6')");
}

pub fn genCONTTYPE(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    _ = args;
    try self.emit("@as(u8, '7')");
}

pub fn genGNUTYPE_LONGNAME(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    _ = args;
    try self.emit("@as(u8, 'L')");
}

pub fn genGNUTYPE_LONGLINK(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    _ = args;
    try self.emit("@as(u8, 'K')");
}

pub fn genGNUTYPE_SPARSE(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    _ = args;
    try self.emit("@as(u8, 'S')");
}

// ============================================================================
// Tar format constants
// ============================================================================

pub fn genUSTAR_FORMAT(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    _ = args;
    try self.emit("@as(i32, 0)");
}

pub fn genGNU_FORMAT(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    _ = args;
    try self.emit("@as(i32, 1)");
}

pub fn genPAX_FORMAT(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    _ = args;
    try self.emit("@as(i32, 2)");
}

pub fn genDEFAULT_FORMAT(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    _ = args;
    try self.emit("@as(i32, 1)"); // GNU_FORMAT
}

// ============================================================================
// Size constants
// ============================================================================

pub fn genBLOCKSIZE(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    _ = args;
    try self.emit("@as(i32, 512)");
}

pub fn genRECORDSIZE(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    _ = args;
    try self.emit("@as(i32, 10240)"); // 20 * BLOCKSIZE
}

// ============================================================================
// Encoding
// ============================================================================

pub fn genENCODING(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    _ = args;
    try self.emit("\"utf-8\"");
}
