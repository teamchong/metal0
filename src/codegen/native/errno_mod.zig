/// Python errno module - Standard errno system symbols
/// MIGRATED TO ZIGBUILDER
const std = @import("std");
const h = @import("mod_helper.zig");
const builder_mod = @import("codegen.builder");
const ast = @import("analysis.ast");

pub const Funcs = std.StaticStringMap(h.H).initComptime(.{
    .{ "errorcode", genErrorcode },
    .{ "EPERM", genEPERM },
    .{ "ENOENT", genENOENT },
    .{ "ESRCH", genESRCH },
    .{ "EINTR", genEINTR },
    .{ "EIO", genEIO },
    .{ "ENXIO", genENXIO },
    .{ "E2BIG", genE2BIG },
    .{ "ENOEXEC", genENOEXEC },
    .{ "EBADF", genEBADF },
    .{ "ECHILD", genECHILD },
    .{ "EAGAIN", genEAGAIN },
    .{ "EWOULDBLOCK", genEWOULDBLOCK },
    .{ "ENOMEM", genENOMEM },
    .{ "EACCES", genEACCES },
    .{ "EFAULT", genEFAULT },
    .{ "ENOTBLK", genENOTBLK },
    .{ "EBUSY", genEBUSY },
    .{ "EEXIST", genEEXIST },
    .{ "EXDEV", genEXDEV },
    .{ "ENODEV", genENODEV },
    .{ "ENOTDIR", genENOTDIR },
    .{ "EISDIR", genEISDIR },
    .{ "EINVAL", genEINVAL },
    .{ "ENFILE", genENFILE },
    .{ "EMFILE", genEMFILE },
    .{ "ENOTTY", genENOTTY },
    .{ "ETXTBSY", genETXTBSY },
    .{ "EFBIG", genEFBIG },
    .{ "ENOSPC", genENOSPC },
    .{ "ESPIPE", genESPIPE },
    .{ "EROFS", genEROFS },
    .{ "EMLINK", genEMLINK },
    .{ "EPIPE", genEPIPE },
    .{ "EDOM", genEDOM },
    .{ "ERANGE", genERANGE },
    .{ "EDEADLK", genEDEADLK },
    .{ "ENAMETOOLONG", genENAMETOOLONG },
    .{ "ENOLCK", genENOLCK },
    .{ "ENOSYS", genENOSYS },
    .{ "ENOTEMPTY", genENOTEMPTY },
    .{ "ELOOP", genELOOP },
    .{ "ENOMSG", genENOMSG },
    .{ "EIDRM", genEIDRM },
    .{ "ECHRNG", genECHRNG },
    .{ "ENOSTR", genENOSTR },
    .{ "ENODATA", genENODATA },
    .{ "ETIME", genETIME },
    .{ "ENOSR", genENOSR },
    .{ "EOVERFLOW", genEOVERFLOW },
    .{ "ENOTSOCK", genENOTSOCK },
    .{ "EDESTADDRREQ", genEDESTADDRREQ },
    .{ "EMSGSIZE", genEMSGSIZE },
    .{ "EPROTOTYPE", genEPROTOTYPE },
    .{ "ENOPROTOOPT", genENOPROTOOPT },
    .{ "EPROTONOSUPPORT", genEPROTONOSUPPORT },
    .{ "ESOCKTNOSUPPORT", genESOCKTNOSUPPORT },
    .{ "EOPNOTSUPP", genEOPNOTSUPP },
    .{ "EPFNOSUPPORT", genEPFNOSUPPORT },
    .{ "EAFNOSUPPORT", genEAFNOSUPPORT },
    .{ "EADDRINUSE", genEADDRINUSE },
    .{ "EADDRNOTAVAIL", genEADDRNOTAVAIL },
    .{ "ENETDOWN", genENETDOWN },
    .{ "ENETUNREACH", genENETUNREACH },
    .{ "ENETRESET", genENETRESET },
    .{ "ECONNABORTED", genECONNABORTED },
    .{ "ECONNRESET", genECONNRESET },
    .{ "ENOBUFS", genENOBUFS },
    .{ "EISCONN", genEISCONN },
    .{ "ENOTCONN", genENOTCONN },
    .{ "ESHUTDOWN", genESHUTDOWN },
    .{ "ETOOMANYREFS", genETOOMANYREFS },
    .{ "ETIMEDOUT", genETIMEDOUT },
    .{ "ECONNREFUSED", genECONNREFUSED },
    .{ "EHOSTDOWN", genEHOSTDOWN },
    .{ "EHOSTUNREACH", genEHOSTUNREACH },
    .{ "EALREADY", genEALREADY },
    .{ "EINPROGRESS", genEINPROGRESS },
    .{ "ESTALE", genESTALE },
    .{ "ECANCELED", genECANCELED },
    .{ "ENOKEY", genENOKEY },
    .{ "EKEYEXPIRED", genEKEYEXPIRED },
    .{ "EKEYREVOKED", genEKEYREVOKED },
    .{ "EKEYREJECTED", genEKEYREJECTED },
});

