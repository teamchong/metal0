/// Python winreg module - Windows registry access
const std = @import("std");
const ast = @import("ast");
const CodegenError = @import("main.zig").CodegenError;
const NativeCodegen = @import("main.zig").NativeCodegen;

const ModuleHandler = *const fn (*NativeCodegen, []ast.Node) CodegenError!void;
pub const Funcs = std.StaticStringMap(ModuleHandler).initComptime(.{
    .{ "close_key", genCloseKey }, .{ "connect_registry", genConnectRegistry }, .{ "create_key", genCreateKey },
    .{ "create_key_ex", genCreateKeyEx }, .{ "delete_key", genDeleteKey }, .{ "delete_key_ex", genDeleteKeyEx },
    .{ "delete_value", genDeleteValue }, .{ "enum_key", genEnumKey }, .{ "enum_value", genEnumValue },
    .{ "expand_environment_strings", genExpandEnvironmentStrings }, .{ "flush_key", genFlushKey },
    .{ "load_key", genLoadKey }, .{ "open_key", genOpenKey }, .{ "open_key_ex", genOpenKeyEx },
    .{ "query_info_key", genQueryInfoKey }, .{ "query_value", genQueryValue }, .{ "query_value_ex", genQueryValueEx },
    .{ "save_key", genSaveKey }, .{ "set_value", genSetValue }, .{ "set_value_ex", genSetValueEx },
    .{ "disable_reflection_key", genDisableReflectionKey }, .{ "enable_reflection_key", genEnableReflectionKey },
    .{ "query_reflection_key", genQueryReflectionKey },
    .{ "h_k_e_y__c_l_a_s_s_e_s__r_o_o_t", genHKEY_CLASSES_ROOT }, .{ "h_k_e_y__c_u_r_r_e_n_t__u_s_e_r", genHKEY_CURRENT_USER },
    .{ "h_k_e_y__l_o_c_a_l__m_a_c_h_i_n_e", genHKEY_LOCAL_MACHINE }, .{ "h_k_e_y__u_s_e_r_s", genHKEY_USERS },
    .{ "h_k_e_y__p_e_r_f_o_r_m_a_n_c_e__d_a_t_a", genHKEY_PERFORMANCE_DATA }, .{ "h_k_e_y__c_u_r_r_e_n_t__c_o_n_f_i_g", genHKEY_CURRENT_CONFIG },
    .{ "h_k_e_y__d_y_n__d_a_t_a", genHKEY_DYN_DATA }, .{ "k_e_y__a_l_l__a_c_c_e_s_s", genKEY_ALL_ACCESS },
    .{ "k_e_y__w_r_i_t_e", genKEY_WRITE }, .{ "k_e_y__r_e_a_d", genKEY_READ }, .{ "k_e_y__e_x_e_c_u_t_e", genKEY_EXECUTE },
    .{ "k_e_y__q_u_e_r_y__v_a_l_u_e", genKEY_QUERY_VALUE }, .{ "k_e_y__s_e_t__v_a_l_u_e", genKEY_SET_VALUE },
    .{ "k_e_y__c_r_e_a_t_e__s_u_b__k_e_y", genKEY_CREATE_SUB_KEY }, .{ "k_e_y__e_n_u_m_e_r_a_t_e__s_u_b__k_e_y_s", genKEY_ENUMERATE_SUB_KEYS },
    .{ "k_e_y__n_o_t_i_f_y", genKEY_NOTIFY }, .{ "k_e_y__c_r_e_a_t_e__l_i_n_k", genKEY_CREATE_LINK },
    .{ "k_e_y__w_o_w64_64_k_e_y", genKEY_WOW64_64KEY }, .{ "k_e_y__w_o_w64_32_k_e_y", genKEY_WOW64_32KEY },
    .{ "r_e_g__n_o_n_e", genREG_NONE }, .{ "r_e_g__s_z", genREG_SZ }, .{ "r_e_g__e_x_p_a_n_d__s_z", genREG_EXPAND_SZ },
    .{ "r_e_g__b_i_n_a_r_y", genREG_BINARY }, .{ "r_e_g__d_w_o_r_d", genREG_DWORD },
    .{ "r_e_g__d_w_o_r_d__l_i_t_t_l_e__e_n_d_i_a_n", genREG_DWORD_LITTLE_ENDIAN },
    .{ "r_e_g__d_w_o_r_d__b_i_g__e_n_d_i_a_n", genREG_DWORD_BIG_ENDIAN }, .{ "r_e_g__l_i_n_k", genREG_LINK },
    .{ "r_e_g__m_u_l_t_i__s_z", genREG_MULTI_SZ }, .{ "r_e_g__r_e_s_o_u_r_c_e__l_i_s_t", genREG_RESOURCE_LIST },
    .{ "r_e_g__f_u_l_l__r_e_s_o_u_r_c_e__d_e_s_c_r_i_p_t_o_r", genREG_FULL_RESOURCE_DESCRIPTOR },
    .{ "r_e_g__r_e_s_o_u_r_c_e__r_e_q_u_i_r_e_m_e_n_t_s__l_i_s_t", genREG_RESOURCE_REQUIREMENTS_LIST },
    .{ "r_e_g__q_w_o_r_d", genREG_QWORD }, .{ "r_e_g__q_w_o_r_d__l_i_t_t_l_e__e_n_d_i_a_n", genREG_QWORD_LITTLE_ENDIAN },
});

