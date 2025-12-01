/// Python msvcrt module - Windows MSVC runtime routines
const std = @import("std");
const ast = @import("ast");
const CodegenError = @import("main.zig").CodegenError;
const NativeCodegen = @import("main.zig").NativeCodegen;

const ModuleHandler = *const fn (*NativeCodegen, []ast.Node) CodegenError!void;
pub const Funcs = std.StaticStringMap(ModuleHandler).initComptime(.{
    .{ "getch", genGetch },
    .{ "getwch", genGetwch },
    .{ "getche", genGetche },
    .{ "getwche", genGetwche },
    .{ "putch", genPutch },
    .{ "putwch", genPutwch },
    .{ "ungetch", genUngetch },
    .{ "ungetwch", genUngetwch },
    .{ "kbhit", genKbhit },
    .{ "locking", genLocking },
    .{ "setmode", genSetmode },
    .{ "open_osfhandle", genOpenOsfhandle },
    .{ "get_osfhandle", genGetOsfhandle },
    .{ "heapmin", genHeapmin },
    .{ "set_error_mode", genSetErrorMode },
    .{ "c_r_t__a_s_s_e_m_b_l_y__v_e_r_s_i_o_n", genCRT_ASSEMBLY_VERSION },
    .{ "l_k__n_b_l_c_k", genLK_NBLCK },
    .{ "l_k__n_b_r_l_c_k", genLK_NBRLCK },
    .{ "l_k__l_o_c_k", genLK_LOCK },
    .{ "l_k__r_l_c_k", genLK_RLCK },
    .{ "l_k__u_n_l_c_k", genLK_UNLCK },
    .{ "s_e_m__f_a_i_l_c_r_i_t_i_c_a_l_e_r_r_o_r_s", genSEM_FAILCRITICALERRORS },
    .{ "s_e_m__n_o_a_l_i_g_n_m_e_n_t_f_a_u_l_t_e_x_c_e_p_t", genSEM_NOALIGNMENTFAULTEXCEPT },
    .{ "s_e_m__n_o_g_p_f_a_u_l_t_e_r_r_o_r_b_o_x", genSEM_NOGPFAULTERRORBOX },
    .{ "s_e_m__n_o_o_p_e_n_f_i_l_e_e_r_r_o_r_b_o_x", genSEM_NOOPENFILEERRORBOX },
});

/// Generate msvcrt.getch() - Read keypress
pub fn genGetch(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    _ = args;
    try self.emit("\"\"");
}

/// Generate msvcrt.getwch() - Read wide keypress
pub fn genGetwch(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    _ = args;
    try self.emit("\"\"");
}

/// Generate msvcrt.getche() - Read keypress with echo
pub fn genGetche(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    _ = args;
    try self.emit("\"\"");
}

/// Generate msvcrt.getwche() - Read wide keypress with echo
pub fn genGetwche(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    _ = args;
    try self.emit("\"\"");
}

/// Generate msvcrt.putch(char) - Write character
pub fn genPutch(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    _ = args;
    try self.emit("{}");
}

/// Generate msvcrt.putwch(char) - Write wide character
pub fn genPutwch(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    _ = args;
    try self.emit("{}");
}

/// Generate msvcrt.ungetch(char) - Push back character
pub fn genUngetch(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    _ = args;
    try self.emit("{}");
}

/// Generate msvcrt.ungetwch(char) - Push back wide character
pub fn genUngetwch(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    _ = args;
    try self.emit("{}");
}

/// Generate msvcrt.kbhit() - Check if key pressed
pub fn genKbhit(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    _ = args;
    try self.emit("false");
}

/// Generate msvcrt.locking(fd, mode, nbytes) - Lock file region
pub fn genLocking(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    _ = args;
    try self.emit("{}");
}

/// Generate msvcrt.setmode(fd, mode) - Set file mode
pub fn genSetmode(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    _ = args;
    try self.emit("0");
}

/// Generate msvcrt.open_osfhandle(handle, flags) - Create C runtime fd
pub fn genOpenOsfhandle(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    _ = args;
    try self.emit("-1");
}

/// Generate msvcrt.get_osfhandle(fd) - Get OS handle
pub fn genGetOsfhandle(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    _ = args;
    try self.emit("-1");
}

/// Generate msvcrt.heapmin() - Minimize heap
pub fn genHeapmin(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    _ = args;
    try self.emit("{}");
}

/// Generate msvcrt.SetErrorMode(mode) - Set error mode
pub fn genSetErrorMode(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    _ = args;
    try self.emit("0");
}

/// Generate msvcrt.CRT_ASSEMBLY_VERSION constant
pub fn genCRT_ASSEMBLY_VERSION(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    _ = args;
    try self.emit("\"\"");
}

/// Generate msvcrt.LK_NBLCK constant
pub fn genLK_NBLCK(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    _ = args;
    try self.emit("2");
}

/// Generate msvcrt.LK_NBRLCK constant
pub fn genLK_NBRLCK(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    _ = args;
    try self.emit("4");
}

/// Generate msvcrt.LK_LOCK constant
pub fn genLK_LOCK(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    _ = args;
    try self.emit("1");
}

/// Generate msvcrt.LK_RLCK constant
pub fn genLK_RLCK(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    _ = args;
    try self.emit("3");
}

/// Generate msvcrt.LK_UNLCK constant
pub fn genLK_UNLCK(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    _ = args;
    try self.emit("0");
}

/// Generate msvcrt.SEM_FAILCRITICALERRORS constant
pub fn genSEM_FAILCRITICALERRORS(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    _ = args;
    try self.emit("1");
}

/// Generate msvcrt.SEM_NOALIGNMENTFAULTEXCEPT constant
pub fn genSEM_NOALIGNMENTFAULTEXCEPT(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    _ = args;
    try self.emit("4");
}

/// Generate msvcrt.SEM_NOGPFAULTERRORBOX constant
pub fn genSEM_NOGPFAULTERRORBOX(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    _ = args;
    try self.emit("2");
}

/// Generate msvcrt.SEM_NOOPENFILEERRORBOX constant
pub fn genSEM_NOOPENFILEERRORBOX(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    _ = args;
    try self.emit("0x8000");
}