fn genErrorcode(self: *h.NativeCodegen, _: []ast.Node) h.CodegenError!void {
    const b = try self.getBuilder();
    try b.emitValue(builder_mod.ZigValue.raw("hashmap_helper.StringHashMap([]const u8).init(__global_allocator)"), builder_mod.EmitConfig.forExpression());
}

fn genEPERM(self: *h.NativeCodegen, _: []ast.Node) h.CodegenError!void {
    const b = try self.getBuilder();
    try b.emitValue(builder_mod.ZigValue.int(1), builder_mod.EmitConfig.forExpression());
}

fn genENOENT(self: *h.NativeCodegen, _: []ast.Node) h.CodegenError!void {
    const b = try self.getBuilder();
    try b.emitValue(builder_mod.ZigValue.int(2), builder_mod.EmitConfig.forExpression());
}

fn genESRCH(self: *h.NativeCodegen, _: []ast.Node) h.CodegenError!void {
    const b = try self.getBuilder();
    try b.emitValue(builder_mod.ZigValue.int(3), builder_mod.EmitConfig.forExpression());
}

fn genEINTR(self: *h.NativeCodegen, _: []ast.Node) h.CodegenError!void {
    const b = try self.getBuilder();
    try b.emitValue(builder_mod.ZigValue.int(4), builder_mod.EmitConfig.forExpression());
}

fn genEIO(self: *h.NativeCodegen, _: []ast.Node) h.CodegenError!void {
    const b = try self.getBuilder();
    try b.emitValue(builder_mod.ZigValue.int(5), builder_mod.EmitConfig.forExpression());
}

fn genENXIO(self: *h.NativeCodegen, _: []ast.Node) h.CodegenError!void {
    const b = try self.getBuilder();
    try b.emitValue(builder_mod.ZigValue.int(6), builder_mod.EmitConfig.forExpression());
}

fn genE2BIG(self: *h.NativeCodegen, _: []ast.Node) h.CodegenError!void {
    const b = try self.getBuilder();
    try b.emitValue(builder_mod.ZigValue.int(7), builder_mod.EmitConfig.forExpression());
}

fn genENOEXEC(self: *h.NativeCodegen, _: []ast.Node) h.CodegenError!void {
    const b = try self.getBuilder();
    try b.emitValue(builder_mod.ZigValue.int(8), builder_mod.EmitConfig.forExpression());
}

fn genEBADF(self: *h.NativeCodegen, _: []ast.Node) h.CodegenError!void {
    const b = try self.getBuilder();
    try b.emitValue(builder_mod.ZigValue.int(9), builder_mod.EmitConfig.forExpression());
}

fn genECHILD(self: *h.NativeCodegen, _: []ast.Node) h.CodegenError!void {
    const b = try self.getBuilder();
    try b.emitValue(builder_mod.ZigValue.int(10), builder_mod.EmitConfig.forExpression());
}

fn genEAGAIN(self: *h.NativeCodegen, _: []ast.Node) h.CodegenError!void {
    const b = try self.getBuilder();
    try b.emitValue(builder_mod.ZigValue.int(11), builder_mod.EmitConfig.forExpression());
}

fn genEWOULDBLOCK(self: *h.NativeCodegen, _: []ast.Node) h.CodegenError!void {
    const b = try self.getBuilder();
    try b.emitValue(builder_mod.ZigValue.int(11), builder_mod.EmitConfig.forExpression());
}

fn genENOMEM(self: *h.NativeCodegen, _: []ast.Node) h.CodegenError!void {
    const b = try self.getBuilder();
    try b.emitValue(builder_mod.ZigValue.int(12), builder_mod.EmitConfig.forExpression());
}

fn genEACCES(self: *h.NativeCodegen, _: []ast.Node) h.CodegenError!void {
    const b = try self.getBuilder();
    try b.emitValue(builder_mod.ZigValue.int(13), builder_mod.EmitConfig.forExpression());
}

