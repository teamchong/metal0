/// Python termios module - POSIX style tty control
const std = @import("std");
const ast = @import("ast");
const CodegenError = @import("main.zig").CodegenError;
const NativeCodegen = @import("main.zig").NativeCodegen;

const ModuleHandler = *const fn (*NativeCodegen, []ast.Node) CodegenError!void;
pub const Funcs = std.StaticStringMap(ModuleHandler).initComptime(.{
    .{ "tcgetattr", genTcgetattr },
    .{ "tcsetattr", genTcsetattr },
    .{ "tcsendbreak", genTcsendbreak },
    .{ "tcdrain", genTcdrain },
    .{ "tcflush", genTcflush },
    .{ "tcflow", genTcflow },
    .{ "tcgetwinsize", genTcgetwinsize },
    .{ "tcsetwinsize", genTcsetwinsize },
    .{ "TCSANOW", genTCSANOW },
    .{ "TCSADRAIN", genTCSADRAIN },
    .{ "TCSAFLUSH", genTCSAFLUSH },
    .{ "TCIFLUSH", genTCIFLUSH },
    .{ "TCOFLUSH", genTCOFLUSH },
    .{ "TCIOFLUSH", genTCIOFLUSH },
    .{ "TCOOFF", genTCOOFF },
    .{ "TCOON", genTCOON },
    .{ "TCIOFF", genTCIOFF },
    .{ "TCION", genTCION },
    .{ "ECHO", genECHO },
    .{ "ECHOE", genECHOE },
    .{ "ECHOK", genECHOK },
    .{ "ECHONL", genECHONL },
    .{ "ICANON", genICANON },
    .{ "ISIG", genISIG },
    .{ "IEXTEN", genIEXTEN },
    .{ "ICRNL", genICRNL },
    .{ "IXON", genIXON },
    .{ "IXOFF", genIXOFF },
    .{ "OPOST", genOPOST },
    .{ "ONLCR", genONLCR },
    .{ "CS8", genCS8 },
    .{ "CREAD", genCREAD },
    .{ "CLOCAL", genCLOCAL },
    .{ "B9600", genB9600 },
    .{ "B19200", genB19200 },
    .{ "B38400", genB38400 },
    .{ "B57600", genB57600 },
    .{ "B115200", genB115200 },
    .{ "VMIN", genVMIN },
    .{ "VTIME", genVTIME },
    .{ "NCCS", genNCCS },
});

/// Generate termios.tcgetattr(fd)
pub fn genTcgetattr(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    _ = args;
    // Returns [iflag, oflag, cflag, lflag, ispeed, ospeed, cc]
    try self.emit("&[_]u32{ 0, 0, 0, 0, 0, 0 }");
}

/// Generate termios.tcsetattr(fd, when, attributes)
pub fn genTcsetattr(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    _ = args;
    try self.emit("{}");
}

/// Generate termios.tcsendbreak(fd, duration)
pub fn genTcsendbreak(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    _ = args;
    try self.emit("{}");
}

/// Generate termios.tcdrain(fd)
pub fn genTcdrain(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    _ = args;
    try self.emit("{}");
}

/// Generate termios.tcflush(fd, queue)
pub fn genTcflush(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    _ = args;
    try self.emit("{}");
}

/// Generate termios.tcflow(fd, action)
pub fn genTcflow(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    _ = args;
    try self.emit("{}");
}

/// Generate termios.tcgetwinsize(fd)
pub fn genTcgetwinsize(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    _ = args;
    try self.emit(".{ @as(u16, 24), @as(u16, 80) }");
}

/// Generate termios.tcsetwinsize(fd, winsize)
pub fn genTcsetwinsize(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    _ = args;
    try self.emit("{}");
}

// ============================================================================
// tcsetattr when constants
// ============================================================================

pub fn genTCSANOW(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    _ = args;
    try self.emit("@as(i32, 0)");
}

pub fn genTCSADRAIN(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    _ = args;
    try self.emit("@as(i32, 1)");
}

pub fn genTCSAFLUSH(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    _ = args;
    try self.emit("@as(i32, 2)");
}

pub fn genTCSASOFT(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    _ = args;
    try self.emit("@as(i32, 0x10)");
}

