/// Python _ssl module - Internal SSL support (C accelerator)
const std = @import("std");
const ast = @import("ast");
const CodegenError = @import("main.zig").CodegenError;
const NativeCodegen = @import("main.zig").NativeCodegen;

const ModuleHandler = *const fn (*NativeCodegen, []ast.Node) CodegenError!void;
fn genConst(comptime v: []const u8) ModuleHandler {
    return struct { fn f(self: *NativeCodegen, args: []ast.Node) CodegenError!void { _ = args; try self.emit(v); } }.f;
}

pub const Funcs = std.StaticStringMap(ModuleHandler).initComptime(.{
    .{ "s_s_l_context", genConst(".{ .protocol = 2, .verify_mode = 0, .check_hostname = false }") },
    .{ "s_s_l_socket", genConst(".{ .context = null, .server_side = false, .server_hostname = null }") },
    .{ "memory_b_i_o", genConst(".{ .pending = 0, .eof = false }") },
    .{ "r_a_n_d_status", genConst("true") }, .{ "r_a_n_d_add", genConst("{}") }, .{ "r_a_n_d_bytes", genConst("\"\"") },
    .{ "r_a_n_d_pseudo_bytes", genConst(".{ \"\", true }") },
    .{ "txt2obj", genConst(".{ .nid = 0, .shortname = \"\", .longname = \"\", .oid = \"\" }") },
    .{ "nid2obj", genConst(".{ .nid = 0, .shortname = \"\", .longname = \"\", .oid = \"\" }") },
    .{ "o_p_e_n_s_s_l__v_e_r_s_i_o_n", genConst("\"OpenSSL 3.0.0 0 Jan 2024\"") },
    .{ "o_p_e_n_s_s_l__v_e_r_s_i_o_n__n_u_m_b_e_r", genConst("@as(i64, 0x30000000)") },
    .{ "o_p_e_n_s_s_l__v_e_r_s_i_o_n__i_n_f_o", genConst(".{ @as(i32, 3), @as(i32, 0), @as(i32, 0), @as(i32, 0), @as(i32, 0) }") },
    .{ "p_r_o_t_o_c_o_l__s_s_lv23", genConst("@as(i32, 2)") }, .{ "p_r_o_t_o_c_o_l__t_l_s", genConst("@as(i32, 2)") },
    .{ "p_r_o_t_o_c_o_l__t_l_s__c_l_i_e_n_t", genConst("@as(i32, 16)") }, .{ "p_r_o_t_o_c_o_l__t_l_s__s_e_r_v_e_r", genConst("@as(i32, 17)") },
    .{ "c_e_r_t__n_o_n_e", genConst("@as(i32, 0)") }, .{ "c_e_r_t__o_p_t_i_o_n_a_l", genConst("@as(i32, 1)") }, .{ "c_e_r_t__r_e_q_u_i_r_e_d", genConst("@as(i32, 2)") },
    .{ "h_a_s__s_n_i", genConst("true") }, .{ "h_a_s__e_c_d_h", genConst("true") }, .{ "h_a_s__n_p_n", genConst("false") }, .{ "h_a_s__a_l_p_n", genConst("true") },
    .{ "h_a_s__t_l_sv1", genConst("true") }, .{ "h_a_s__t_l_sv1_1", genConst("true") }, .{ "h_a_s__t_l_sv1_2", genConst("true") }, .{ "h_a_s__t_l_sv1_3", genConst("true") },
    .{ "s_s_l_error", genConst("error.SSLError") }, .{ "s_s_l_zero_return_error", genConst("error.SSLZeroReturnError") },
    .{ "s_s_l_want_read_error", genConst("error.SSLWantReadError") }, .{ "s_s_l_want_write_error", genConst("error.SSLWantWriteError") },
    .{ "s_s_l_syscall_error", genConst("error.SSLSyscallError") }, .{ "s_s_l_e_o_f_error", genConst("error.SSLEOFError") },
    .{ "s_s_l_cert_verification_error", genConst("error.SSLCertVerificationError") },
});
