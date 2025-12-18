/// Python winreg module - Windows registry access
/// MIGRATED TO ZIGBUILDER
const std = @import("std");
const h = @import("mod_helper.zig");
const builder_mod = @import("codegen.builder");
const ast = @import("analysis.ast");

pub const Funcs = std.StaticStringMap(h.H).initComptime(.{
    .{ "close_key", genCloseKey },
    .{ "connect_registry", genConnectRegistry },
    .{ "create_key", genCreateKey },
    .{ "create_key_ex", genCreateKeyEx },
    .{ "delete_key", genDeleteKey },
    .{ "delete_key_ex", genDeleteKeyEx },
    .{ "delete_value", genDeleteValue },
    .{ "enum_key", genEnumKey },
    .{ "enum_value", genEnumValue },
    .{ "expand_environment_strings", genExpandEnvironmentStrings },
    .{ "flush_key", genFlushKey },
    .{ "load_key", genLoadKey },
    .{ "open_key", genOpenKey },
    .{ "open_key_ex", genOpenKeyEx },
    .{ "query_info_key", genQueryInfoKey },
    .{ "query_value", genQueryValue },
    .{ "query_value_ex", genQueryValueEx },
    .{ "save_key", genSaveKey },
    .{ "set_value", genSetValue },
    .{ "set_value_ex", genSetValueEx },
    .{ "disable_reflection_key", genDisableReflectionKey },
    .{ "enable_reflection_key", genEnableReflectionKey },
    .{ "query_reflection_key", genQueryReflectionKey },
    .{ "h_k_e_y__c_l_a_s_s_e_s__r_o_o_t", genHkeyClassesRoot },
    .{ "h_k_e_y__c_u_r_r_e_n_t__u_s_e_r", genHkeyCurrentUser },
    .{ "h_k_e_y__l_o_c_a_l__m_a_c_h_i_n_e", genHkeyLocalMachine },
    .{ "h_k_e_y__u_s_e_r_s", genHkeyUsers },
    .{ "h_k_e_y__p_e_r_f_o_r_m_a_n_c_e__d_a_t_a", genHkeyPerformanceData },
    .{ "h_k_e_y__c_u_r_r_e_n_t__c_o_n_f_i_g", genHkeyCurrentConfig },
    .{ "h_k_e_y__d_y_n__d_a_t_a", genHkeyDynData },
    .{ "k_e_y__a_l_l__a_c_c_e_s_s", genKeyAllAccess },
    .{ "k_e_y__w_r_i_t_e", genKeyWrite },
    .{ "k_e_y__r_e_a_d", genKeyRead },
    .{ "k_e_y__e_x_e_c_u_t_e", genKeyExecute },
    .{ "k_e_y__q_u_e_r_y__v_a_l_u_e", genKeyQueryValue },
    .{ "k_e_y__s_e_t__v_a_l_u_e", genKeySetValue },
    .{ "k_e_y__c_r_e_a_t_e__s_u_b__k_e_y", genKeyCreateSubKey },
    .{ "k_e_y__e_n_u_m_e_r_a_t_e__s_u_b__k_e_y_s", genKeyEnumerateSubKeys },
    .{ "k_e_y__n_o_t_i_f_y", genKeyNotify },
    .{ "k_e_y__c_r_e_a_t_e__l_i_n_k", genKeyCreateLink },
    .{ "k_e_y__w_o_w64_64_k_e_y", genKeyWow6464Key },
    .{ "k_e_y__w_o_w64_32_k_e_y", genKeyWow6432Key },
    .{ "r_e_g__n_o_n_e", genRegNone },
    .{ "r_e_g__s_z", genRegSz },
    .{ "r_e_g__e_x_p_a_n_d__s_z", genRegExpandSz },
    .{ "r_e_g__b_i_n_a_r_y", genRegBinary },
    .{ "r_e_g__d_w_o_r_d", genRegDword },
    .{ "r_e_g__d_w_o_r_d__l_i_t_t_l_e__e_n_d_i_a_n", genRegDwordLittleEndian },
    .{ "r_e_g__d_w_o_r_d__b_i_g__e_n_d_i_a_n", genRegDwordBigEndian },
    .{ "r_e_g__l_i_n_k", genRegLink },
    .{ "r_e_g__m_u_l_t_i__s_z", genRegMultiSz },
    .{ "r_e_g__r_e_s_o_u_r_c_e__l_i_s_t", genRegResourceList },
    .{ "r_e_g__f_u_l_l__r_e_s_o_u_r_c_e__d_e_s_c_r_i_p_t_o_r", genRegFullResourceDescriptor },
    .{ "r_e_g__r_e_s_o_u_r_c_e__r_e_q_u_i_r_e_m_e_n_t_s__l_i_s_t", genRegResourceRequirementsList },
    .{ "r_e_g__q_w_o_r_d", genRegQword },
    .{ "r_e_g__q_w_o_r_d__l_i_t_t_l_e__e_n_d_i_a_n", genRegQwordLittleEndian },
});