fn genEFAULT(self: *h.NativeCodegen, _: []ast.Node) h.CodegenError!void {
    const b = try self.getBuilder();
    try b.emitValue(builder_mod.ZigValue.int(14), builder_mod.EmitConfig.forExpression());
}

fn genENOTBLK(self: *h.NativeCodegen, _: []ast.Node) h.CodegenError!void {
    const b = try self.getBuilder();
    try b.emitValue(builder_mod.ZigValue.int(15), builder_mod.EmitConfig.forExpression());
}

fn genEBUSY(self: *h.NativeCodegen, _: []ast.Node) h.CodegenError!void {
    const b = try self.getBuilder();
    try b.emitValue(builder_mod.ZigValue.int(16), builder_mod.EmitConfig.forExpression());
}

fn genEEXIST(self: *h.NativeCodegen, _: []ast.Node) h.CodegenError!void {
    const b = try self.getBuilder();
    try b.emitValue(builder_mod.ZigValue.int(17), builder_mod.EmitConfig.forExpression());
}

fn genEXDEV(self: *h.NativeCodegen, _: []ast.Node) h.CodegenError!void {
    const b = try self.getBuilder();
    try b.emitValue(builder_mod.ZigValue.int(18), builder_mod.EmitConfig.forExpression());
}

fn genENODEV(self: *h.NativeCodegen, _: []ast.Node) h.CodegenError!void {
    const b = try self.getBuilder();
    try b.emitValue(builder_mod.ZigValue.int(19), builder_mod.EmitConfig.forExpression());
}

fn genENOTDIR(self: *h.NativeCodegen, _: []ast.Node) h.CodegenError!void {
    const b = try self.getBuilder();
    try b.emitValue(builder_mod.ZigValue.int(20), builder_mod.EmitConfig.forExpression());
}

fn genEISDIR(self: *h.NativeCodegen, _: []ast.Node) h.CodegenError!void {
    const b = try self.getBuilder();
    try b.emitValue(builder_mod.ZigValue.int(21), builder_mod.EmitConfig.forExpression());
}

fn genEINVAL(self: *h.NativeCodegen, _: []ast.Node) h.CodegenError!void {
    const b = try self.getBuilder();
    try b.emitValue(builder_mod.ZigValue.int(22), builder_mod.EmitConfig.forExpression());
}

fn genENFILE(self: *h.NativeCodegen, _: []ast.Node) h.CodegenError!void {
    const b = try self.getBuilder();
    try b.emitValue(builder_mod.ZigValue.int(23), builder_mod.EmitConfig.forExpression());
}

fn genEMFILE(self: *h.NativeCodegen, _: []ast.Node) h.CodegenError!void {
    const b = try self.getBuilder();
    try b.emitValue(builder_mod.ZigValue.int(24), builder_mod.EmitConfig.forExpression());
}

fn genENOTTY(self: *h.NativeCodegen, _: []ast.Node) h.CodegenError!void {
    const b = try self.getBuilder();
    try b.emitValue(builder_mod.ZigValue.int(25), builder_mod.EmitConfig.forExpression());
}

fn genETXTBSY(self: *h.NativeCodegen, _: []ast.Node) h.CodegenError!void {
    const b = try self.getBuilder();
    try b.emitValue(builder_mod.ZigValue.int(26), builder_mod.EmitConfig.forExpression());
}

fn genEFBIG(self: *h.NativeCodegen, _: []ast.Node) h.CodegenError!void {
    const b = try self.getBuilder();
    try b.emitValue(builder_mod.ZigValue.int(27), builder_mod.EmitConfig.forExpression());
}

fn genENOSPC(self: *h.NativeCodegen, _: []ast.Node) h.CodegenError!void {
    const b = try self.getBuilder();
    try b.emitValue(builder_mod.ZigValue.int(28), builder_mod.EmitConfig.forExpression());
}

fn genESPIPE(self: *h.NativeCodegen, _: []ast.Node) h.CodegenError!void {
    const b = try self.getBuilder();
    try b.emitValue(builder_mod.ZigValue.int(29), builder_mod.EmitConfig.forExpression());
}

fn genEROFS(self: *h.NativeCodegen, _: []ast.Node) h.CodegenError!void {
    const b = try self.getBuilder();
    try b.emitValue(builder_mod.ZigValue.int(30), builder_mod.EmitConfig.forExpression());
}

fn genEMLINK(self: *h.NativeCodegen, _: []ast.Node) h.CodegenError!void {
    const b = try self.getBuilder();
    try b.emitValue(builder_mod.ZigValue.int(31), builder_mod.EmitConfig.forExpression());
}

