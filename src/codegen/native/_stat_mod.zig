/// Python _stat module - Constants/functions from stat.h (internal)
/// MIGRATED TO ZIGBUILDER
const std = @import("std");
const h = @import("mod_helper.zig");
const ast = @import("analysis.ast");
const CodegenError = h.CodegenError;
const NativeCodegen = h.NativeCodegen;

pub const Funcs = std.StaticStringMap(h.H).initComptime(.{
    // File type constants
    .{ "S_IFMT", genSIFMT },
    .{ "S_IFDIR", genSIFDIR },
    .{ "S_IFCHR", genSIFCHR },
    .{ "S_IFBLK", genSIFBLK },
    .{ "S_IFREG", genSIFREG },
    .{ "S_IFIFO", genSIFIFO },
    .{ "S_IFLNK", genSIFLNK },
    .{ "S_IFSOCK", genSIFSOCK },
    // Permission bits
    .{ "S_ISUID", genSISUID },
    .{ "S_ISGID", genSISGID },
    .{ "S_ISVTX", genSISVTX },
    .{ "S_IRWXU", genSIRWXU },
    .{ "S_IRUSR", genSIRUSR },
    .{ "S_IWUSR", genSIWUSR },
    .{ "S_IXUSR", genSIXUSR },
    .{ "S_IRWXG", genSIRWXG },
    .{ "S_IRGRP", genSIRGRP },
    .{ "S_IWGRP", genSIWGRP },
    .{ "S_IXGRP", genSIXGRP },
    .{ "S_IRWXO", genSIRWXO },
    .{ "S_IROTH", genSIROTH },
    .{ "S_IWOTH", genSIWOTH },
    .{ "S_IXOTH", genSIXOTH },
    // Type test functions
    .{ "S_ISDIR", genSISDIR },
    .{ "S_ISCHR", genSISCHR },
    .{ "S_ISBLK", genSISBLK },
    .{ "S_ISREG", genSISREG },
    .{ "S_ISFIFO", genSISFIFO },
    .{ "S_ISLNK", genSISLNK },
    .{ "S_ISSOCK", genSISSOCK },
    .{ "S_IMODE", genSIMODE },
    .{ "filemode", genFilemode },
    // stat_result field indices
    .{ "ST_MODE", genSTMODE },
    .{ "ST_INO", genSTINO },
    .{ "ST_DEV", genSTDEV },
    .{ "ST_NLINK", genSTNLINK },
    .{ "ST_UID", genSTUID },
    .{ "ST_GID", genSTGID },
    .{ "ST_SIZE", genSTSIZE },
    .{ "ST_ATIME", genSTATIME },
    .{ "ST_MTIME", genSTMTIME },
    .{ "ST_CTIME", genSTCTIME },
    // Windows file attributes
    .{ "FILE_ATTRIBUTE_ARCHIVE", genFILEATTRIBUTEARCHIVE },
    .{ "FILE_ATTRIBUTE_COMPRESSED", genFILEATTRIBUTECOMPRESSED },
    .{ "FILE_ATTRIBUTE_DEVICE", genFILEATTRIBUTEDEVICE },
    .{ "FILE_ATTRIBUTE_DIRECTORY", genFILEATTRIBUTEDIRECTORY },
    .{ "FILE_ATTRIBUTE_ENCRYPTED", genFILEATTRIBUTEENCRYPTED },
    .{ "FILE_ATTRIBUTE_HIDDEN", genFILEATTRIBUTEHIDDEN },
    .{ "FILE_ATTRIBUTE_NORMAL", genFILEATTRIBUTENORMAL },
    .{ "FILE_ATTRIBUTE_NOT_CONTENT_INDEXED", genFILEATTRIBUTENOTCONTENTINDEXED },
    .{ "FILE_ATTRIBUTE_OFFLINE", genFILEATTRIBUTEOFFLINE },
    .{ "FILE_ATTRIBUTE_READONLY", genFILEATTRIBUTEREADONLY },
    .{ "FILE_ATTRIBUTE_REPARSE_POINT", genFILEATTRIBUTEREPARSEPOINT },
    .{ "FILE_ATTRIBUTE_SPARSE_FILE", genFILEATTRIBUTESPARSEFILE },
    .{ "FILE_ATTRIBUTE_SYSTEM", genFILEATTRIBUTESYSTEM },
    .{ "FILE_ATTRIBUTE_TEMPORARY", genFILEATTRIBUTETEMPORARY },
    .{ "FILE_ATTRIBUTE_VIRTUAL", genFILEATTRIBUTEVIRTUAL },
});