fn genCloseKey(self: *h.NativeCodegen, _: []ast.Node) h.CodegenError!void {
    const b = try self.getBuilder();
    try b.emitValue(builder_mod.ZigValue.raw("{}"), builder_mod.EmitConfig.forExpression());
}

fn genConnectRegistry(self: *h.NativeCodegen, _: []ast.Node) h.CodegenError!void {
    const b = try self.getBuilder();
    try b.emitValue(builder_mod.ZigValue.null_(), builder_mod.EmitConfig.forExpression());
}

fn genCreateKey(self: *h.NativeCodegen, _: []ast.Node) h.CodegenError!void {
    const b = try self.getBuilder();
    try b.emitValue(builder_mod.ZigValue.null_(), builder_mod.EmitConfig.forExpression());
}

fn genCreateKeyEx(self: *h.NativeCodegen, _: []ast.Node) h.CodegenError!void {
    const b = try self.getBuilder();
    try b.emitValue(builder_mod.ZigValue.null_(), builder_mod.EmitConfig.forExpression());
}

fn genDeleteKey(self: *h.NativeCodegen, _: []ast.Node) h.CodegenError!void {
    const b = try self.getBuilder();
    try b.emitValue(builder_mod.ZigValue.raw("{}"), builder_mod.EmitConfig.forExpression());
}

fn genDeleteKeyEx(self: *h.NativeCodegen, _: []ast.Node) h.CodegenError!void {
    const b = try self.getBuilder();
    try b.emitValue(builder_mod.ZigValue.raw("{}"), builder_mod.EmitConfig.forExpression());
}

fn genDeleteValue(self: *h.NativeCodegen, _: []ast.Node) h.CodegenError!void {
    const b = try self.getBuilder();
    try b.emitValue(builder_mod.ZigValue.raw("{}"), builder_mod.EmitConfig.forExpression());
}

fn genEnumKey(self: *h.NativeCodegen, _: []ast.Node) h.CodegenError!void {
    const b = try self.getBuilder();
    try b.emitValue(builder_mod.ZigValue.string(""), builder_mod.EmitConfig.forExpression());
}

fn genEnumValue(self: *h.NativeCodegen, _: []ast.Node) h.CodegenError!void {
    const b = try self.getBuilder();
    try b.emitValue(builder_mod.ZigValue.raw(".{ \"\", null, 0 }"), builder_mod.EmitConfig.forExpression());
}

fn genExpandEnvironmentStrings(self: *h.NativeCodegen, _: []ast.Node) h.CodegenError!void {
    const b = try self.getBuilder();
    try b.emitValue(builder_mod.ZigValue.string(""), builder_mod.EmitConfig.forExpression());
}

fn genFlushKey(self: *h.NativeCodegen, _: []ast.Node) h.CodegenError!void {
    const b = try self.getBuilder();
    try b.emitValue(builder_mod.ZigValue.raw("{}"), builder_mod.EmitConfig.forExpression());
}

fn genLoadKey(self: *h.NativeCodegen, _: []ast.Node) h.CodegenError!void {
    const b = try self.getBuilder();
    try b.emitValue(builder_mod.ZigValue.raw("{}"), builder_mod.EmitConfig.forExpression());
}