fn genEPIPE(self: *h.NativeCodegen, _: []ast.Node) h.CodegenError!void {
    const b = try self.getBuilder();
    try b.emitValue(builder_mod.ZigValue.int(32), builder_mod.EmitConfig.forExpression());
}

fn genEDOM(self: *h.NativeCodegen, _: []ast.Node) h.CodegenError!void {
    const b = try self.getBuilder();
    try b.emitValue(builder_mod.ZigValue.int(33), builder_mod.EmitConfig.forExpression());
}

fn genERANGE(self: *h.NativeCodegen, _: []ast.Node) h.CodegenError!void {
    const b = try self.getBuilder();
    try b.emitValue(builder_mod.ZigValue.int(34), builder_mod.EmitConfig.forExpression());
}

fn genEDEADLK(self: *h.NativeCodegen, _: []ast.Node) h.CodegenError!void {
    const b = try self.getBuilder();
    try b.emitValue(builder_mod.ZigValue.int(35), builder_mod.EmitConfig.forExpression());
}

fn genENAMETOOLONG(self: *h.NativeCodegen, _: []ast.Node) h.CodegenError!void {
    const b = try self.getBuilder();
    try b.emitValue(builder_mod.ZigValue.int(36), builder_mod.EmitConfig.forExpression());
}

fn genENOLCK(self: *h.NativeCodegen, _: []ast.Node) h.CodegenError!void {
    const b = try self.getBuilder();
    try b.emitValue(builder_mod.ZigValue.int(37), builder_mod.EmitConfig.forExpression());
}

fn genENOSYS(self: *h.NativeCodegen, _: []ast.Node) h.CodegenError!void {
    const b = try self.getBuilder();
    try b.emitValue(builder_mod.ZigValue.int(38), builder_mod.EmitConfig.forExpression());
}

fn genENOTEMPTY(self: *h.NativeCodegen, _: []ast.Node) h.CodegenError!void {
    const b = try self.getBuilder();
    try b.emitValue(builder_mod.ZigValue.int(39), builder_mod.EmitConfig.forExpression());
}

fn genELOOP(self: *h.NativeCodegen, _: []ast.Node) h.CodegenError!void {
    const b = try self.getBuilder();
    try b.emitValue(builder_mod.ZigValue.int(40), builder_mod.EmitConfig.forExpression());
}

fn genENOMSG(self: *h.NativeCodegen, _: []ast.Node) h.CodegenError!void {
    const b = try self.getBuilder();
    try b.emitValue(builder_mod.ZigValue.int(42), builder_mod.EmitConfig.forExpression());
}

fn genEIDRM(self: *h.NativeCodegen, _: []ast.Node) h.CodegenError!void {
    const b = try self.getBuilder();
    try b.emitValue(builder_mod.ZigValue.int(43), builder_mod.EmitConfig.forExpression());
}

fn genECHRNG(self: *h.NativeCodegen, _: []ast.Node) h.CodegenError!void {
    const b = try self.getBuilder();
    try b.emitValue(builder_mod.ZigValue.int(44), builder_mod.EmitConfig.forExpression());
}

fn genENOSTR(self: *h.NativeCodegen, _: []ast.Node) h.CodegenError!void {
    const b = try self.getBuilder();
    try b.emitValue(builder_mod.ZigValue.int(60), builder_mod.EmitConfig.forExpression());
}

fn genENODATA(self: *h.NativeCodegen, _: []ast.Node) h.CodegenError!void {
    const b = try self.getBuilder();
    try b.emitValue(builder_mod.ZigValue.int(61), builder_mod.EmitConfig.forExpression());
}

fn genETIME(self: *h.NativeCodegen, _: []ast.Node) h.CodegenError!void {
    const b = try self.getBuilder();
    try b.emitValue(builder_mod.ZigValue.int(62), builder_mod.EmitConfig.forExpression());
}

fn genENOSR(self: *h.NativeCodegen, _: []ast.Node) h.CodegenError!void {
    const b = try self.getBuilder();
    try b.emitValue(builder_mod.ZigValue.int(63), builder_mod.EmitConfig.forExpression());
}

fn genEOVERFLOW(self: *h.NativeCodegen, _: []ast.Node) h.CodegenError!void {
    const b = try self.getBuilder();
    try b.emitValue(builder_mod.ZigValue.int(75), builder_mod.EmitConfig.forExpression());
}