// File type constants
fn genSIFMT(self: *NativeCodegen, _: []ast.Node) CodegenError!void {
    try self.emit("@as(u32, 0o170000)");
}

fn genSIFDIR(self: *NativeCodegen, _: []ast.Node) CodegenError!void {
    try self.emit("@as(u32, 0o040000)");
}

fn genSIFCHR(self: *NativeCodegen, _: []ast.Node) CodegenError!void {
    try self.emit("@as(u32, 0o020000)");
}

fn genSIFBLK(self: *NativeCodegen, _: []ast.Node) CodegenError!void {
    try self.emit("@as(u32, 0o060000)");
}

fn genSIFREG(self: *NativeCodegen, _: []ast.Node) CodegenError!void {
    try self.emit("@as(u32, 0o100000)");
}

fn genSIFIFO(self: *NativeCodegen, _: []ast.Node) CodegenError!void {
    try self.emit("@as(u32, 0o010000)");
}

fn genSIFLNK(self: *NativeCodegen, _: []ast.Node) CodegenError!void {
    try self.emit("@as(u32, 0o120000)");
}

fn genSIFSOCK(self: *NativeCodegen, _: []ast.Node) CodegenError!void {
    try self.emit("@as(u32, 0o140000)");
}

// Permission bits
fn genSISUID(self: *NativeCodegen, _: []ast.Node) CodegenError!void {
    try self.emit("@as(u32, 0o4000)");
}

fn genSISGID(self: *NativeCodegen, _: []ast.Node) CodegenError!void {
    try self.emit("@as(u32, 0o2000)");
}

fn genSISVTX(self: *NativeCodegen, _: []ast.Node) CodegenError!void {
    try self.emit("@as(u32, 0o1000)");
}

fn genSIRWXU(self: *NativeCodegen, _: []ast.Node) CodegenError!void {
    try self.emit("@as(u32, 0o700)");
}

fn genSIRUSR(self: *NativeCodegen, _: []ast.Node) CodegenError!void {
    try self.emit("@as(u32, 0o400)");
}

fn genSIWUSR(self: *NativeCodegen, _: []ast.Node) CodegenError!void {
    try self.emit("@as(u32, 0o200)");
}

fn genSIXUSR(self: *NativeCodegen, _: []ast.Node) CodegenError!void {
    try self.emit("@as(u32, 0o100)");
}

fn genSIRWXG(self: *NativeCodegen, _: []ast.Node) CodegenError!void {
    try self.emit("@as(u32, 0o070)");
}

fn genSIRGRP(self: *NativeCodegen, _: []ast.Node) CodegenError!void {
    try self.emit("@as(u32, 0o040)");
}

fn genSIWGRP(self: *NativeCodegen, _: []ast.Node) CodegenError!void {
    try self.emit("@as(u32, 0o020)");
}

fn genSIXGRP(self: *NativeCodegen, _: []ast.Node) CodegenError!void {
    try self.emit("@as(u32, 0o010)");
}

fn genSIRWXO(self: *NativeCodegen, _: []ast.Node) CodegenError!void {
    try self.emit("@as(u32, 0o007)");
}

