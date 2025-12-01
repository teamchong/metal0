/// Python _msi module - Windows MSI database access
const std = @import("std");
const ast = @import("ast");
const CodegenError = @import("main.zig").CodegenError;
const NativeCodegen = @import("main.zig").NativeCodegen;

const ModuleHandler = *const fn (*NativeCodegen, []ast.Node) CodegenError!void;
pub const Funcs = std.StaticStringMap(ModuleHandler).initComptime(.{
    .{ "open_database", genOpenDatabase },
    .{ "create_record", genCreateRecord },
    .{ "uuid_create", genUuidCreate },
    .{ "f_c_i_create", genFCICreate },
    .{ "m_s_i_d_b_o_p_e_n__r_e_a_d_o_n_l_y", genMSIDBOPEN_READONLY },
    .{ "m_s_i_d_b_o_p_e_n__t_r_a_n_s_a_c_t", genMSIDBOPEN_TRANSACT },
    .{ "m_s_i_d_b_o_p_e_n__c_r_e_a_t_e", genMSIDBOPEN_CREATE },
    .{ "m_s_i_d_b_o_p_e_n__c_r_e_a_t_e_d_i_r_e_c_t", genMSIDBOPEN_CREATEDIRECT },
    .{ "m_s_i_d_b_o_p_e_n__d_i_r_e_c_t", genMSIDBOPEN_DIRECT },
    .{ "p_i_d__c_o_d_e_p_a_g_e", genPID_CODEPAGE },
    .{ "p_i_d__t_i_t_l_e", genPID_TITLE },
    .{ "p_i_d__s_u_b_j_e_c_t", genPID_SUBJECT },
    .{ "p_i_d__a_u_t_h_o_r", genPID_AUTHOR },
    .{ "p_i_d__k_e_y_w_o_r_d_s", genPID_KEYWORDS },
    .{ "p_i_d__c_o_m_m_e_n_t_s", genPID_COMMENTS },
    .{ "p_i_d__t_e_m_p_l_a_t_e", genPID_TEMPLATE },
    .{ "p_i_d__r_e_v_n_u_m_b_e_r", genPID_REVNUMBER },
    .{ "p_i_d__p_a_g_e_c_o_u_n_t", genPID_PAGECOUNT },
    .{ "p_i_d__w_o_r_d_c_o_u_n_t", genPID_WORDCOUNT },
    .{ "p_i_d__a_p_p_n_a_m_e", genPID_APPNAME },
    .{ "p_i_d__s_e_c_u_r_i_t_y", genPID_SECURITY },
});

/// Generate _msi.OpenDatabase(path, persist) - Open MSI database
pub fn genOpenDatabase(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    _ = args;
    try self.emit(".{}");
}

/// Generate _msi.CreateRecord(count) - Create MSI record
pub fn genCreateRecord(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    _ = args;
    try self.emit(".{}");
}

/// Generate _msi.UuidCreate() - Create UUID
pub fn genUuidCreate(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    _ = args;
    try self.emit("\"00000000-0000-0000-0000-000000000000\"");
}

/// Generate _msi.FCICreate(cab_name, files) - Create cabinet
pub fn genFCICreate(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    _ = args;
    try self.emit("{}");
}

/// Generate _msi.MSIDBOPEN_READONLY constant
pub fn genMSIDBOPEN_READONLY(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    _ = args;
    try self.emit("0");
}

/// Generate _msi.MSIDBOPEN_TRANSACT constant
pub fn genMSIDBOPEN_TRANSACT(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    _ = args;
    try self.emit("1");
}

/// Generate _msi.MSIDBOPEN_CREATE constant
pub fn genMSIDBOPEN_CREATE(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    _ = args;
    try self.emit("3");
}

/// Generate _msi.MSIDBOPEN_CREATEDIRECT constant
pub fn genMSIDBOPEN_CREATEDIRECT(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    _ = args;
    try self.emit("4");
}

/// Generate _msi.MSIDBOPEN_DIRECT constant
pub fn genMSIDBOPEN_DIRECT(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    _ = args;
    try self.emit("2");
}

/// Generate _msi.PID_CODEPAGE constant
pub fn genPID_CODEPAGE(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    _ = args;
    try self.emit("1");
}

/// Generate _msi.PID_TITLE constant
pub fn genPID_TITLE(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    _ = args;
    try self.emit("2");
}

/// Generate _msi.PID_SUBJECT constant
pub fn genPID_SUBJECT(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    _ = args;
    try self.emit("3");
}

/// Generate _msi.PID_AUTHOR constant
pub fn genPID_AUTHOR(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    _ = args;
    try self.emit("4");
}

/// Generate _msi.PID_KEYWORDS constant
pub fn genPID_KEYWORDS(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    _ = args;
    try self.emit("5");
}

/// Generate _msi.PID_COMMENTS constant
pub fn genPID_COMMENTS(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    _ = args;
    try self.emit("6");
}

/// Generate _msi.PID_TEMPLATE constant
pub fn genPID_TEMPLATE(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    _ = args;
    try self.emit("7");
}

/// Generate _msi.PID_REVNUMBER constant
pub fn genPID_REVNUMBER(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    _ = args;
    try self.emit("9");
}

/// Generate _msi.PID_PAGECOUNT constant
pub fn genPID_PAGECOUNT(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    _ = args;
    try self.emit("14");
}

/// Generate _msi.PID_WORDCOUNT constant
pub fn genPID_WORDCOUNT(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    _ = args;
    try self.emit("15");
}

/// Generate _msi.PID_APPNAME constant
pub fn genPID_APPNAME(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    _ = args;
    try self.emit("18");
}

/// Generate _msi.PID_SECURITY constant
pub fn genPID_SECURITY(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    _ = args;
    try self.emit("19");
}
