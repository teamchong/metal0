/// Python _stat module - Constants/functions from stat.h (internal)
/// MIGRATED TO ZIGBUILDER
const std = @import("std");
const h = @import("mod_helper.zig");
const builder_mod = @import("codegen.builder");
const ast = @import("analysis.ast");

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
fn genSIFMT(self: *h.NativeCodegen, _: []ast.Node) h.CodegenError!void {
    const b = try self.getBuilder();
    try b.emitValue(builder_mod.ZigValue.raw("@as(u32, 0o170000)"), builder_mod.EmitConfig.forExpression());
}

fn genSIFDIR(self: *h.NativeCodegen, _: []ast.Node) h.CodegenError!void {
    const b = try self.getBuilder();
    try b.emitValue(builder_mod.ZigValue.raw("@as(u32, 0o040000)"), builder_mod.EmitConfig.forExpression());
}

fn genSIFCHR(self: *h.NativeCodegen, _: []ast.Node) h.CodegenError!void {
    const b = try self.getBuilder();
    try b.emitValue(builder_mod.ZigValue.raw("@as(u32, 0o020000)"), builder_mod.EmitConfig.forExpression());
}

fn genSIFBLK(self: *h.NativeCodegen, _: []ast.Node) h.CodegenError!void {
    const b = try self.getBuilder();
    try b.emitValue(builder_mod.ZigValue.raw("@as(u32, 0o060000)"), builder_mod.EmitConfig.forExpression());
}

fn genSIFREG(self: *h.NativeCodegen, _: []ast.Node) h.CodegenError!void {
    const b = try self.getBuilder();
    try b.emitValue(builder_mod.ZigValue.raw("@as(u32, 0o100000)"), builder_mod.EmitConfig.forExpression());
}

fn genSIFIFO(self: *h.NativeCodegen, _: []ast.Node) h.CodegenError!void {
    const b = try self.getBuilder();
    try b.emitValue(builder_mod.ZigValue.raw("@as(u32, 0o010000)"), builder_mod.EmitConfig.forExpression());
}

fn genSIFLNK(self: *h.NativeCodegen, _: []ast.Node) h.CodegenError!void {
    const b = try self.getBuilder();
    try b.emitValue(builder_mod.ZigValue.raw("@as(u32, 0o120000)"), builder_mod.EmitConfig.forExpression());
}

fn genSIFSOCK(self: *h.NativeCodegen, _: []ast.Node) h.CodegenError!void {
    const b = try self.getBuilder();
    try b.emitValue(builder_mod.ZigValue.raw("@as(u32, 0o140000)"), builder_mod.EmitConfig.forExpression());
}

// Permission bits
fn genSISUID(self: *h.NativeCodegen, _: []ast.Node) h.CodegenError!void {
    const b = try self.getBuilder();
    try b.emitValue(builder_mod.ZigValue.raw("@as(u32, 0o4000)"), builder_mod.EmitConfig.forExpression());
}

fn genSISGID(self: *h.NativeCodegen, _: []ast.Node) h.CodegenError!void {
    const b = try self.getBuilder();
    try b.emitValue(builder_mod.ZigValue.raw("@as(u32, 0o2000)"), builder_mod.EmitConfig.forExpression());
}

fn genSISVTX(self: *h.NativeCodegen, _: []ast.Node) h.CodegenError!void {
    const b = try self.getBuilder();
    try b.emitValue(builder_mod.ZigValue.raw("@as(u32, 0o1000)"), builder_mod.EmitConfig.forExpression());
}

fn genSIRWXU(self: *h.NativeCodegen, _: []ast.Node) h.CodegenError!void {
    const b = try self.getBuilder();
    try b.emitValue(builder_mod.ZigValue.raw("@as(u32, 0o700)"), builder_mod.EmitConfig.forExpression());
}