fn genSIROTH(self: *NativeCodegen, _: []ast.Node) CodegenError!void {
    try self.emit("@as(u32, 0o004)");
}

fn genSIWOTH(self: *NativeCodegen, _: []ast.Node) CodegenError!void {
    try self.emit("@as(u32, 0o002)");
}

fn genSIXOTH(self: *NativeCodegen, _: []ast.Node) CodegenError!void {
    try self.emit("@as(u32, 0o001)");
}

// Type test functions
fn genSISDIR(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    if (args.len > 0) {
        try self.emit("((");
        try self.genExpr(args[0]);
        try self.emit(" & 0o170000) == 0o040000)");
    } else {
        try self.emit("false");
    }
}

fn genSISCHR(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    if (args.len > 0) {
        try self.emit("((");
        try self.genExpr(args[0]);
        try self.emit(" & 0o170000) == 0o020000)");
    } else {
        try self.emit("false");
    }
}

fn genSISBLK(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    if (args.len > 0) {
        try self.emit("((");
        try self.genExpr(args[0]);
        try self.emit(" & 0o170000) == 0o060000)");
    } else {
        try self.emit("false");
    }
}

fn genSISREG(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    if (args.len > 0) {
        try self.emit("((");
        try self.genExpr(args[0]);
        try self.emit(" & 0o170000) == 0o100000)");
    } else {
        try self.emit("false");
    }
}

fn genSISFIFO(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    if (args.len > 0) {
        try self.emit("((");
        try self.genExpr(args[0]);
        try self.emit(" & 0o170000) == 0o010000)");
    } else {
        try self.emit("false");
    }
}

fn genSISLNK(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    if (args.len > 0) {
        try self.emit("((");
        try self.genExpr(args[0]);
        try self.emit(" & 0o170000) == 0o120000)");
    } else {
        try self.emit("false");
    }
}

fn genSISSOCK(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    if (args.len > 0) {
        try self.emit("((");
        try self.genExpr(args[0]);
        try self.emit(" & 0o170000) == 0o140000)");
    } else {
        try self.emit("false");
    }
}

fn genSIMODE(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    if (args.len > 0) {
        // Use auto-close pattern for bitwise and expression
        try self.withParensCtx(args[0], struct {
            pub fn f(s: *NativeCodegen, arg: ast.Node) CodegenError!void {
                try s.genExpr(arg);
                try s.emit(" & 0o7777");
            }
        }.f);
    } else {
        try self.emit("@as(u32, 0)");
    }
}

fn genFilemode(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    if (args.len == 0) {
        try self.emit("\"----------\"");
        return;
    }
    try self.withInlineBlock("fm", args, struct {
        fn emit(c: *NativeCodegen, label: []const u8, a: []ast.Node) !void {
            try c.emit("const mode = ");
            try c.genExpr(a[0]);
            try c.emitFmt("; var perm: [10]u8 = \"----------\".*; if ((mode & 0o170000) == 0o040000) perm[0] = 'd'; if ((mode & 0o400) != 0) perm[1] = 'r'; if ((mode & 0o200) != 0) perm[2] = 'w'; if ((mode & 0o100) != 0) perm[3] = 'x'; if ((mode & 0o040) != 0) perm[4] = 'r'; if ((mode & 0o020) != 0) perm[5] = 'w'; if ((mode & 0o010) != 0) perm[6] = 'x'; if ((mode & 0o004) != 0) perm[7] = 'r'; if ((mode & 0o002) != 0) perm[8] = 'w'; if ((mode & 0o001) != 0) perm[9] = 'x'; break :{s} &perm", .{label});
        }
    }.emit);
}

// stat_result field indices
fn genSTMODE(self: *NativeCodegen, _: []ast.Node) CodegenError!void {
    try self.emit("@as(i32, 0)");
}

fn genSTINO(self: *NativeCodegen, _: []ast.Node) CodegenError!void {
    try self.emit("@as(i32, 1)");
}

