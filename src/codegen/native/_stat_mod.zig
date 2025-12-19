/// Python _stat module - Constants/functions from stat.h (internal)
/// MIGRATED TO ZIGBUILDER
const std = @import("std");
const h = @import("mod_helper.zig");
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

// Helper for simple constant output
fn emitConst(self: *h.NativeCodegen, val: []const u8) h.CodegenError!void {
    const b = try self.getBuilder();
    try b.write(val);
    const output = b.getBodyAndClear();
    try self.output.appendSlice(self.allocator, output);
}

// File type constants
fn genSIFMT(self: *h.NativeCodegen, _: []ast.Node) h.CodegenError!void {
    try emitConst(self, "@as(u32, 0o170000)");
}

fn genSIFDIR(self: *h.NativeCodegen, _: []ast.Node) h.CodegenError!void {
    try emitConst(self, "@as(u32, 0o040000)");
}

fn genSIFCHR(self: *h.NativeCodegen, _: []ast.Node) h.CodegenError!void {
    try emitConst(self, "@as(u32, 0o020000)");
}

fn genSIFBLK(self: *h.NativeCodegen, _: []ast.Node) h.CodegenError!void {
    try emitConst(self, "@as(u32, 0o060000)");
}

fn genSIFREG(self: *h.NativeCodegen, _: []ast.Node) h.CodegenError!void {
    try emitConst(self, "@as(u32, 0o100000)");
}

fn genSIFIFO(self: *h.NativeCodegen, _: []ast.Node) h.CodegenError!void {
    try emitConst(self, "@as(u32, 0o010000)");
}

fn genSIFLNK(self: *h.NativeCodegen, _: []ast.Node) h.CodegenError!void {
    try emitConst(self, "@as(u32, 0o120000)");
}

fn genSIFSOCK(self: *h.NativeCodegen, _: []ast.Node) h.CodegenError!void {
    try emitConst(self, "@as(u32, 0o140000)");
}

// Permission bits
fn genSISUID(self: *h.NativeCodegen, _: []ast.Node) h.CodegenError!void {
    try emitConst(self, "@as(u32, 0o4000)");
}

fn genSISGID(self: *h.NativeCodegen, _: []ast.Node) h.CodegenError!void {
    try emitConst(self, "@as(u32, 0o2000)");
}

fn genSISVTX(self: *h.NativeCodegen, _: []ast.Node) h.CodegenError!void {
    try emitConst(self, "@as(u32, 0o1000)");
}

fn genSIRWXU(self: *h.NativeCodegen, _: []ast.Node) h.CodegenError!void {
    try emitConst(self, "@as(u32, 0o700)");
}

fn genSIRUSR(self: *h.NativeCodegen, _: []ast.Node) h.CodegenError!void {
    try emitConst(self, "@as(u32, 0o400)");
}

fn genSIWUSR(self: *h.NativeCodegen, _: []ast.Node) h.CodegenError!void {
    try emitConst(self, "@as(u32, 0o200)");
}

fn genSIXUSR(self: *h.NativeCodegen, _: []ast.Node) h.CodegenError!void {
    try emitConst(self, "@as(u32, 0o100)");
}

fn genSIRWXG(self: *h.NativeCodegen, _: []ast.Node) h.CodegenError!void {
    try emitConst(self, "@as(u32, 0o070)");
}

fn genSIRGRP(self: *h.NativeCodegen, _: []ast.Node) h.CodegenError!void {
    try emitConst(self, "@as(u32, 0o040)");
}

fn genSIWGRP(self: *h.NativeCodegen, _: []ast.Node) h.CodegenError!void {
    try emitConst(self, "@as(u32, 0o020)");
}

fn genSIXGRP(self: *h.NativeCodegen, _: []ast.Node) h.CodegenError!void {
    try emitConst(self, "@as(u32, 0o010)");
}