fn genOpenKey(self: *h.NativeCodegen, _: []ast.Node) h.CodegenError!void {
    const b = try self.getBuilder();
    try b.emitValue(builder_mod.ZigValue.null_(), builder_mod.EmitConfig.forExpression());
}

fn genOpenKeyEx(self: *h.NativeCodegen, _: []ast.Node) h.CodegenError!void {
    const b = try self.getBuilder();
    try b.emitValue(builder_mod.ZigValue.null_(), builder_mod.EmitConfig.forExpression());
}

fn genQueryInfoKey(self: *h.NativeCodegen, _: []ast.Node) h.CodegenError!void {
    const b = try self.getBuilder();
    try b.emitValue(builder_mod.ZigValue.raw(".{ 0, 0, 0 }"), builder_mod.EmitConfig.forExpression());
}

fn genQueryValue(self: *h.NativeCodegen, _: []ast.Node) h.CodegenError!void {
    const b = try self.getBuilder();
    try b.emitValue(builder_mod.ZigValue.string(""), builder_mod.EmitConfig.forExpression());
}

fn genQueryValueEx(self: *h.NativeCodegen, _: []ast.Node) h.CodegenError!void {
    const b = try self.getBuilder();
    try b.emitValue(builder_mod.ZigValue.raw(".{ null, 0 }"), builder_mod.EmitConfig.forExpression());
}

fn genSaveKey(self: *h.NativeCodegen, _: []ast.Node) h.CodegenError!void {
    const b = try self.getBuilder();
    try b.emitValue(builder_mod.ZigValue.raw("{}"), builder_mod.EmitConfig.forExpression());
}

fn genSetValue(self: *h.NativeCodegen, _: []ast.Node) h.CodegenError!void {
    const b = try self.getBuilder();
    try b.emitValue(builder_mod.ZigValue.raw("{}"), builder_mod.EmitConfig.forExpression());
}

fn genSetValueEx(self: *h.NativeCodegen, _: []ast.Node) h.CodegenError!void {
    const b = try self.getBuilder();
    try b.emitValue(builder_mod.ZigValue.raw("{}"), builder_mod.EmitConfig.forExpression());
}

fn genDisableReflectionKey(self: *h.NativeCodegen, _: []ast.Node) h.CodegenError!void {
    const b = try self.getBuilder();
    try b.emitValue(builder_mod.ZigValue.raw("{}"), builder_mod.EmitConfig.forExpression());
}

fn genEnableReflectionKey(self: *h.NativeCodegen, _: []ast.Node) h.CodegenError!void {
    const b = try self.getBuilder();
    try b.emitValue(builder_mod.ZigValue.raw("{}"), builder_mod.EmitConfig.forExpression());
}

fn genQueryReflectionKey(self: *h.NativeCodegen, _: []ast.Node) h.CodegenError!void {
    const b = try self.getBuilder();
    try b.emitValue(builder_mod.ZigValue.boolean(false), builder_mod.EmitConfig.forExpression());
}

fn genHkeyClassesRoot(self: *h.NativeCodegen, _: []ast.Node) h.CodegenError!void {
    const b = try self.getBuilder();
    try b.emitValue(builder_mod.ZigValue.raw("0x80000000"), builder_mod.EmitConfig.forExpression());
}

fn genHkeyCurrentUser(self: *h.NativeCodegen, _: []ast.Node) h.CodegenError!void {
    const b = try self.getBuilder();
    try b.emitValue(builder_mod.ZigValue.raw("0x80000001"), builder_mod.EmitConfig.forExpression());
}

fn genHkeyLocalMachine(self: *h.NativeCodegen, _: []ast.Node) h.CodegenError!void {
    const b = try self.getBuilder();
    try b.emitValue(builder_mod.ZigValue.raw("0x80000002"), builder_mod.EmitConfig.forExpression());
}