fn genSIRUSR(self: *h.NativeCodegen, _: []ast.Node) h.CodegenError!void {
    const b = try self.getBuilder();
    try b.emitValue(builder_mod.ZigValue.raw("@as(u32, 0o400)"), builder_mod.EmitConfig.forExpression());
}

fn genSIWUSR(self: *h.NativeCodegen, _: []ast.Node) h.CodegenError!void {
    const b = try self.getBuilder();
    try b.emitValue(builder_mod.ZigValue.raw("@as(u32, 0o200)"), builder_mod.EmitConfig.forExpression());
}

fn genSIXUSR(self: *h.NativeCodegen, _: []ast.Node) h.CodegenError!void {
    const b = try self.getBuilder();
    try b.emitValue(builder_mod.ZigValue.raw("@as(u32, 0o100)"), builder_mod.EmitConfig.forExpression());
}

fn genSIRWXG(self: *h.NativeCodegen, _: []ast.Node) h.CodegenError!void {
    const b = try self.getBuilder();
    try b.emitValue(builder_mod.ZigValue.raw("@as(u32, 0o070)"), builder_mod.EmitConfig.forExpression());
}

fn genSIRGRP(self: *h.NativeCodegen, _: []ast.Node) h.CodegenError!void {
    const b = try self.getBuilder();
    try b.emitValue(builder_mod.ZigValue.raw("@as(u32, 0o040)"), builder_mod.EmitConfig.forExpression());
}

fn genSIWGRP(self: *h.NativeCodegen, _: []ast.Node) h.CodegenError!void {
    const b = try self.getBuilder();
    try b.emitValue(builder_mod.ZigValue.raw("@as(u32, 0o020)"), builder_mod.EmitConfig.forExpression());
}

fn genSIXGRP(self: *h.NativeCodegen, _: []ast.Node) h.CodegenError!void {
    const b = try self.getBuilder();
    try b.emitValue(builder_mod.ZigValue.raw("@as(u32, 0o010)"), builder_mod.EmitConfig.forExpression());
}

fn genSIRWXO(self: *h.NativeCodegen, _: []ast.Node) h.CodegenError!void {
    const b = try self.getBuilder();
    try b.emitValue(builder_mod.ZigValue.raw("@as(u32, 0o007)"), builder_mod.EmitConfig.forExpression());
}

fn genSIROTH(self: *h.NativeCodegen, _: []ast.Node) h.CodegenError!void {
    const b = try self.getBuilder();
    try b.emitValue(builder_mod.ZigValue.raw("@as(u32, 0o004)"), builder_mod.EmitConfig.forExpression());
}

fn genSIWOTH(self: *h.NativeCodegen, _: []ast.Node) h.CodegenError!void {
    const b = try self.getBuilder();
    try b.emitValue(builder_mod.ZigValue.raw("@as(u32, 0o002)"), builder_mod.EmitConfig.forExpression());
}

fn genSIXOTH(self: *h.NativeCodegen, _: []ast.Node) h.CodegenError!void {
    const b = try self.getBuilder();
    try b.emitValue(builder_mod.ZigValue.raw("@as(u32, 0o001)"), builder_mod.EmitConfig.forExpression());
}

// Type test functions
fn genSISDIR(self: *h.NativeCodegen, args: []ast.Node) h.CodegenError!void {
    const b = try self.getBuilder();
    if (args.len > 0) {
        try self.emit("((");
        try self.genExpr(args[0]);
        try self.emit(" & 0o170000) == 0o040000)");
    } else {
        try b.emitValue(builder_mod.ZigValue.boolean(false), builder_mod.EmitConfig.forExpression());
    }
}

fn genSISCHR(self: *h.NativeCodegen, args: []ast.Node) h.CodegenError!void {
    const b = try self.getBuilder();
    if (args.len > 0) {
        try self.emit("((");
        try self.genExpr(args[0]);
        try self.emit(" & 0o170000) == 0o020000)");
    } else {
        try b.emitValue(builder_mod.ZigValue.boolean(false), builder_mod.EmitConfig.forExpression());
    }
}