fn genSIRWXO(self: *h.NativeCodegen, _: []ast.Node) h.CodegenError!void {
    try emitConst(self, "@as(u32, 0o007)");
}

fn genSIROTH(self: *h.NativeCodegen, _: []ast.Node) h.CodegenError!void {
    try emitConst(self, "@as(u32, 0o004)");
}

fn genSIWOTH(self: *h.NativeCodegen, _: []ast.Node) h.CodegenError!void {
    try emitConst(self, "@as(u32, 0o002)");
}

fn genSIXOTH(self: *h.NativeCodegen, _: []ast.Node) h.CodegenError!void {
    try emitConst(self, "@as(u32, 0o001)");
}

// Type test functions
fn genSISDIR(self: *h.NativeCodegen, args: []ast.Node) h.CodegenError!void {
    if (args.len > 0) {
        {
            const b = try self.getBuilder();
            try b.write("((");
            const output = b.getBodyAndClear();
            try self.output.appendSlice(self.allocator, output);
        }
        try self.genExpr(args[0]);
        {
            const b = try self.getBuilder();
            try b.write(" & 0o170000) == 0o040000)");
            const output = b.getBodyAndClear();
            try self.output.appendSlice(self.allocator, output);
        }
    } else {
        try emitConst(self, "false");
    }
}

fn genSISCHR(self: *h.NativeCodegen, args: []ast.Node) h.CodegenError!void {
    if (args.len > 0) {
        {
            const b = try self.getBuilder();
            try b.write("((");
            const output = b.getBodyAndClear();
            try self.output.appendSlice(self.allocator, output);
        }
        try self.genExpr(args[0]);
        {
            const b = try self.getBuilder();
            try b.write(" & 0o170000) == 0o020000)");
            const output = b.getBodyAndClear();
            try self.output.appendSlice(self.allocator, output);
        }
    } else {
        try emitConst(self, "false");
    }
}

fn genSISBLK(self: *h.NativeCodegen, args: []ast.Node) h.CodegenError!void {
    if (args.len > 0) {
        {
            const b = try self.getBuilder();
            try b.write("((");
            const output = b.getBodyAndClear();
            try self.output.appendSlice(self.allocator, output);
        }
        try self.genExpr(args[0]);
        {
            const b = try self.getBuilder();
            try b.write(" & 0o170000) == 0o060000)");
            const output = b.getBodyAndClear();
            try self.output.appendSlice(self.allocator, output);
        }
    } else {
        try emitConst(self, "false");
    }
}

fn genSISREG(self: *h.NativeCodegen, args: []ast.Node) h.CodegenError!void {
    if (args.len > 0) {
        {
            const b = try self.getBuilder();
            try b.write("((");
            const output = b.getBodyAndClear();
            try self.output.appendSlice(self.allocator, output);
        }
        try self.genExpr(args[0]);
        {
            const b = try self.getBuilder();
            try b.write(" & 0o170000) == 0o100000)");
            const output = b.getBodyAndClear();
            try self.output.appendSlice(self.allocator, output);
        }
    } else {
        try emitConst(self, "false");
    }
}

fn genSISFIFO(self: *h.NativeCodegen, args: []ast.Node) h.CodegenError!void {
    if (args.len > 0) {
        {
            const b = try self.getBuilder();
            try b.write("((");
            const output = b.getBodyAndClear();
            try self.output.appendSlice(self.allocator, output);
        }
        try self.genExpr(args[0]);
        {
            const b = try self.getBuilder();
            try b.write(" & 0o170000) == 0o010000)");
            const output = b.getBodyAndClear();
            try self.output.appendSlice(self.allocator, output);
        }
    } else {
        try emitConst(self, "false");
    }
}