// ============================================================================
// tcflush queue constants
// ============================================================================

pub fn genTCIFLUSH(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    _ = args;
    try self.emit("@as(i32, 0)");
}

pub fn genTCOFLUSH(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    _ = args;
    try self.emit("@as(i32, 1)");
}

pub fn genTCIOFLUSH(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    _ = args;
    try self.emit("@as(i32, 2)");
}

// ============================================================================
// tcflow action constants
// ============================================================================

pub fn genTCOOFF(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    _ = args;
    try self.emit("@as(i32, 0)");
}

pub fn genTCOON(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    _ = args;
    try self.emit("@as(i32, 1)");
}

pub fn genTCIOFF(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    _ = args;
    try self.emit("@as(i32, 2)");
}

pub fn genTCION(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    _ = args;
    try self.emit("@as(i32, 3)");
}

// ============================================================================
// Input flags (iflag)
// ============================================================================

pub fn genIGNBRK(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    _ = args;
    try self.emit("@as(u32, 0x00000001)");
}

pub fn genBRKINT(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    _ = args;
    try self.emit("@as(u32, 0x00000002)");
}

pub fn genIGNPAR(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    _ = args;
    try self.emit("@as(u32, 0x00000004)");
}

pub fn genPARMRK(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    _ = args;
    try self.emit("@as(u32, 0x00000008)");
}

pub fn genINPCK(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    _ = args;
    try self.emit("@as(u32, 0x00000010)");
}

pub fn genISTRIP(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    _ = args;
    try self.emit("@as(u32, 0x00000020)");
}

pub fn genINLCR(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    _ = args;
    try self.emit("@as(u32, 0x00000040)");
}

pub fn genIGNCR(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    _ = args;
    try self.emit("@as(u32, 0x00000080)");
}

pub fn genICRNL(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    _ = args;
    try self.emit("@as(u32, 0x00000100)");
}

pub fn genIXON(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    _ = args;
    try self.emit("@as(u32, 0x00000200)");
}

pub fn genIXOFF(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    _ = args;
    try self.emit("@as(u32, 0x00000400)");
}

pub fn genIXANY(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    _ = args;
    try self.emit("@as(u32, 0x00000800)");
}

pub fn genIMAXBEL(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    _ = args;
    try self.emit("@as(u32, 0x00002000)");
}

pub fn genIUTF8(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    _ = args;
    try self.emit("@as(u32, 0x00004000)");
}

// ============================================================================
// Output flags (oflag)
// ============================================================================

pub fn genOPOST(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    _ = args;
    try self.emit("@as(u32, 0x00000001)");
}

pub fn genONLCR(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    _ = args;
    try self.emit("@as(u32, 0x00000002)");
}

pub fn genOCRNL(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    _ = args;
    try self.emit("@as(u32, 0x00000010)");
}

pub fn genONOCR(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    _ = args;
    try self.emit("@as(u32, 0x00000020)");
}

pub fn genONLRET(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    _ = args;
    try self.emit("@as(u32, 0x00000040)");
}

// ============================================================================
// Control flags (cflag)
// ============================================================================

pub fn genCS5(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    _ = args;
    try self.emit("@as(u32, 0x00000000)");
}

pub fn genCS6(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    _ = args;
    try self.emit("@as(u32, 0x00000100)");
}

pub fn genCS7(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    _ = args;
    try self.emit("@as(u32, 0x00000200)");
}

pub fn genCS8(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    _ = args;
    try self.emit("@as(u32, 0x00000300)");
}

pub fn genCSIZE(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    _ = args;
    try self.emit("@as(u32, 0x00000300)");
}

pub fn genCSTOPB(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    _ = args;
    try self.emit("@as(u32, 0x00000400)");
}

pub fn genCREAD(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    _ = args;
    try self.emit("@as(u32, 0x00000800)");
}

pub fn genPARENB(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    _ = args;
    try self.emit("@as(u32, 0x00001000)");
}

pub fn genPARODD(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    _ = args;
    try self.emit("@as(u32, 0x00002000)");
}

pub fn genHUPCL(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    _ = args;
    try self.emit("@as(u32, 0x00004000)");
}