fn genENOTSOCK(self: *h.NativeCodegen, _: []ast.Node) h.CodegenError!void {
    const b = try self.getBuilder();
    try b.emitValue(builder_mod.ZigValue.int(88), builder_mod.EmitConfig.forExpression());
}

fn genEDESTADDRREQ(self: *h.NativeCodegen, _: []ast.Node) h.CodegenError!void {
    const b = try self.getBuilder();
    try b.emitValue(builder_mod.ZigValue.int(89), builder_mod.EmitConfig.forExpression());
}

fn genEMSGSIZE(self: *h.NativeCodegen, _: []ast.Node) h.CodegenError!void {
    const b = try self.getBuilder();
    try b.emitValue(builder_mod.ZigValue.int(90), builder_mod.EmitConfig.forExpression());
}

fn genEPROTOTYPE(self: *h.NativeCodegen, _: []ast.Node) h.CodegenError!void {
    const b = try self.getBuilder();
    try b.emitValue(builder_mod.ZigValue.int(91), builder_mod.EmitConfig.forExpression());
}

fn genENOPROTOOPT(self: *h.NativeCodegen, _: []ast.Node) h.CodegenError!void {
    const b = try self.getBuilder();
    try b.emitValue(builder_mod.ZigValue.int(92), builder_mod.EmitConfig.forExpression());
}

fn genEPROTONOSUPPORT(self: *h.NativeCodegen, _: []ast.Node) h.CodegenError!void {
    const b = try self.getBuilder();
    try b.emitValue(builder_mod.ZigValue.int(93), builder_mod.EmitConfig.forExpression());
}

fn genESOCKTNOSUPPORT(self: *h.NativeCodegen, _: []ast.Node) h.CodegenError!void {
    const b = try self.getBuilder();
    try b.emitValue(builder_mod.ZigValue.int(94), builder_mod.EmitConfig.forExpression());
}

fn genEOPNOTSUPP(self: *h.NativeCodegen, _: []ast.Node) h.CodegenError!void {
    const b = try self.getBuilder();
    try b.emitValue(builder_mod.ZigValue.int(95), builder_mod.EmitConfig.forExpression());
}

fn genEPFNOSUPPORT(self: *h.NativeCodegen, _: []ast.Node) h.CodegenError!void {
    const b = try self.getBuilder();
    try b.emitValue(builder_mod.ZigValue.int(96), builder_mod.EmitConfig.forExpression());
}

fn genEAFNOSUPPORT(self: *h.NativeCodegen, _: []ast.Node) h.CodegenError!void {
    const b = try self.getBuilder();
    try b.emitValue(builder_mod.ZigValue.int(97), builder_mod.EmitConfig.forExpression());
}

fn genEADDRINUSE(self: *h.NativeCodegen, _: []ast.Node) h.CodegenError!void {
    const b = try self.getBuilder();
    try b.emitValue(builder_mod.ZigValue.int(98), builder_mod.EmitConfig.forExpression());
}

fn genEADDRNOTAVAIL(self: *h.NativeCodegen, _: []ast.Node) h.CodegenError!void {
    const b = try self.getBuilder();
    try b.emitValue(builder_mod.ZigValue.int(99), builder_mod.EmitConfig.forExpression());
}

fn genENETDOWN(self: *h.NativeCodegen, _: []ast.Node) h.CodegenError!void {
    const b = try self.getBuilder();
    try b.emitValue(builder_mod.ZigValue.int(100), builder_mod.EmitConfig.forExpression());
}

fn genENETUNREACH(self: *h.NativeCodegen, _: []ast.Node) h.CodegenError!void {
    const b = try self.getBuilder();
    try b.emitValue(builder_mod.ZigValue.int(101), builder_mod.EmitConfig.forExpression());
}

fn genENETRESET(self: *h.NativeCodegen, _: []ast.Node) h.CodegenError!void {
    const b = try self.getBuilder();
    try b.emitValue(builder_mod.ZigValue.int(102), builder_mod.EmitConfig.forExpression());
}

fn genECONNABORTED(self: *h.NativeCodegen, _: []ast.Node) h.CodegenError!void {
    const b = try self.getBuilder();
    try b.emitValue(builder_mod.ZigValue.int(103), builder_mod.EmitConfig.forExpression());
}

fn genECONNRESET(self: *h.NativeCodegen, _: []ast.Node) h.CodegenError!void {
    const b = try self.getBuilder();
    try b.emitValue(builder_mod.ZigValue.int(104), builder_mod.EmitConfig.forExpression());
}