fn genSISBLK(self: *h.NativeCodegen, args: []ast.Node) h.CodegenError!void {
    const b = try self.getBuilder();
    if (args.len > 0) {
        try self.emit("((");
        try self.genExpr(args[0]);
        try self.emit(" & 0o170000) == 0o060000)");
    } else {
        try b.emitValue(builder_mod.ZigValue.boolean(false), builder_mod.EmitConfig.forExpression());
    }
}

fn genSISREG(self: *h.NativeCodegen, args: []ast.Node) h.CodegenError!void {
    const b = try self.getBuilder();
    if (args.len > 0) {
        try self.emit("((");
        try self.genExpr(args[0]);
        try self.emit(" & 0o170000) == 0o100000)");
    } else {
        try b.emitValue(builder_mod.ZigValue.boolean(false), builder_mod.EmitConfig.forExpression());
    }
}

fn genSISFIFO(self: *h.NativeCodegen, args: []ast.Node) h.CodegenError!void {
    const b = try self.getBuilder();
    if (args.len > 0) {
        try self.emit("((");
        try self.genExpr(args[0]);
        try self.emit(" & 0o170000) == 0o010000)");
    } else {
        try b.emitValue(builder_mod.ZigValue.boolean(false), builder_mod.EmitConfig.forExpression());
    }
}

fn genSISLNK(self: *h.NativeCodegen, args: []ast.Node) h.CodegenError!void {
    const b = try self.getBuilder();
    if (args.len > 0) {
        try self.emit("((");
        try self.genExpr(args[0]);
        try self.emit(" & 0o170000) == 0o120000)");
    } else {
        try b.emitValue(builder_mod.ZigValue.boolean(false), builder_mod.EmitConfig.forExpression());
    }
}

fn genSISSOCK(self: *h.NativeCodegen, args: []ast.Node) h.CodegenError!void {
    const b = try self.getBuilder();
    if (args.len > 0) {
        try self.emit("((");
        try self.genExpr(args[0]);
        try self.emit(" & 0o170000) == 0o140000)");
    } else {
        try b.emitValue(builder_mod.ZigValue.boolean(false), builder_mod.EmitConfig.forExpression());
    }
}

fn genSIMODE(self: *h.NativeCodegen, args: []ast.Node) h.CodegenError!void {
    const b = try self.getBuilder();
    if (args.len > 0) {
        try self.emit("(");
        try self.genExpr(args[0]);
        try self.emit(" & 0o7777)");
    } else {
        try b.emitValue(builder_mod.ZigValue.raw("@as(u32, 0)"), builder_mod.EmitConfig.forExpression());
    }
}

fn genFilemode(self: *h.NativeCodegen, args: []ast.Node) h.CodegenError!void {
    const b = try self.getBuilder();
    if (args.len == 0) {
        try b.emitValue(builder_mod.ZigValue.string("----------"), builder_mod.EmitConfig.forExpression());
        return;
    }
    try self.withInlineBlock("fm", args, struct {
        fn emit(c: *h.NativeCodegen, label: []const u8, a: []ast.Node) !void {
            try c.emit("const mode = ");
            try c.genExpr(a[0]);
            try c.emit("; var perm: [10]u8 = \"----------\".*; if ((mode & 0o170000) == 0o040000) perm[0] = 'd'; if ((mode & 0o400) != 0) perm[1] = 'r'; if ((mode & 0o200) != 0) perm[2] = 'w'; if ((mode & 0o100) != 0) perm[3] = 'x'; if ((mode & 0o040) != 0) perm[4] = 'r'; if ((mode & 0o020) != 0) perm[5] = 'w'; if ((mode & 0o010) != 0) perm[6] = 'x'; if ((mode & 0o004) != 0) perm[7] = 'r'; if ((mode & 0o002) != 0) perm[8] = 'w'; if ((mode & 0o001) != 0) perm[9] = 'x'; break :");
            try c.emitFmt("{s} &perm", .{label});
        }
    }.emit);
}