fn genSISLNK(self: *h.NativeCodegen, args: []ast.Node) h.CodegenError!void {
    if (args.len > 0) {
        {
            const b = try self.getBuilder();
            try b.write("((");
            const output = b.getBodyAndClear();
            try self.output.appendSlice(self.allocator, output);
        }
        try self.genExpr(args[0]);
        {
            const b = try self.getBuilder();
            try b.write(" & 0o170000) == 0o120000)");
            const output = b.getBodyAndClear();
            try self.output.appendSlice(self.allocator, output);
        }
    } else {
        try emitConst(self, "false");
    }
}

fn genSISSOCK(self: *h.NativeCodegen, args: []ast.Node) h.CodegenError!void {
    if (args.len > 0) {
        {
            const b = try self.getBuilder();
            try b.write("((");
            const output = b.getBodyAndClear();
            try self.output.appendSlice(self.allocator, output);
        }
        try self.genExpr(args[0]);
        {
            const b = try self.getBuilder();
            try b.write(" & 0o170000) == 0o140000)");
            const output = b.getBodyAndClear();
            try self.output.appendSlice(self.allocator, output);
        }
    } else {
        try emitConst(self, "false");
    }
}

fn genSIMODE(self: *h.NativeCodegen, args: []ast.Node) h.CodegenError!void {
    if (args.len > 0) {
        {
            const b = try self.getBuilder();
            try b.write("(");
            const output = b.getBodyAndClear();
            try self.output.appendSlice(self.allocator, output);
        }
        try self.genExpr(args[0]);
        {
            const b = try self.getBuilder();
            try b.write(" & 0o7777)");
            const output = b.getBodyAndClear();
            try self.output.appendSlice(self.allocator, output);
        }
    } else {
        try emitConst(self, "@as(u32, 0)");
    }
}

fn genFilemode(self: *h.NativeCodegen, args: []ast.Node) h.CodegenError!void {
    if (args.len == 0) {
        try emitConst(self, "\"----------\"");
        return;
    }
    try self.withInlineBlock("fm", args, struct {
        fn emit(c: *h.NativeCodegen, label: []const u8, a: []ast.Node) !void {
            const b = try c.getBuilder();
            try b.write("const mode = ");
            const output1 = b.getBodyAndClear();
            try c.output.appendSlice(c.allocator, output1);
            try c.genExpr(a[0]);
            {
                const b2 = try c.getBuilder();
                try b2.writeFmt("; var perm: [10]u8 = \"----------\".*; if ((mode & 0o170000) == 0o040000) perm[0] = 'd'; if ((mode & 0o400) != 0) perm[1] = 'r'; if ((mode & 0o200) != 0) perm[2] = 'w'; if ((mode & 0o100) != 0) perm[3] = 'x'; if ((mode & 0o040) != 0) perm[4] = 'r'; if ((mode & 0o020) != 0) perm[5] = 'w'; if ((mode & 0o010) != 0) perm[6] = 'x'; if ((mode & 0o004) != 0) perm[7] = 'r'; if ((mode & 0o002) != 0) perm[8] = 'w'; if ((mode & 0o001) != 0) perm[9] = 'x'; break :{s} &perm", .{label});
                const output2 = b2.getBodyAndClear();
                try c.output.appendSlice(c.allocator, output2);
            }
        }
    }.emit);
}

// stat_result field indices
fn genSTMODE(self: *h.NativeCodegen, _: []ast.Node) h.CodegenError!void {
    try emitConst(self, "@as(i32, 0)");
}

fn genSTINO(self: *h.NativeCodegen, _: []ast.Node) h.CodegenError!void {
    try emitConst(self, "@as(i32, 1)");
}

fn genSTDEV(self: *h.NativeCodegen, _: []ast.Node) h.CodegenError!void {
    try emitConst(self, "@as(i32, 2)");
}

fn genSTNLINK(self: *h.NativeCodegen, _: []ast.Node) h.CodegenError!void {
    try emitConst(self, "@as(i32, 3)");
}

fn genSTUID(self: *h.NativeCodegen, _: []ast.Node) h.CodegenError!void {
    try emitConst(self, "@as(i32, 4)");
}

