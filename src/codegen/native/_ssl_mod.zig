/// Python _ssl module - Internal SSL support (C accelerator)
const std = @import("std");
const ast = @import("ast");
const CodegenError = @import("main.zig").CodegenError;
const NativeCodegen = @import("main.zig").NativeCodegen;

const ModuleHandler = *const fn (*NativeCodegen, []ast.Node) CodegenError!void;
pub const Funcs = std.StaticStringMap(ModuleHandler).initComptime(.{
    .{ "s_s_l_context", genSSLContext }, .{ "s_s_l_socket", genSSLSocket }, .{ "memory_b_i_o", genMemoryBIO },
    .{ "r_a_n_d_status", genTrue }, .{ "r_a_n_d_add", genUnit }, .{ "r_a_n_d_bytes", genEmptyStr },
    .{ "r_a_n_d_pseudo_bytes", genRAND_pseudo_bytes }, .{ "txt2obj", genObjStruct }, .{ "nid2obj", genObjStruct },
    .{ "o_p_e_n_s_s_l__v_e_r_s_i_o_n", genOPENSSL_VERSION },
    .{ "o_p_e_n_s_s_l__v_e_r_s_i_o_n__n_u_m_b_e_r", genOPENSSL_VERSION_NUMBER },
    .{ "o_p_e_n_s_s_l__v_e_r_s_i_o_n__i_n_f_o", genOPENSSL_VERSION_INFO },
    .{ "p_r_o_t_o_c_o_l__s_s_lv23", genI32_2 }, .{ "p_r_o_t_o_c_o_l__t_l_s", genI32_2 },
    .{ "p_r_o_t_o_c_o_l__t_l_s__c_l_i_e_n_t", genI32_16 }, .{ "p_r_o_t_o_c_o_l__t_l_s__s_e_r_v_e_r", genI32_17 },
    .{ "c_e_r_t__n_o_n_e", genI32_0 }, .{ "c_e_r_t__o_p_t_i_o_n_a_l", genI32_1 }, .{ "c_e_r_t__r_e_q_u_i_r_e_d", genI32_2 },
    .{ "h_a_s__s_n_i", genTrue }, .{ "h_a_s__e_c_d_h", genTrue }, .{ "h_a_s__n_p_n", genFalse }, .{ "h_a_s__a_l_p_n", genTrue },
    .{ "h_a_s__t_l_sv1", genTrue }, .{ "h_a_s__t_l_sv1_1", genTrue }, .{ "h_a_s__t_l_sv1_2", genTrue }, .{ "h_a_s__t_l_sv1_3", genTrue },
    .{ "s_s_l_error", genSSLError }, .{ "s_s_l_zero_return_error", genSSLZeroReturnError },
    .{ "s_s_l_want_read_error", genSSLWantReadError }, .{ "s_s_l_want_write_error", genSSLWantWriteError },
    .{ "s_s_l_syscall_error", genSSLSyscallError }, .{ "s_s_l_e_o_f_error", genSSLEOFError },
    .{ "s_s_l_cert_verification_error", genSSLCertVerificationError },
});

// Helpers
fn genConst(self: *NativeCodegen, args: []ast.Node, value: []const u8) CodegenError!void { _ = args; try self.emit(value); }
fn genUnit(self: *NativeCodegen, args: []ast.Node) CodegenError!void { try genConst(self, args, "{}"); }
fn genTrue(self: *NativeCodegen, args: []ast.Node) CodegenError!void { try genConst(self, args, "true"); }
fn genFalse(self: *NativeCodegen, args: []ast.Node) CodegenError!void { try genConst(self, args, "false"); }
fn genEmptyStr(self: *NativeCodegen, args: []ast.Node) CodegenError!void { try genConst(self, args, "\"\""); }
fn genI32_0(self: *NativeCodegen, args: []ast.Node) CodegenError!void { try genConst(self, args, "@as(i32, 0)"); }
fn genI32_1(self: *NativeCodegen, args: []ast.Node) CodegenError!void { try genConst(self, args, "@as(i32, 1)"); }
fn genI32_2(self: *NativeCodegen, args: []ast.Node) CodegenError!void { try genConst(self, args, "@as(i32, 2)"); }
fn genI32_16(self: *NativeCodegen, args: []ast.Node) CodegenError!void { try genConst(self, args, "@as(i32, 16)"); }
fn genI32_17(self: *NativeCodegen, args: []ast.Node) CodegenError!void { try genConst(self, args, "@as(i32, 17)"); }

// Struct types
fn genSSLContext(self: *NativeCodegen, args: []ast.Node) CodegenError!void { try genConst(self, args, ".{ .protocol = 2, .verify_mode = 0, .check_hostname = false }"); }
fn genSSLSocket(self: *NativeCodegen, args: []ast.Node) CodegenError!void { try genConst(self, args, ".{ .context = null, .server_side = false, .server_hostname = null }"); }
fn genMemoryBIO(self: *NativeCodegen, args: []ast.Node) CodegenError!void { try genConst(self, args, ".{ .pending = 0, .eof = false }"); }
fn genRAND_pseudo_bytes(self: *NativeCodegen, args: []ast.Node) CodegenError!void { try genConst(self, args, ".{ \"\", true }"); }
fn genObjStruct(self: *NativeCodegen, args: []ast.Node) CodegenError!void { try genConst(self, args, ".{ .nid = 0, .shortname = \"\", .longname = \"\", .oid = \"\" }"); }
fn genOPENSSL_VERSION(self: *NativeCodegen, args: []ast.Node) CodegenError!void { try genConst(self, args, "\"OpenSSL 3.0.0 0 Jan 2024\""); }
fn genOPENSSL_VERSION_NUMBER(self: *NativeCodegen, args: []ast.Node) CodegenError!void { try genConst(self, args, "@as(i64, 0x30000000)"); }
fn genOPENSSL_VERSION_INFO(self: *NativeCodegen, args: []ast.Node) CodegenError!void { try genConst(self, args, ".{ @as(i32, 3), @as(i32, 0), @as(i32, 0), @as(i32, 0), @as(i32, 0) }"); }

// Exceptions
fn genSSLError(self: *NativeCodegen, args: []ast.Node) CodegenError!void { try genConst(self, args, "error.SSLError"); }
fn genSSLZeroReturnError(self: *NativeCodegen, args: []ast.Node) CodegenError!void { try genConst(self, args, "error.SSLZeroReturnError"); }
fn genSSLWantReadError(self: *NativeCodegen, args: []ast.Node) CodegenError!void { try genConst(self, args, "error.SSLWantReadError"); }
fn genSSLWantWriteError(self: *NativeCodegen, args: []ast.Node) CodegenError!void { try genConst(self, args, "error.SSLWantWriteError"); }
fn genSSLSyscallError(self: *NativeCodegen, args: []ast.Node) CodegenError!void { try genConst(self, args, "error.SSLSyscallError"); }
fn genSSLEOFError(self: *NativeCodegen, args: []ast.Node) CodegenError!void { try genConst(self, args, "error.SSLEOFError"); }
fn genSSLCertVerificationError(self: *NativeCodegen, args: []ast.Node) CodegenError!void { try genConst(self, args, "error.SSLCertVerificationError"); }