fn genHkeyUsers(self: *h.NativeCodegen, _: []ast.Node) h.CodegenError!void {
    const b = try self.getBuilder();
    try b.emitValue(builder_mod.ZigValue.raw("0x80000003"), builder_mod.EmitConfig.forExpression());
}

fn genHkeyPerformanceData(self: *h.NativeCodegen, _: []ast.Node) h.CodegenError!void {
    const b = try self.getBuilder();
    try b.emitValue(builder_mod.ZigValue.raw("0x80000004"), builder_mod.EmitConfig.forExpression());
}

fn genHkeyCurrentConfig(self: *h.NativeCodegen, _: []ast.Node) h.CodegenError!void {
    const b = try self.getBuilder();
    try b.emitValue(builder_mod.ZigValue.raw("0x80000005"), builder_mod.EmitConfig.forExpression());
}

fn genHkeyDynData(self: *h.NativeCodegen, _: []ast.Node) h.CodegenError!void {
    const b = try self.getBuilder();
    try b.emitValue(builder_mod.ZigValue.raw("0x80000006"), builder_mod.EmitConfig.forExpression());
}

fn genKeyAllAccess(self: *h.NativeCodegen, _: []ast.Node) h.CodegenError!void {
    const b = try self.getBuilder();
    try b.emitValue(builder_mod.ZigValue.raw("0xF003F"), builder_mod.EmitConfig.forExpression());
}

fn genKeyWrite(self: *h.NativeCodegen, _: []ast.Node) h.CodegenError!void {
    const b = try self.getBuilder();
    try b.emitValue(builder_mod.ZigValue.raw("0x20006"), builder_mod.EmitConfig.forExpression());
}

fn genKeyRead(self: *h.NativeCodegen, _: []ast.Node) h.CodegenError!void {
    const b = try self.getBuilder();
    try b.emitValue(builder_mod.ZigValue.raw("0x20019"), builder_mod.EmitConfig.forExpression());
}

fn genKeyExecute(self: *h.NativeCodegen, _: []ast.Node) h.CodegenError!void {
    const b = try self.getBuilder();
    try b.emitValue(builder_mod.ZigValue.raw("0x20019"), builder_mod.EmitConfig.forExpression());
}

fn genKeyQueryValue(self: *h.NativeCodegen, _: []ast.Node) h.CodegenError!void {
    const b = try self.getBuilder();
    try b.emitValue(builder_mod.ZigValue.raw("0x0001"), builder_mod.EmitConfig.forExpression());
}

fn genKeySetValue(self: *h.NativeCodegen, _: []ast.Node) h.CodegenError!void {
    const b = try self.getBuilder();
    try b.emitValue(builder_mod.ZigValue.raw("0x0002"), builder_mod.EmitConfig.forExpression());
}

fn genKeyCreateSubKey(self: *h.NativeCodegen, _: []ast.Node) h.CodegenError!void {
    const b = try self.getBuilder();
    try b.emitValue(builder_mod.ZigValue.raw("0x0004"), builder_mod.EmitConfig.forExpression());
}

fn genKeyEnumerateSubKeys(self: *h.NativeCodegen, _: []ast.Node) h.CodegenError!void {
    const b = try self.getBuilder();
    try b.emitValue(builder_mod.ZigValue.raw("0x0008"), builder_mod.EmitConfig.forExpression());
}

fn genKeyNotify(self: *h.NativeCodegen, _: []ast.Node) h.CodegenError!void {
    const b = try self.getBuilder();
    try b.emitValue(builder_mod.ZigValue.raw("0x0010"), builder_mod.EmitConfig.forExpression());
}

fn genKeyCreateLink(self: *h.NativeCodegen, _: []ast.Node) h.CodegenError!void {
    const b = try self.getBuilder();
    try b.emitValue(builder_mod.ZigValue.raw("0x0020"), builder_mod.EmitConfig.forExpression());
}

fn genKeyWow6464Key(self: *h.NativeCodegen, _: []ast.Node) h.CodegenError!void {
    const b = try self.getBuilder();
    try b.emitValue(builder_mod.ZigValue.raw("0x0100"), builder_mod.EmitConfig.forExpression());
}