fn genSTGID(self: *h.NativeCodegen, _: []ast.Node) h.CodegenError!void {
    try emitConst(self, "@as(i32, 5)");
}

fn genSTSIZE(self: *h.NativeCodegen, _: []ast.Node) h.CodegenError!void {
    try emitConst(self, "@as(i32, 6)");
}

fn genSTATIME(self: *h.NativeCodegen, _: []ast.Node) h.CodegenError!void {
    try emitConst(self, "@as(i32, 7)");
}

fn genSTMTIME(self: *h.NativeCodegen, _: []ast.Node) h.CodegenError!void {
    try emitConst(self, "@as(i32, 8)");
}

fn genSTCTIME(self: *h.NativeCodegen, _: []ast.Node) h.CodegenError!void {
    try emitConst(self, "@as(i32, 9)");
}

// Windows file attributes
fn genFILEATTRIBUTEARCHIVE(self: *h.NativeCodegen, _: []ast.Node) h.CodegenError!void {
    try emitConst(self, "@as(u32, 32)");
}

fn genFILEATTRIBUTECOMPRESSED(self: *h.NativeCodegen, _: []ast.Node) h.CodegenError!void {
    try emitConst(self, "@as(u32, 2048)");
}

fn genFILEATTRIBUTEDEVICE(self: *h.NativeCodegen, _: []ast.Node) h.CodegenError!void {
    try emitConst(self, "@as(u32, 64)");
}

fn genFILEATTRIBUTEDIRECTORY(self: *h.NativeCodegen, _: []ast.Node) h.CodegenError!void {
    try emitConst(self, "@as(u32, 16)");
}

fn genFILEATTRIBUTEENCRYPTED(self: *h.NativeCodegen, _: []ast.Node) h.CodegenError!void {
    try emitConst(self, "@as(u32, 16384)");
}

fn genFILEATTRIBUTEHIDDEN(self: *h.NativeCodegen, _: []ast.Node) h.CodegenError!void {
    try emitConst(self, "@as(u32, 2)");
}

fn genFILEATTRIBUTENORMAL(self: *h.NativeCodegen, _: []ast.Node) h.CodegenError!void {
    try emitConst(self, "@as(u32, 128)");
}

fn genFILEATTRIBUTENOTCONTENTINDEXED(self: *h.NativeCodegen, _: []ast.Node) h.CodegenError!void {
    try emitConst(self, "@as(u32, 8192)");
}

fn genFILEATTRIBUTEOFFLINE(self: *h.NativeCodegen, _: []ast.Node) h.CodegenError!void {
    try emitConst(self, "@as(u32, 4096)");
}

fn genFILEATTRIBUTEREADONLY(self: *h.NativeCodegen, _: []ast.Node) h.CodegenError!void {
    try emitConst(self, "@as(u32, 1)");
}

fn genFILEATTRIBUTEREPARSEPOINT(self: *h.NativeCodegen, _: []ast.Node) h.CodegenError!void {
    try emitConst(self, "@as(u32, 1024)");
}

fn genFILEATTRIBUTESPARSEFILE(self: *h.NativeCodegen, _: []ast.Node) h.CodegenError!void {
    try emitConst(self, "@as(u32, 512)");
}

fn genFILEATTRIBUTESYSTEM(self: *h.NativeCodegen, _: []ast.Node) h.CodegenError!void {
    try emitConst(self, "@as(u32, 4)");
}

fn genFILEATTRIBUTETEMPORARY(self: *h.NativeCodegen, _: []ast.Node) h.CodegenError!void {
    try emitConst(self, "@as(u32, 256)");
}

fn genFILEATTRIBUTEVIRTUAL(self: *h.NativeCodegen, _: []ast.Node) h.CodegenError!void {
    try emitConst(self, "@as(u32, 65536)");
}