// stat_result field indices
fn genSTMODE(self: *h.NativeCodegen, _: []ast.Node) h.CodegenError!void {
    const b = try self.getBuilder();
    try b.emitValue(builder_mod.ZigValue.raw("@as(i32, 0)"), builder_mod.EmitConfig.forExpression());
}

fn genSTINO(self: *h.NativeCodegen, _: []ast.Node) h.CodegenError!void {
    const b = try self.getBuilder();
    try b.emitValue(builder_mod.ZigValue.raw("@as(i32, 1)"), builder_mod.EmitConfig.forExpression());
}

fn genSTDEV(self: *h.NativeCodegen, _: []ast.Node) h.CodegenError!void {
    const b = try self.getBuilder();
    try b.emitValue(builder_mod.ZigValue.raw("@as(i32, 2)"), builder_mod.EmitConfig.forExpression());
}

fn genSTNLINK(self: *h.NativeCodegen, _: []ast.Node) h.CodegenError!void {
    const b = try self.getBuilder();
    try b.emitValue(builder_mod.ZigValue.raw("@as(i32, 3)"), builder_mod.EmitConfig.forExpression());
}

fn genSTUID(self: *h.NativeCodegen, _: []ast.Node) h.CodegenError!void {
    const b = try self.getBuilder();
    try b.emitValue(builder_mod.ZigValue.raw("@as(i32, 4)"), builder_mod.EmitConfig.forExpression());
}

fn genSTGID(self: *h.NativeCodegen, _: []ast.Node) h.CodegenError!void {
    const b = try self.getBuilder();
    try b.emitValue(builder_mod.ZigValue.raw("@as(i32, 5)"), builder_mod.EmitConfig.forExpression());
}

fn genSTSIZE(self: *h.NativeCodegen, _: []ast.Node) h.CodegenError!void {
    const b = try self.getBuilder();
    try b.emitValue(builder_mod.ZigValue.raw("@as(i32, 6)"), builder_mod.EmitConfig.forExpression());
}

fn genSTATIME(self: *h.NativeCodegen, _: []ast.Node) h.CodegenError!void {
    const b = try self.getBuilder();
    try b.emitValue(builder_mod.ZigValue.raw("@as(i32, 7)"), builder_mod.EmitConfig.forExpression());
}

fn genSTMTIME(self: *h.NativeCodegen, _: []ast.Node) h.CodegenError!void {
    const b = try self.getBuilder();
    try b.emitValue(builder_mod.ZigValue.raw("@as(i32, 8)"), builder_mod.EmitConfig.forExpression());
}

fn genSTCTIME(self: *h.NativeCodegen, _: []ast.Node) h.CodegenError!void {
    const b = try self.getBuilder();
    try b.emitValue(builder_mod.ZigValue.raw("@as(i32, 9)"), builder_mod.EmitConfig.forExpression());
}

// Windows file attributes
fn genFILEATTRIBUTEARCHIVE(self: *h.NativeCodegen, _: []ast.Node) h.CodegenError!void {
    const b = try self.getBuilder();
    try b.emitValue(builder_mod.ZigValue.raw("@as(u32, 32)"), builder_mod.EmitConfig.forExpression());
}

fn genFILEATTRIBUTECOMPRESSED(self: *h.NativeCodegen, _: []ast.Node) h.CodegenError!void {
    const b = try self.getBuilder();
    try b.emitValue(builder_mod.ZigValue.raw("@as(u32, 2048)"), builder_mod.EmitConfig.forExpression());
}

fn genFILEATTRIBUTEDEVICE(self: *h.NativeCodegen, _: []ast.Node) h.CodegenError!void {
    const b = try self.getBuilder();
    try b.emitValue(builder_mod.ZigValue.raw("@as(u32, 64)"), builder_mod.EmitConfig.forExpression());
}