fn genKeyWow6432Key(self: *h.NativeCodegen, _: []ast.Node) h.CodegenError!void {
    const b = try self.getBuilder();
    try b.emitValue(builder_mod.ZigValue.raw("0x0200"), builder_mod.EmitConfig.forExpression());
}

fn genRegNone(self: *h.NativeCodegen, _: []ast.Node) h.CodegenError!void {
    const b = try self.getBuilder();
    try b.emitValue(builder_mod.ZigValue.raw("0"), builder_mod.EmitConfig.forExpression());
}

fn genRegSz(self: *h.NativeCodegen, _: []ast.Node) h.CodegenError!void {
    const b = try self.getBuilder();
    try b.emitValue(builder_mod.ZigValue.raw("1"), builder_mod.EmitConfig.forExpression());
}

fn genRegExpandSz(self: *h.NativeCodegen, _: []ast.Node) h.CodegenError!void {
    const b = try self.getBuilder();
    try b.emitValue(builder_mod.ZigValue.raw("2"), builder_mod.EmitConfig.forExpression());
}

fn genRegBinary(self: *h.NativeCodegen, _: []ast.Node) h.CodegenError!void {
    const b = try self.getBuilder();
    try b.emitValue(builder_mod.ZigValue.raw("3"), builder_mod.EmitConfig.forExpression());
}

fn genRegDword(self: *h.NativeCodegen, _: []ast.Node) h.CodegenError!void {
    const b = try self.getBuilder();
    try b.emitValue(builder_mod.ZigValue.raw("4"), builder_mod.EmitConfig.forExpression());
}

fn genRegDwordLittleEndian(self: *h.NativeCodegen, _: []ast.Node) h.CodegenError!void {
    const b = try self.getBuilder();
    try b.emitValue(builder_mod.ZigValue.raw("4"), builder_mod.EmitConfig.forExpression());
}

fn genRegDwordBigEndian(self: *h.NativeCodegen, _: []ast.Node) h.CodegenError!void {
    const b = try self.getBuilder();
    try b.emitValue(builder_mod.ZigValue.raw("5"), builder_mod.EmitConfig.forExpression());
}

fn genRegLink(self: *h.NativeCodegen, _: []ast.Node) h.CodegenError!void {
    const b = try self.getBuilder();
    try b.emitValue(builder_mod.ZigValue.raw("6"), builder_mod.EmitConfig.forExpression());
}

fn genRegMultiSz(self: *h.NativeCodegen, _: []ast.Node) h.CodegenError!void {
    const b = try self.getBuilder();
    try b.emitValue(builder_mod.ZigValue.raw("7"), builder_mod.EmitConfig.forExpression());
}

fn genRegResourceList(self: *h.NativeCodegen, _: []ast.Node) h.CodegenError!void {
    const b = try self.getBuilder();
    try b.emitValue(builder_mod.ZigValue.raw("8"), builder_mod.EmitConfig.forExpression());
}

fn genRegFullResourceDescriptor(self: *h.NativeCodegen, _: []ast.Node) h.CodegenError!void {
    const b = try self.getBuilder();
    try b.emitValue(builder_mod.ZigValue.raw("9"), builder_mod.EmitConfig.forExpression());
}

fn genRegResourceRequirementsList(self: *h.NativeCodegen, _: []ast.Node) h.CodegenError!void {
    const b = try self.getBuilder();
    try b.emitValue(builder_mod.ZigValue.raw("10"), builder_mod.EmitConfig.forExpression());
}

fn genRegQword(self: *h.NativeCodegen, _: []ast.Node) h.CodegenError!void {
    const b = try self.getBuilder();
    try b.emitValue(builder_mod.ZigValue.raw("11"), builder_mod.EmitConfig.forExpression());
}

fn genRegQwordLittleEndian(self: *h.NativeCodegen, _: []ast.Node) h.CodegenError!void {
    const b = try self.getBuilder();
    try b.emitValue(builder_mod.ZigValue.raw("11"), builder_mod.EmitConfig.forExpression());
}
