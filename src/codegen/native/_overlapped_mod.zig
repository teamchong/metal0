/// Python _overlapped module - Windows overlapped I/O
const std = @import("std");
const ast = @import("ast");
const CodegenError = @import("main.zig").CodegenError;
const NativeCodegen = @import("main.zig").NativeCodegen;

const ModuleHandler = *const fn (*NativeCodegen, []ast.Node) CodegenError!void;
fn genConst(self: *NativeCodegen, args: []ast.Node, v: []const u8) CodegenError!void { _ = args; try self.emit(v); }
fn genEmpty(self: *NativeCodegen, args: []ast.Node) CodegenError!void { try genConst(self, args, ".{}"); }
fn genUnit(self: *NativeCodegen, args: []ast.Node) CodegenError!void { try genConst(self, args, "{}"); }
fn genZero(self: *NativeCodegen, args: []ast.Node) CodegenError!void { try genConst(self, args, "0"); }

pub const Funcs = std.StaticStringMap(ModuleHandler).initComptime(.{
    .{ "overlapped", genEmpty }, .{ "create_event", genZero }, .{ "create_io_completion_port", genZero },
    .{ "get_queued_completion_status", genGetQueuedCompletionStatus },
    .{ "post_queued_completion_status", genUnit }, .{ "reset_event", genUnit }, .{ "set_event", genUnit },
    .{ "format_message", genEmptyStr }, .{ "bind_local", genUnit }, .{ "register_wait_with_queue", genZero },
    .{ "unregister_wait", genUnit }, .{ "unregister_wait_ex", genUnit },
    .{ "connect_pipe", genEmpty }, .{ "w_s_a_connect", genEmpty },
    .{ "i_n_v_a_l_i_d__h_a_n_d_l_e__v_a_l_u_e", genInvalidHandle }, .{ "n_u_l_l", genZero },
    .{ "e_r_r_o_r__i_o__p_e_n_d_i_n_g", genErrIoPending }, .{ "e_r_r_o_r__n_e_t_n_a_m_e__d_e_l_e_t_e_d", genErrNetname },
    .{ "e_r_r_o_r__s_e_m__t_i_m_e_o_u_t", genErrSemTimeout }, .{ "e_r_r_o_r__p_i_p_e__b_u_s_y", genErrPipeBusy },
    .{ "i_n_f_i_n_i_t_e", genInfinite },
});

fn genEmptyStr(self: *NativeCodegen, args: []ast.Node) CodegenError!void { try genConst(self, args, "\"\""); }
fn genGetQueuedCompletionStatus(self: *NativeCodegen, args: []ast.Node) CodegenError!void { try genConst(self, args, ".{ .bytes = 0, .key = 0, .overlapped = null }"); }
fn genInvalidHandle(self: *NativeCodegen, args: []ast.Node) CodegenError!void { try genConst(self, args, "-1"); }
fn genErrIoPending(self: *NativeCodegen, args: []ast.Node) CodegenError!void { try genConst(self, args, "997"); }
fn genErrNetname(self: *NativeCodegen, args: []ast.Node) CodegenError!void { try genConst(self, args, "64"); }
fn genErrSemTimeout(self: *NativeCodegen, args: []ast.Node) CodegenError!void { try genConst(self, args, "121"); }
fn genErrPipeBusy(self: *NativeCodegen, args: []ast.Node) CodegenError!void { try genConst(self, args, "231"); }
fn genInfinite(self: *NativeCodegen, args: []ast.Node) CodegenError!void { try genConst(self, args, "0xFFFFFFFF"); }
