/// Python msilib module - Windows MSI file creation
const std = @import("std");
const ast = @import("ast");
const CodegenError = @import("main.zig").CodegenError;
const NativeCodegen = @import("main.zig").NativeCodegen;

const ModuleHandler = *const fn (*NativeCodegen, []ast.Node) CodegenError!void;
pub const Funcs = std.StaticStringMap(ModuleHandler).initComptime(.{
    .{ "init_database", genEmpty }, .{ "add_data", genUnit }, .{ "add_tables", genUnit }, .{ "add_stream", genUnit },
    .{ "gen_uuid", genUuid }, .{ "open_database", genEmpty }, .{ "create_record", genEmpty },
    .{ "c_a_b", genEmpty }, .{ "directory", genEmpty }, .{ "feature", genEmpty }, .{ "dialog", genEmpty },
    .{ "control", genEmpty }, .{ "radio_button_group", genEmpty },
    .{ "a_m_d64", genFalse }, .{ "win64", genFalse }, .{ "itanium", genFalse },
    .{ "schema", genEmpty }, .{ "sequence", genEmpty }, .{ "text", genEmpty },
    .{ "m_s_i_d_b_o_p_e_n__c_r_e_a_t_e_d_i_r_e_c_t", genI4 }, .{ "m_s_i_d_b_o_p_e_n__c_r_e_a_t_e", genI3 },
    .{ "m_s_i_d_b_o_p_e_n__d_i_r_e_c_t", genI2 }, .{ "m_s_i_d_b_o_p_e_n__r_e_a_d_o_n_l_y", genI0 },
    .{ "m_s_i_d_b_o_p_e_n__t_r_a_n_s_a_c_t", genI1 },
});

fn genConst(self: *NativeCodegen, args: []ast.Node, v: []const u8) CodegenError!void { _ = args; try self.emit(v); }
fn genUnit(self: *NativeCodegen, args: []ast.Node) CodegenError!void { try genConst(self, args, "{}"); }
fn genEmpty(self: *NativeCodegen, args: []ast.Node) CodegenError!void { try genConst(self, args, ".{}"); }
fn genFalse(self: *NativeCodegen, args: []ast.Node) CodegenError!void { try genConst(self, args, "false"); }
fn genUuid(self: *NativeCodegen, args: []ast.Node) CodegenError!void { try genConst(self, args, "\"{00000000-0000-0000-0000-000000000000}\""); }
fn genI0(self: *NativeCodegen, args: []ast.Node) CodegenError!void { try genConst(self, args, "0"); }
fn genI1(self: *NativeCodegen, args: []ast.Node) CodegenError!void { try genConst(self, args, "1"); }
fn genI2(self: *NativeCodegen, args: []ast.Node) CodegenError!void { try genConst(self, args, "2"); }
fn genI3(self: *NativeCodegen, args: []ast.Node) CodegenError!void { try genConst(self, args, "3"); }
fn genI4(self: *NativeCodegen, args: []ast.Node) CodegenError!void { try genConst(self, args, "4"); }