// Helper
fn genConst(self: *NativeCodegen, args: []ast.Node, value: []const u8) CodegenError!void { _ = args; try self.emit(value); }

// Functions
pub fn genCloseKey(self: *NativeCodegen, args: []ast.Node) CodegenError!void { try genConst(self, args, "{}"); }
pub fn genConnectRegistry(self: *NativeCodegen, args: []ast.Node) CodegenError!void { try genConst(self, args, "null"); }
pub fn genCreateKey(self: *NativeCodegen, args: []ast.Node) CodegenError!void { try genConst(self, args, "null"); }
pub fn genCreateKeyEx(self: *NativeCodegen, args: []ast.Node) CodegenError!void { try genConst(self, args, "null"); }
pub fn genDeleteKey(self: *NativeCodegen, args: []ast.Node) CodegenError!void { try genConst(self, args, "{}"); }
pub fn genDeleteKeyEx(self: *NativeCodegen, args: []ast.Node) CodegenError!void { try genConst(self, args, "{}"); }
pub fn genDeleteValue(self: *NativeCodegen, args: []ast.Node) CodegenError!void { try genConst(self, args, "{}"); }
pub fn genEnumKey(self: *NativeCodegen, args: []ast.Node) CodegenError!void { try genConst(self, args, "\"\""); }
pub fn genEnumValue(self: *NativeCodegen, args: []ast.Node) CodegenError!void { try genConst(self, args, ".{ \"\", null, 0 }"); }
pub fn genExpandEnvironmentStrings(self: *NativeCodegen, args: []ast.Node) CodegenError!void { try genConst(self, args, "\"\""); }
pub fn genFlushKey(self: *NativeCodegen, args: []ast.Node) CodegenError!void { try genConst(self, args, "{}"); }
pub fn genLoadKey(self: *NativeCodegen, args: []ast.Node) CodegenError!void { try genConst(self, args, "{}"); }
pub fn genOpenKey(self: *NativeCodegen, args: []ast.Node) CodegenError!void { try genConst(self, args, "null"); }
pub fn genOpenKeyEx(self: *NativeCodegen, args: []ast.Node) CodegenError!void { try genConst(self, args, "null"); }
pub fn genQueryInfoKey(self: *NativeCodegen, args: []ast.Node) CodegenError!void { try genConst(self, args, ".{ 0, 0, 0 }"); }
pub fn genQueryValue(self: *NativeCodegen, args: []ast.Node) CodegenError!void { try genConst(self, args, "\"\""); }
pub fn genQueryValueEx(self: *NativeCodegen, args: []ast.Node) CodegenError!void { try genConst(self, args, ".{ null, 0 }"); }
pub fn genSaveKey(self: *NativeCodegen, args: []ast.Node) CodegenError!void { try genConst(self, args, "{}"); }
pub fn genSetValue(self: *NativeCodegen, args: []ast.Node) CodegenError!void { try genConst(self, args, "{}"); }
pub fn genSetValueEx(self: *NativeCodegen, args: []ast.Node) CodegenError!void { try genConst(self, args, "{}"); }
pub fn genDisableReflectionKey(self: *NativeCodegen, args: []ast.Node) CodegenError!void { try genConst(self, args, "{}"); }
pub fn genEnableReflectionKey(self: *NativeCodegen, args: []ast.Node) CodegenError!void { try genConst(self, args, "{}"); }
pub fn genQueryReflectionKey(self: *NativeCodegen, args: []ast.Node) CodegenError!void { try genConst(self, args, "false"); }

