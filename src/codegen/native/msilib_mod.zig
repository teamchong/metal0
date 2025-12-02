/// Python msilib module - Windows MSI file creation
const std = @import("std");
const ast = @import("ast");
const CodegenError = @import("main.zig").CodegenError;
const NativeCodegen = @import("main.zig").NativeCodegen;

const ModuleHandler = *const fn (*NativeCodegen, []ast.Node) CodegenError!void;
fn genConst(comptime v: []const u8) ModuleHandler {
    return struct { fn f(self: *NativeCodegen, args: []ast.Node) CodegenError!void { _ = args; try self.emit(v); } }.f;
}

pub const Funcs = std.StaticStringMap(ModuleHandler).initComptime(.{
    .{ "init_database", genConst(".{}") }, .{ "add_data", genConst("{}") }, .{ "add_tables", genConst("{}") },
    .{ "add_stream", genConst("{}") }, .{ "gen_uuid", genConst("\"{00000000-0000-0000-0000-000000000000}\"") },
    .{ "open_database", genConst(".{}") }, .{ "create_record", genConst(".{}") },
    .{ "c_a_b", genConst(".{}") }, .{ "directory", genConst(".{}") }, .{ "feature", genConst(".{}") },
    .{ "dialog", genConst(".{}") }, .{ "control", genConst(".{}") }, .{ "radio_button_group", genConst(".{}") },
    .{ "a_m_d64", genConst("false") }, .{ "win64", genConst("false") }, .{ "itanium", genConst("false") },
    .{ "schema", genConst(".{}") }, .{ "sequence", genConst(".{}") }, .{ "text", genConst(".{}") },
    .{ "m_s_i_d_b_o_p_e_n__c_r_e_a_t_e_d_i_r_e_c_t", genConst("4") },
    .{ "m_s_i_d_b_o_p_e_n__c_r_e_a_t_e", genConst("3") },
    .{ "m_s_i_d_b_o_p_e_n__d_i_r_e_c_t", genConst("2") },
    .{ "m_s_i_d_b_o_p_e_n__r_e_a_d_o_n_l_y", genConst("0") },
    .{ "m_s_i_d_b_o_p_e_n__t_r_a_n_s_a_c_t", genConst("1") },
});