fn genSTDEV(self: *NativeCodegen, _: []ast.Node) CodegenError!void {
    try self.emit("@as(i32, 2)");
}

fn genSTNLINK(self: *NativeCodegen, _: []ast.Node) CodegenError!void {
    try self.emit("@as(i32, 3)");
}

fn genSTUID(self: *NativeCodegen, _: []ast.Node) CodegenError!void {
    try self.emit("@as(i32, 4)");
}

fn genSTGID(self: *NativeCodegen, _: []ast.Node) CodegenError!void {
    try self.emit("@as(i32, 5)");
}

fn genSTSIZE(self: *NativeCodegen, _: []ast.Node) CodegenError!void {
    try self.emit("@as(i32, 6)");
}

fn genSTATIME(self: *NativeCodegen, _: []ast.Node) CodegenError!void {
    try self.emit("@as(i32, 7)");
}

fn genSTMTIME(self: *NativeCodegen, _: []ast.Node) CodegenError!void {
    try self.emit("@as(i32, 8)");
}

fn genSTCTIME(self: *NativeCodegen, _: []ast.Node) CodegenError!void {
    try self.emit("@as(i32, 9)");
}

// Windows file attributes
fn genFILEATTRIBUTEARCHIVE(self: *NativeCodegen, _: []ast.Node) CodegenError!void {
    try self.emit("@as(u32, 32)");
}

fn genFILEATTRIBUTECOMPRESSED(self: *NativeCodegen, _: []ast.Node) CodegenError!void {
    try self.emit("@as(u32, 2048)");
}

fn genFILEATTRIBUTEDEVICE(self: *NativeCodegen, _: []ast.Node) CodegenError!void {
    try self.emit("@as(u32, 64)");
}

fn genFILEATTRIBUTEDIRECTORY(self: *NativeCodegen, _: []ast.Node) CodegenError!void {
    try self.emit("@as(u32, 16)");
}

fn genFILEATTRIBUTEENCRYPTED(self: *NativeCodegen, _: []ast.Node) CodegenError!void {
    try self.emit("@as(u32, 16384)");
}

fn genFILEATTRIBUTEHIDDEN(self: *NativeCodegen, _: []ast.Node) CodegenError!void {
    try self.emit("@as(u32, 2)");
}

fn genFILEATTRIBUTENORMAL(self: *NativeCodegen, _: []ast.Node) CodegenError!void {
    try self.emit("@as(u32, 128)");
}

fn genFILEATTRIBUTENOTCONTENTINDEXED(self: *NativeCodegen, _: []ast.Node) CodegenError!void {
    try self.emit("@as(u32, 8192)");
}

fn genFILEATTRIBUTEOFFLINE(self: *NativeCodegen, _: []ast.Node) CodegenError!void {
    try self.emit("@as(u32, 4096)");
}

fn genFILEATTRIBUTEREADONLY(self: *NativeCodegen, _: []ast.Node) CodegenError!void {
    try self.emit("@as(u32, 1)");
}

fn genFILEATTRIBUTEREPARSEPOINT(self: *NativeCodegen, _: []ast.Node) CodegenError!void {
    try self.emit("@as(u32, 1024)");
}

fn genFILEATTRIBUTESPARSEFILE(self: *NativeCodegen, _: []ast.Node) CodegenError!void {
    try self.emit("@as(u32, 512)");
}

fn genFILEATTRIBUTESYSTEM(self: *NativeCodegen, _: []ast.Node) CodegenError!void {
    try self.emit("@as(u32, 4)");
}

fn genFILEATTRIBUTETEMPORARY(self: *NativeCodegen, _: []ast.Node) CodegenError!void {
    try self.emit("@as(u32, 256)");
}

fn genFILEATTRIBUTEVIRTUAL(self: *NativeCodegen, _: []ast.Node) CodegenError!void {
    try self.emit("@as(u32, 65536)");
}