// HKEY constants
pub fn genHKEY_CLASSES_ROOT(self: *NativeCodegen, args: []ast.Node) CodegenError!void { try genConst(self, args, "0x80000000"); }
pub fn genHKEY_CURRENT_USER(self: *NativeCodegen, args: []ast.Node) CodegenError!void { try genConst(self, args, "0x80000001"); }
pub fn genHKEY_LOCAL_MACHINE(self: *NativeCodegen, args: []ast.Node) CodegenError!void { try genConst(self, args, "0x80000002"); }
pub fn genHKEY_USERS(self: *NativeCodegen, args: []ast.Node) CodegenError!void { try genConst(self, args, "0x80000003"); }
pub fn genHKEY_PERFORMANCE_DATA(self: *NativeCodegen, args: []ast.Node) CodegenError!void { try genConst(self, args, "0x80000004"); }
pub fn genHKEY_CURRENT_CONFIG(self: *NativeCodegen, args: []ast.Node) CodegenError!void { try genConst(self, args, "0x80000005"); }
pub fn genHKEY_DYN_DATA(self: *NativeCodegen, args: []ast.Node) CodegenError!void { try genConst(self, args, "0x80000006"); }

// Access rights
pub fn genKEY_ALL_ACCESS(self: *NativeCodegen, args: []ast.Node) CodegenError!void { try genConst(self, args, "0xF003F"); }
pub fn genKEY_WRITE(self: *NativeCodegen, args: []ast.Node) CodegenError!void { try genConst(self, args, "0x20006"); }
pub fn genKEY_READ(self: *NativeCodegen, args: []ast.Node) CodegenError!void { try genConst(self, args, "0x20019"); }
pub fn genKEY_EXECUTE(self: *NativeCodegen, args: []ast.Node) CodegenError!void { try genConst(self, args, "0x20019"); }
pub fn genKEY_QUERY_VALUE(self: *NativeCodegen, args: []ast.Node) CodegenError!void { try genConst(self, args, "0x0001"); }
pub fn genKEY_SET_VALUE(self: *NativeCodegen, args: []ast.Node) CodegenError!void { try genConst(self, args, "0x0002"); }
pub fn genKEY_CREATE_SUB_KEY(self: *NativeCodegen, args: []ast.Node) CodegenError!void { try genConst(self, args, "0x0004"); }
pub fn genKEY_ENUMERATE_SUB_KEYS(self: *NativeCodegen, args: []ast.Node) CodegenError!void { try genConst(self, args, "0x0008"); }
pub fn genKEY_NOTIFY(self: *NativeCodegen, args: []ast.Node) CodegenError!void { try genConst(self, args, "0x0010"); }
pub fn genKEY_CREATE_LINK(self: *NativeCodegen, args: []ast.Node) CodegenError!void { try genConst(self, args, "0x0020"); }
pub fn genKEY_WOW64_64KEY(self: *NativeCodegen, args: []ast.Node) CodegenError!void { try genConst(self, args, "0x0100"); }
pub fn genKEY_WOW64_32KEY(self: *NativeCodegen, args: []ast.Node) CodegenError!void { try genConst(self, args, "0x0200"); }

// REG type constants
pub fn genREG_NONE(self: *NativeCodegen, args: []ast.Node) CodegenError!void { try genConst(self, args, "0"); }
pub fn genREG_SZ(self: *NativeCodegen, args: []ast.Node) CodegenError!void { try genConst(self, args, "1"); }
pub fn genREG_EXPAND_SZ(self: *NativeCodegen, args: []ast.Node) CodegenError!void { try genConst(self, args, "2"); }
pub fn genREG_BINARY(self: *NativeCodegen, args: []ast.Node) CodegenError!void { try genConst(self, args, "3"); }
pub fn genREG_DWORD(self: *NativeCodegen, args: []ast.Node) CodegenError!void { try genConst(self, args, "4"); }
pub fn genREG_DWORD_LITTLE_ENDIAN(self: *NativeCodegen, args: []ast.Node) CodegenError!void { try genConst(self, args, "4"); }
pub fn genREG_DWORD_BIG_ENDIAN(self: *NativeCodegen, args: []ast.Node) CodegenError!void { try genConst(self, args, "5"); }
pub fn genREG_LINK(self: *NativeCodegen, args: []ast.Node) CodegenError!void { try genConst(self, args, "6"); }
pub fn genREG_MULTI_SZ(self: *NativeCodegen, args: []ast.Node) CodegenError!void { try genConst(self, args, "7"); }
pub fn genREG_RESOURCE_LIST(self: *NativeCodegen, args: []ast.Node) CodegenError!void { try genConst(self, args, "8"); }
pub fn genREG_FULL_RESOURCE_DESCRIPTOR(self: *NativeCodegen, args: []ast.Node) CodegenError!void { try genConst(self, args, "9"); }
pub fn genREG_RESOURCE_REQUIREMENTS_LIST(self: *NativeCodegen, args: []ast.Node) CodegenError!void { try genConst(self, args, "10"); }
pub fn genREG_QWORD(self: *NativeCodegen, args: []ast.Node) CodegenError!void { try genConst(self, args, "11"); }
pub fn genREG_QWORD_LITTLE_ENDIAN(self: *NativeCodegen, args: []ast.Node) CodegenError!void { try genConst(self, args, "11"); }