pub fn genCLOCAL(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    _ = args;
    try self.emit("@as(u32, 0x00008000)");
}

// ============================================================================
// Local flags (lflag)
// ============================================================================

pub fn genECHO(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    _ = args;
    try self.emit("@as(u32, 0x00000008)");
}

pub fn genECHOE(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    _ = args;
    try self.emit("@as(u32, 0x00000002)");
}

pub fn genECHOK(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    _ = args;
    try self.emit("@as(u32, 0x00000004)");
}

pub fn genECHONL(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    _ = args;
    try self.emit("@as(u32, 0x00000010)");
}

pub fn genICANON(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    _ = args;
    try self.emit("@as(u32, 0x00000100)");
}

pub fn genISIG(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    _ = args;
    try self.emit("@as(u32, 0x00000080)");
}

pub fn genIEXTEN(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    _ = args;
    try self.emit("@as(u32, 0x00000400)");
}

pub fn genNOFLSH(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    _ = args;
    try self.emit("@as(u32, 0x80000000)");
}

pub fn genTOSTOP(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    _ = args;
    try self.emit("@as(u32, 0x00400000)");
}

// ============================================================================
// Baud rates
// ============================================================================

pub fn genB0(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    _ = args;
    try self.emit("@as(u32, 0)");
}

pub fn genB50(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    _ = args;
    try self.emit("@as(u32, 50)");
}

pub fn genB75(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    _ = args;
    try self.emit("@as(u32, 75)");
}

pub fn genB110(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    _ = args;
    try self.emit("@as(u32, 110)");
}

pub fn genB134(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    _ = args;
    try self.emit("@as(u32, 134)");
}

pub fn genB150(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    _ = args;
    try self.emit("@as(u32, 150)");
}

pub fn genB200(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    _ = args;
    try self.emit("@as(u32, 200)");
}

pub fn genB300(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    _ = args;
    try self.emit("@as(u32, 300)");
}

pub fn genB600(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    _ = args;
    try self.emit("@as(u32, 600)");
}

pub fn genB1200(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    _ = args;
    try self.emit("@as(u32, 1200)");
}

pub fn genB1800(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    _ = args;
    try self.emit("@as(u32, 1800)");
}

pub fn genB2400(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    _ = args;
    try self.emit("@as(u32, 2400)");
}

pub fn genB4800(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    _ = args;
    try self.emit("@as(u32, 4800)");
}

pub fn genB9600(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    _ = args;
    try self.emit("@as(u32, 9600)");
}

pub fn genB19200(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    _ = args;
    try self.emit("@as(u32, 19200)");
}

pub fn genB38400(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    _ = args;
    try self.emit("@as(u32, 38400)");
}

pub fn genB57600(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    _ = args;
    try self.emit("@as(u32, 57600)");
}

pub fn genB115200(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    _ = args;
    try self.emit("@as(u32, 115200)");
}

pub fn genB230400(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    _ = args;
    try self.emit("@as(u32, 230400)");
}

// ============================================================================
// Control character indices
// ============================================================================

pub fn genVEOF(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    _ = args;
    try self.emit("@as(usize, 0)");
}

pub fn genVEOL(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    _ = args;
    try self.emit("@as(usize, 1)");
}

pub fn genVERASE(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    _ = args;
    try self.emit("@as(usize, 3)");
}

pub fn genVINTR(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    _ = args;
    try self.emit("@as(usize, 8)");
}

pub fn genVKILL(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    _ = args;
    try self.emit("@as(usize, 5)");
}

pub fn genVMIN(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    _ = args;
    try self.emit("@as(usize, 16)");
}

pub fn genVQUIT(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    _ = args;
    try self.emit("@as(usize, 9)");
}

pub fn genVSTART(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    _ = args;
    try self.emit("@as(usize, 12)");
}

pub fn genVSTOP(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    _ = args;
    try self.emit("@as(usize, 13)");
}

pub fn genVSUSP(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    _ = args;
    try self.emit("@as(usize, 10)");
}

pub fn genVTIME(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    _ = args;
    try self.emit("@as(usize, 17)");
}

/// Generate termios.NCCS (number of control characters)
pub fn genNCCS(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    _ = args;
    try self.emit("@as(usize, 20)");
}