fn genENOBUFS(self: *h.NativeCodegen, _: []ast.Node) h.CodegenError!void {
    const b = try self.getBuilder();
    try b.emitValue(builder_mod.ZigValue.int(105), builder_mod.EmitConfig.forExpression());
}

fn genEISCONN(self: *h.NativeCodegen, _: []ast.Node) h.CodegenError!void {
    const b = try self.getBuilder();
    try b.emitValue(builder_mod.ZigValue.int(106), builder_mod.EmitConfig.forExpression());
}

fn genENOTCONN(self: *h.NativeCodegen, _: []ast.Node) h.CodegenError!void {
    const b = try self.getBuilder();
    try b.emitValue(builder_mod.ZigValue.int(107), builder_mod.EmitConfig.forExpression());
}

fn genESHUTDOWN(self: *h.NativeCodegen, _: []ast.Node) h.CodegenError!void {
    const b = try self.getBuilder();
    try b.emitValue(builder_mod.ZigValue.int(108), builder_mod.EmitConfig.forExpression());
}

fn genETOOMANYREFS(self: *h.NativeCodegen, _: []ast.Node) h.CodegenError!void {
    const b = try self.getBuilder();
    try b.emitValue(builder_mod.ZigValue.int(109), builder_mod.EmitConfig.forExpression());
}

fn genETIMEDOUT(self: *h.NativeCodegen, _: []ast.Node) h.CodegenError!void {
    const b = try self.getBuilder();
    try b.emitValue(builder_mod.ZigValue.int(110), builder_mod.EmitConfig.forExpression());
}

fn genECONNREFUSED(self: *h.NativeCodegen, _: []ast.Node) h.CodegenError!void {
    const b = try self.getBuilder();
    try b.emitValue(builder_mod.ZigValue.int(111), builder_mod.EmitConfig.forExpression());
}

fn genEHOSTDOWN(self: *h.NativeCodegen, _: []ast.Node) h.CodegenError!void {
    const b = try self.getBuilder();
    try b.emitValue(builder_mod.ZigValue.int(112), builder_mod.EmitConfig.forExpression());
}

fn genEHOSTUNREACH(self: *h.NativeCodegen, _: []ast.Node) h.CodegenError!void {
    const b = try self.getBuilder();
    try b.emitValue(builder_mod.ZigValue.int(113), builder_mod.EmitConfig.forExpression());
}

fn genEALREADY(self: *h.NativeCodegen, _: []ast.Node) h.CodegenError!void {
    const b = try self.getBuilder();
    try b.emitValue(builder_mod.ZigValue.int(114), builder_mod.EmitConfig.forExpression());
}

fn genEINPROGRESS(self: *h.NativeCodegen, _: []ast.Node) h.CodegenError!void {
    const b = try self.getBuilder();
    try b.emitValue(builder_mod.ZigValue.int(115), builder_mod.EmitConfig.forExpression());
}

fn genESTALE(self: *h.NativeCodegen, _: []ast.Node) h.CodegenError!void {
    const b = try self.getBuilder();
    try b.emitValue(builder_mod.ZigValue.int(116), builder_mod.EmitConfig.forExpression());
}

fn genECANCELED(self: *h.NativeCodegen, _: []ast.Node) h.CodegenError!void {
    const b = try self.getBuilder();
    try b.emitValue(builder_mod.ZigValue.int(125), builder_mod.EmitConfig.forExpression());
}

fn genENOKEY(self: *h.NativeCodegen, _: []ast.Node) h.CodegenError!void {
    const b = try self.getBuilder();
    try b.emitValue(builder_mod.ZigValue.int(126), builder_mod.EmitConfig.forExpression());
}

fn genEKEYEXPIRED(self: *h.NativeCodegen, _: []ast.Node) h.CodegenError!void {
    const b = try self.getBuilder();
    try b.emitValue(builder_mod.ZigValue.int(127), builder_mod.EmitConfig.forExpression());
}

fn genEKEYREVOKED(self: *h.NativeCodegen, _: []ast.Node) h.CodegenError!void {
    const b = try self.getBuilder();
    try b.emitValue(builder_mod.ZigValue.int(128), builder_mod.EmitConfig.forExpression());
}

fn genEKEYREJECTED(self: *h.NativeCodegen, _: []ast.Node) h.CodegenError!void {
    const b = try self.getBuilder();
    try b.emitValue(builder_mod.ZigValue.int(129), builder_mod.EmitConfig.forExpression());
}
