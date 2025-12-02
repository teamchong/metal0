/// Python _overlapped module - Windows overlapped I/O
const std = @import("std");
const ast = @import("ast");
const CodegenError = @import("main.zig").CodegenError;
const NativeCodegen = @import("main.zig").NativeCodegen;

const ModuleHandler = *const fn (*NativeCodegen, []ast.Node) CodegenError!void;
fn genConst(comptime v: []const u8) ModuleHandler {
    return struct { fn f(self: *NativeCodegen, args: []ast.Node) CodegenError!void { _ = args; try self.emit(v); } }.f;
}

pub const Funcs = std.StaticStringMap(ModuleHandler).initComptime(.{
    .{ "overlapped", genConst(".{}") }, .{ "create_event", genConst("0") }, .{ "create_io_completion_port", genConst("0") },
    .{ "get_queued_completion_status", genConst(".{ .bytes = 0, .key = 0, .overlapped = null }") },
    .{ "post_queued_completion_status", genConst("{}") }, .{ "reset_event", genConst("{}") }, .{ "set_event", genConst("{}") },
    .{ "format_message", genConst("\"\"") }, .{ "bind_local", genConst("{}") }, .{ "register_wait_with_queue", genConst("0") },
    .{ "unregister_wait", genConst("{}") }, .{ "unregister_wait_ex", genConst("{}") },
    .{ "connect_pipe", genConst(".{}") }, .{ "w_s_a_connect", genConst(".{}") },
    .{ "i_n_v_a_l_i_d__h_a_n_d_l_e__v_a_l_u_e", genConst("-1") }, .{ "n_u_l_l", genConst("0") },
    .{ "e_r_r_o_r__i_o__p_e_n_d_i_n_g", genConst("997") }, .{ "e_r_r_o_r__n_e_t_n_a_m_e__d_e_l_e_t_e_d", genConst("64") },
    .{ "e_r_r_o_r__s_e_m__t_i_m_e_o_u_t", genConst("121") }, .{ "e_r_r_o_r__p_i_p_e__b_u_s_y", genConst("231") },
    .{ "i_n_f_i_n_i_t_e", genConst("0xFFFFFFFF") },
});
