/// Python _tkinter module - Tcl/Tk interface
const std = @import("std");
const ast = @import("ast");
const CodegenError = @import("main.zig").CodegenError;
const NativeCodegen = @import("main.zig").NativeCodegen;

const ModuleHandler = *const fn (*NativeCodegen, []ast.Node) CodegenError!void;
pub const Funcs = std.StaticStringMap(ModuleHandler).initComptime(.{
    .{ "create", genCreate },
    .{ "setbusywaitinterval", genSetbusywaitinterval },
    .{ "getbusywaitinterval", genGetbusywaitinterval },
    .{ "tcl_error", genTclError },
    .{ "t_k__v_e_r_s_i_o_n", genTK_VERSION },
    .{ "t_c_l__v_e_r_s_i_o_n", genTCL_VERSION },
    .{ "r_e_a_d_a_b_l_e", genREADABLE },
    .{ "w_r_i_t_a_b_l_e", genWRITABLE },
    .{ "e_x_c_e_p_t_i_o_n", genEXCEPTION },
    .{ "d_o_n_t__w_a_i_t", genDONT_WAIT },
    .{ "w_i_n_d_o_w__e_v_e_n_t_s", genWINDOW_EVENTS },
    .{ "f_i_l_e__e_v_e_n_t_s", genFILE_EVENTS },
    .{ "t_i_m_e_r__e_v_e_n_t_s", genTIMER_EVENTS },
    .{ "i_d_l_e__e_v_e_n_t_s", genIDLE_EVENTS },
    .{ "a_l_l__e_v_e_n_t_s", genALL_EVENTS },
});

/// Generate _tkinter.create(screenName, baseName, className, interactive, wantobjects, wantTk, sync, use) - Create Tk app
pub fn genCreate(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    _ = args;
    try self.emit(".{}");
}

/// Generate _tkinter.setbusywaitinterval(ms) - Set busy wait interval
pub fn genSetbusywaitinterval(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    _ = args;
    try self.emit("{}");
}

/// Generate _tkinter.getbusywaitinterval() - Get busy wait interval
pub fn genGetbusywaitinterval(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    _ = args;
    try self.emit("20");
}

/// Generate _tkinter.TclError exception
pub fn genTclError(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    _ = args;
    try self.emit("error.TclError");
}

/// Generate _tkinter.TK_VERSION constant
pub fn genTK_VERSION(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    _ = args;
    try self.emit("\"8.6\"");
}

/// Generate _tkinter.TCL_VERSION constant
pub fn genTCL_VERSION(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    _ = args;
    try self.emit("\"8.6\"");
}

/// Generate _tkinter.READABLE constant
pub fn genREADABLE(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    _ = args;
    try self.emit("2");
}

/// Generate _tkinter.WRITABLE constant
pub fn genWRITABLE(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    _ = args;
    try self.emit("4");
}

/// Generate _tkinter.EXCEPTION constant
pub fn genEXCEPTION(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    _ = args;
    try self.emit("8");
}

/// Generate _tkinter.DONT_WAIT constant
pub fn genDONT_WAIT(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    _ = args;
    try self.emit("2");
}

/// Generate _tkinter.WINDOW_EVENTS constant
pub fn genWINDOW_EVENTS(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    _ = args;
    try self.emit("4");
}

/// Generate _tkinter.FILE_EVENTS constant
pub fn genFILE_EVENTS(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    _ = args;
    try self.emit("8");
}

/// Generate _tkinter.TIMER_EVENTS constant
pub fn genTIMER_EVENTS(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    _ = args;
    try self.emit("16");
}

/// Generate _tkinter.IDLE_EVENTS constant
pub fn genIDLE_EVENTS(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    _ = args;
    try self.emit("32");
}

/// Generate _tkinter.ALL_EVENTS constant
pub fn genALL_EVENTS(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    _ = args;
    try self.emit("-3");
}