fn genFILEATTRIBUTEDIRECTORY(self: *h.NativeCodegen, _: []ast.Node) h.CodegenError!void {
    const b = try self.getBuilder();
    try b.emitValue(builder_mod.ZigValue.raw("@as(u32, 16)"), builder_mod.EmitConfig.forExpression());
}

fn genFILEATTRIBUTEENCRYPTED(self: *h.NativeCodegen, _: []ast.Node) h.CodegenError!void {
    const b = try self.getBuilder();
    try b.emitValue(builder_mod.ZigValue.raw("@as(u32, 16384)"), builder_mod.EmitConfig.forExpression());
}

fn genFILEATTRIBUTEHIDDEN(self: *h.NativeCodegen, _: []ast.Node) h.CodegenError!void {
    const b = try self.getBuilder();
    try b.emitValue(builder_mod.ZigValue.raw("@as(u32, 2)"), builder_mod.EmitConfig.forExpression());
}

fn genFILEATTRIBUTENORMAL(self: *h.NativeCodegen, _: []ast.Node) h.CodegenError!void {
    const b = try self.getBuilder();
    try b.emitValue(builder_mod.ZigValue.raw("@as(u32, 128)"), builder_mod.EmitConfig.forExpression());
}

fn genFILEATTRIBUTENOTCONTENTINDEXED(self: *h.NativeCodegen, _: []ast.Node) h.CodegenError!void {
    const b = try self.getBuilder();
    try b.emitValue(builder_mod.ZigValue.raw("@as(u32, 8192)"), builder_mod.EmitConfig.forExpression());
}

fn genFILEATTRIBUTEOFFLINE(self: *h.NativeCodegen, _: []ast.Node) h.CodegenError!void {
    const b = try self.getBuilder();
    try b.emitValue(builder_mod.ZigValue.raw("@as(u32, 4096)"), builder_mod.EmitConfig.forExpression());
}

fn genFILEATTRIBUTEREADONLY(self: *h.NativeCodegen, _: []ast.Node) h.CodegenError!void {
    const b = try self.getBuilder();
    try b.emitValue(builder_mod.ZigValue.raw("@as(u32, 1)"), builder_mod.EmitConfig.forExpression());
}

fn genFILEATTRIBUTEREPARSEPOINT(self: *h.NativeCodegen, _: []ast.Node) h.CodegenError!void {
    const b = try self.getBuilder();
    try b.emitValue(builder_mod.ZigValue.raw("@as(u32, 1024)"), builder_mod.EmitConfig.forExpression());
}

fn genFILEATTRIBUTESPARSEFILE(self: *h.NativeCodegen, _: []ast.Node) h.CodegenError!void {
    const b = try self.getBuilder();
    try b.emitValue(builder_mod.ZigValue.raw("@as(u32, 512)"), builder_mod.EmitConfig.forExpression());
}

fn genFILEATTRIBUTESYSTEM(self: *h.NativeCodegen, _: []ast.Node) h.CodegenError!void {
    const b = try self.getBuilder();
    try b.emitValue(builder_mod.ZigValue.raw("@as(u32, 4)"), builder_mod.EmitConfig.forExpression());
}

fn genFILEATTRIBUTETEMPORARY(self: *h.NativeCodegen, _: []ast.Node) h.CodegenError!void {
    const b = try self.getBuilder();
    try b.emitValue(builder_mod.ZigValue.raw("@as(u32, 256)"), builder_mod.EmitConfig.forExpression());
}

fn genFILEATTRIBUTEVIRTUAL(self: *h.NativeCodegen, _: []ast.Node) h.CodegenError!void {
    const b = try self.getBuilder();
    try b.emitValue(builder_mod.ZigValue.raw("@as(u32, 65536)"), builder_mod.EmitConfig.forExpression());
}
