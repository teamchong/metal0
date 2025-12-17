/// Python _winapi module - Windows API functions
/// MIGRATED TO ZIGBUILDER
const std = @import("std");
const h = @import("mod_helper.zig");
const builder_mod = @import("codegen.builder");
const ast = @import("analysis.ast");

pub const Funcs = std.StaticStringMap(h.H).initComptime(.{
    // Functions
    .{ "close_handle", genCloseHandle },
    .{ "create_file", genCreateFile },
    .{ "create_junction", genCreateJunction },
    .{ "create_named_pipe", genCreateNamedPipe },
    .{ "create_pipe", genCreatePipe },
    .{ "create_process", genCreateProcess },
    .{ "duplicate_handle", genDuplicateHandle },
    .{ "exit_process", genExitProcess },
    .{ "get_current_process", genGetCurrentProcess },
    .{ "get_exit_code_process", genGetExitCodeProcess },
    .{ "get_last_error", genGetLastError },
    .{ "get_module_file_name", genGetModuleFileName },
    .{ "get_std_handle", genGetStdHandle },
    .{ "get_version", genGetVersion },
    .{ "open_process", genOpenProcess },
    .{ "peek_named_pipe", genPeekNamedPipe },
    .{ "read_file", genReadFile },
    .{ "set_named_pipe_handle_state", genSetNamedPipeHandleState },
    .{ "terminate_process", genTerminateProcess },
    .{ "wait_for_multiple_objects", genWaitForMultipleObjects },
    .{ "wait_for_single_object", genWaitForSingleObject },
    .{ "wait_named_pipe", genWaitNamedPipe },
    .{ "write_file", genWriteFile },
    .{ "connect_named_pipe", genConnectNamedPipe },
    .{ "get_file_type", genGetFileType },
    // Constants
    .{ "s_t_d__i_n_p_u_t__h_a_n_d_l_e", genStdInputHandle },
    .{ "s_t_d__o_u_t_p_u_t__h_a_n_d_l_e", genStdOutputHandle },
    .{ "s_t_d__e_r_r_o_r__h_a_n_d_l_e", genStdErrorHandle },
    .{ "d_u_p_l_i_c_a_t_e__s_a_m_e__a_c_c_e_s_s", genDuplicateSameAccess },
    .{ "d_u_p_l_i_c_a_t_e__c_l_o_s_e__s_o_u_r_c_e", genDuplicateCloseSource },
    .{ "s_t_a_r_t_u_p_i_n_f_o", genStartupinfo },
    .{ "i_n_f_i_n_i_t_e", genInfinite },
    .{ "w_a_i_t__o_b_j_e_c_t_0", genWaitObject0 },
    .{ "w_a_i_t__a_b_a_n_d_o_n_e_d_0", genWaitAbandoned0 },
    .{ "w_a_i_t__t_i_m_e_o_u_t", genWaitTimeout },
    .{ "c_r_e_a_t_e__n_e_w__c_o_n_s_o_l_e", genCreateNewConsole },
    .{ "c_r_e_a_t_e__n_e_w__p_r_o_c_e_s_s__g_r_o_u_p", genCreateNewProcessGroup },
    .{ "s_t_i_l_l__a_c_t_i_v_e", genStillActive },
    .{ "p_i_p_e__a_c_c_e_s_s__i_n_b_o_u_n_d", genPipeAccessInbound },
    .{ "p_i_p_e__a_c_c_e_s_s__o_u_t_b_o_u_n_d", genPipeAccessOutbound },
    .{ "p_i_p_e__a_c_c_e_s_s__d_u_p_l_e_x", genPipeAccessDuplex },
    .{ "n_m_p_w_a_i_t__w_a_i_t__f_o_r_e_v_e_r", genNmpwaitWaitForever },
    .{ "g_e_n_e_r_i_c__r_e_a_d", genGenericRead },
    .{ "g_e_n_e_r_i_c__w_r_i_t_e", genGenericWrite },
    .{ "o_p_e_n__e_x_i_s_t_i_n_g", genOpenExisting },
    .{ "f_i_l_e__f_l_a_g__o_v_e_r_l_a_p_p_e_d", genFileFlagOverlapped },
    .{ "f_i_l_e__f_l_a_g__f_i_r_s_t__p_i_p_e__i_n_s_t_a_n_c_e", genFileFlagFirstPipeInstance },
    .{ "p_i_p_e__w_a_i_t", genPipeWait },
    .{ "p_i_p_e__t_y_p_e__m_e_s_s_a_g_e", genPipeTypeMessage },
    .{ "p_i_p_e__r_e_a_d_m_o_d_e__m_e_s_s_a_g_e", genPipeReadmodeMessage },
    .{ "p_i_p_e__u_n_l_i_m_i_t_e_d__i_n_s_t_a_n_c_e_s", genPipeUnlimitedInstances },
    .{ "e_r_r_o_r__i_o__p_e_n_d_i_n_g", genErrorIoPending },
    .{ "e_r_r_o_r__p_i_p_e__b_u_s_y", genErrorPipeBusy },
    .{ "e_r_r_o_r__a_l_r_e_a_d_y__e_x_i_s_t_s", genErrorAlreadyExists },
    .{ "e_r_r_o_r__b_r_o_k_e_n__p_i_p_e", genErrorBrokenPipe },
    .{ "e_r_r_o_r__n_o__d_a_t_a", genErrorNoData },
    .{ "e_r_r_o_r__n_o__s_y_s_t_e_m__r_e_s_o_u_r_c_e_s", genErrorNoSystemResources },
    .{ "e_r_r_o_r__o_p_e_r_a_t_i_o_n__a_b_o_r_t_e_d", genErrorOperationAborted },
    .{ "e_r_r_o_r__p_i_p_e__c_o_n_n_e_c_t_e_d", genErrorPipeConnected },
    .{ "e_r_r_o_r__s_e_m__t_i_m_e_o_u_t", genErrorSemTimeout },
    .{ "e_r_r_o_r__m_o_r_e__d_a_t_a", genErrorMoreData },
    .{ "e_r_r_o_r__n_e_t_n_a_m_e__d_e_l_e_t_e_d", genErrorNetnameDeleted },
    .{ "n_u_l_l", genNull },
});

fn genCloseHandle(self: *h.NativeCodegen, _: []ast.Node) h.CodegenError!void {
    const b = try self.getBuilder();
    try b.emitValue(builder_mod.ZigValue.raw("{}"), builder_mod.EmitConfig.forExpression());
}

fn genCreateFile(self: *h.NativeCodegen, _: []ast.Node) h.CodegenError!void {
    const b = try self.getBuilder();
    try b.emitValue(builder_mod.ZigValue.int(0), builder_mod.EmitConfig.forExpression());
}

fn genCreateJunction(self: *h.NativeCodegen, _: []ast.Node) h.CodegenError!void {
    const b = try self.getBuilder();
    try b.emitValue(builder_mod.ZigValue.raw("{}"), builder_mod.EmitConfig.forExpression());
}

fn genCreateNamedPipe(self: *h.NativeCodegen, _: []ast.Node) h.CodegenError!void {
    const b = try self.getBuilder();
    try b.emitValue(builder_mod.ZigValue.int(0), builder_mod.EmitConfig.forExpression());
}

fn genCreatePipe(self: *h.NativeCodegen, _: []ast.Node) h.CodegenError!void {
    const b = try self.getBuilder();
    try b.emitValue(builder_mod.ZigValue.raw(".{ .read = 0, .write = 0 }"), builder_mod.EmitConfig.forExpression());
}

fn genCreateProcess(self: *h.NativeCodegen, _: []ast.Node) h.CodegenError!void {
    const b = try self.getBuilder();
    try b.emitValue(builder_mod.ZigValue.raw(".{ .process = 0, .thread = 0, .pid = 0, .tid = 0 }"), builder_mod.EmitConfig.forExpression());
}

fn genDuplicateHandle(self: *h.NativeCodegen, _: []ast.Node) h.CodegenError!void {
    const b = try self.getBuilder();
    try b.emitValue(builder_mod.ZigValue.int(0), builder_mod.EmitConfig.forExpression());
}

fn genExitProcess(self: *h.NativeCodegen, _: []ast.Node) h.CodegenError!void {
    const b = try self.getBuilder();
    try b.emitValue(builder_mod.ZigValue.raw("{}"), builder_mod.EmitConfig.forExpression());
}

fn genGetCurrentProcess(self: *h.NativeCodegen, _: []ast.Node) h.CodegenError!void {
    const b = try self.getBuilder();
    try b.emitValue(builder_mod.ZigValue.int(-1), builder_mod.EmitConfig.forExpression());
}

fn genGetExitCodeProcess(self: *h.NativeCodegen, _: []ast.Node) h.CodegenError!void {
    const b = try self.getBuilder();
    try b.emitValue(builder_mod.ZigValue.int(0), builder_mod.EmitConfig.forExpression());
}

fn genGetLastError(self: *h.NativeCodegen, _: []ast.Node) h.CodegenError!void {
    const b = try self.getBuilder();
    try b.emitValue(builder_mod.ZigValue.int(0), builder_mod.EmitConfig.forExpression());
}

fn genGetModuleFileName(self: *h.NativeCodegen, _: []ast.Node) h.CodegenError!void {
    const b = try self.getBuilder();
    try b.emitValue(builder_mod.ZigValue.string(""), builder_mod.EmitConfig.forExpression());
}

fn genGetStdHandle(self: *h.NativeCodegen, _: []ast.Node) h.CodegenError!void {
    const b = try self.getBuilder();
    try b.emitValue(builder_mod.ZigValue.int(0), builder_mod.EmitConfig.forExpression());
}

fn genGetVersion(self: *h.NativeCodegen, _: []ast.Node) h.CodegenError!void {
    const b = try self.getBuilder();
    try b.emitValue(builder_mod.ZigValue.int(0), builder_mod.EmitConfig.forExpression());
}

fn genOpenProcess(self: *h.NativeCodegen, _: []ast.Node) h.CodegenError!void {
    const b = try self.getBuilder();
    try b.emitValue(builder_mod.ZigValue.int(0), builder_mod.EmitConfig.forExpression());
}

fn genPeekNamedPipe(self: *h.NativeCodegen, _: []ast.Node) h.CodegenError!void {
    const b = try self.getBuilder();
    try b.emitValue(builder_mod.ZigValue.raw(".{ .data = \"\", .available = 0, .message = 0 }"), builder_mod.EmitConfig.forExpression());
}

fn genReadFile(self: *h.NativeCodegen, _: []ast.Node) h.CodegenError!void {
    const b = try self.getBuilder();
    try b.emitValue(builder_mod.ZigValue.raw(".{ .data = \"\", .error = 0 }"), builder_mod.EmitConfig.forExpression());
}

fn genSetNamedPipeHandleState(self: *h.NativeCodegen, _: []ast.Node) h.CodegenError!void {
    const b = try self.getBuilder();
    try b.emitValue(builder_mod.ZigValue.raw("{}"), builder_mod.EmitConfig.forExpression());
}

fn genTerminateProcess(self: *h.NativeCodegen, _: []ast.Node) h.CodegenError!void {
    const b = try self.getBuilder();
    try b.emitValue(builder_mod.ZigValue.raw("{}"), builder_mod.EmitConfig.forExpression());
}

fn genWaitForMultipleObjects(self: *h.NativeCodegen, _: []ast.Node) h.CodegenError!void {
    const b = try self.getBuilder();
    try b.emitValue(builder_mod.ZigValue.int(0), builder_mod.EmitConfig.forExpression());
}

fn genWaitForSingleObject(self: *h.NativeCodegen, _: []ast.Node) h.CodegenError!void {
    const b = try self.getBuilder();
    try b.emitValue(builder_mod.ZigValue.int(0), builder_mod.EmitConfig.forExpression());
}

fn genWaitNamedPipe(self: *h.NativeCodegen, _: []ast.Node) h.CodegenError!void {
    const b = try self.getBuilder();
    try b.emitValue(builder_mod.ZigValue.raw("{}"), builder_mod.EmitConfig.forExpression());
}

fn genWriteFile(self: *h.NativeCodegen, _: []ast.Node) h.CodegenError!void {
    const b = try self.getBuilder();
    try b.emitValue(builder_mod.ZigValue.raw(".{ .written = 0, .error = 0 }"), builder_mod.EmitConfig.forExpression());
}

fn genConnectNamedPipe(self: *h.NativeCodegen, _: []ast.Node) h.CodegenError!void {
    const b = try self.getBuilder();
    try b.emitValue(builder_mod.ZigValue.raw("{}"), builder_mod.EmitConfig.forExpression());
}

fn genGetFileType(self: *h.NativeCodegen, _: []ast.Node) h.CodegenError!void {
    const b = try self.getBuilder();
    try b.emitValue(builder_mod.ZigValue.int(1), builder_mod.EmitConfig.forExpression());
}

// Constants
fn genStdInputHandle(self: *h.NativeCodegen, _: []ast.Node) h.CodegenError!void {
    const b = try self.getBuilder();
    try b.emitValue(builder_mod.ZigValue.int(-10), builder_mod.EmitConfig.forExpression());
}

fn genStdOutputHandle(self: *h.NativeCodegen, _: []ast.Node) h.CodegenError!void {
    const b = try self.getBuilder();
    try b.emitValue(builder_mod.ZigValue.int(-11), builder_mod.EmitConfig.forExpression());
}

fn genStdErrorHandle(self: *h.NativeCodegen, _: []ast.Node) h.CodegenError!void {
    const b = try self.getBuilder();
    try b.emitValue(builder_mod.ZigValue.int(-12), builder_mod.EmitConfig.forExpression());
}

fn genDuplicateSameAccess(self: *h.NativeCodegen, _: []ast.Node) h.CodegenError!void {
    const b = try self.getBuilder();
    try b.emitValue(builder_mod.ZigValue.int(2), builder_mod.EmitConfig.forExpression());
}

fn genDuplicateCloseSource(self: *h.NativeCodegen, _: []ast.Node) h.CodegenError!void {
    const b = try self.getBuilder();
    try b.emitValue(builder_mod.ZigValue.int(1), builder_mod.EmitConfig.forExpression());
}

fn genStartupinfo(self: *h.NativeCodegen, _: []ast.Node) h.CodegenError!void {
    const b = try self.getBuilder();
    try b.emitValue(builder_mod.ZigValue.raw(".{}"), builder_mod.EmitConfig.forExpression());
}

fn genInfinite(self: *h.NativeCodegen, _: []ast.Node) h.CodegenError!void {
    const b = try self.getBuilder();
    try b.emitValue(builder_mod.ZigValue.raw("0xFFFFFFFF"), builder_mod.EmitConfig.forExpression());
}

fn genWaitObject0(self: *h.NativeCodegen, _: []ast.Node) h.CodegenError!void {
    const b = try self.getBuilder();
    try b.emitValue(builder_mod.ZigValue.int(0), builder_mod.EmitConfig.forExpression());
}

fn genWaitAbandoned0(self: *h.NativeCodegen, _: []ast.Node) h.CodegenError!void {
    const b = try self.getBuilder();
    try b.emitValue(builder_mod.ZigValue.raw("0x80"), builder_mod.EmitConfig.forExpression());
}

fn genWaitTimeout(self: *h.NativeCodegen, _: []ast.Node) h.CodegenError!void {
    const b = try self.getBuilder();
    try b.emitValue(builder_mod.ZigValue.int(258), builder_mod.EmitConfig.forExpression());
}

fn genCreateNewConsole(self: *h.NativeCodegen, _: []ast.Node) h.CodegenError!void {
    const b = try self.getBuilder();
    try b.emitValue(builder_mod.ZigValue.raw("0x10"), builder_mod.EmitConfig.forExpression());
}

fn genCreateNewProcessGroup(self: *h.NativeCodegen, _: []ast.Node) h.CodegenError!void {
    const b = try self.getBuilder();
    try b.emitValue(builder_mod.ZigValue.raw("0x200"), builder_mod.EmitConfig.forExpression());
}

fn genStillActive(self: *h.NativeCodegen, _: []ast.Node) h.CodegenError!void {
    const b = try self.getBuilder();
    try b.emitValue(builder_mod.ZigValue.int(259), builder_mod.EmitConfig.forExpression());
}

fn genPipeAccessInbound(self: *h.NativeCodegen, _: []ast.Node) h.CodegenError!void {
    const b = try self.getBuilder();
    try b.emitValue(builder_mod.ZigValue.int(1), builder_mod.EmitConfig.forExpression());
}

fn genPipeAccessOutbound(self: *h.NativeCodegen, _: []ast.Node) h.CodegenError!void {
    const b = try self.getBuilder();
    try b.emitValue(builder_mod.ZigValue.int(2), builder_mod.EmitConfig.forExpression());
}

fn genPipeAccessDuplex(self: *h.NativeCodegen, _: []ast.Node) h.CodegenError!void {
    const b = try self.getBuilder();
    try b.emitValue(builder_mod.ZigValue.int(3), builder_mod.EmitConfig.forExpression());
}

fn genNmpwaitWaitForever(self: *h.NativeCodegen, _: []ast.Node) h.CodegenError!void {
    const b = try self.getBuilder();
    try b.emitValue(builder_mod.ZigValue.raw("0xFFFFFFFF"), builder_mod.EmitConfig.forExpression());
}

fn genGenericRead(self: *h.NativeCodegen, _: []ast.Node) h.CodegenError!void {
    const b = try self.getBuilder();
    try b.emitValue(builder_mod.ZigValue.raw("0x80000000"), builder_mod.EmitConfig.forExpression());
}

fn genGenericWrite(self: *h.NativeCodegen, _: []ast.Node) h.CodegenError!void {
    const b = try self.getBuilder();
    try b.emitValue(builder_mod.ZigValue.raw("0x40000000"), builder_mod.EmitConfig.forExpression());
}

fn genOpenExisting(self: *h.NativeCodegen, _: []ast.Node) h.CodegenError!void {
    const b = try self.getBuilder();
    try b.emitValue(builder_mod.ZigValue.int(3), builder_mod.EmitConfig.forExpression());
}

fn genFileFlagOverlapped(self: *h.NativeCodegen, _: []ast.Node) h.CodegenError!void {
    const b = try self.getBuilder();
    try b.emitValue(builder_mod.ZigValue.raw("0x40000000"), builder_mod.EmitConfig.forExpression());
}

fn genFileFlagFirstPipeInstance(self: *h.NativeCodegen, _: []ast.Node) h.CodegenError!void {
    const b = try self.getBuilder();
    try b.emitValue(builder_mod.ZigValue.raw("0x80000"), builder_mod.EmitConfig.forExpression());
}

fn genPipeWait(self: *h.NativeCodegen, _: []ast.Node) h.CodegenError!void {
    const b = try self.getBuilder();
    try b.emitValue(builder_mod.ZigValue.int(0), builder_mod.EmitConfig.forExpression());
}

fn genPipeTypeMessage(self: *h.NativeCodegen, _: []ast.Node) h.CodegenError!void {
    const b = try self.getBuilder();
    try b.emitValue(builder_mod.ZigValue.int(4), builder_mod.EmitConfig.forExpression());
}

fn genPipeReadmodeMessage(self: *h.NativeCodegen, _: []ast.Node) h.CodegenError!void {
    const b = try self.getBuilder();
    try b.emitValue(builder_mod.ZigValue.int(2), builder_mod.EmitConfig.forExpression());
}

fn genPipeUnlimitedInstances(self: *h.NativeCodegen, _: []ast.Node) h.CodegenError!void {
    const b = try self.getBuilder();
    try b.emitValue(builder_mod.ZigValue.int(255), builder_mod.EmitConfig.forExpression());
}

fn genErrorIoPending(self: *h.NativeCodegen, _: []ast.Node) h.CodegenError!void {
    const b = try self.getBuilder();
    try b.emitValue(builder_mod.ZigValue.int(997), builder_mod.EmitConfig.forExpression());
}

fn genErrorPipeBusy(self: *h.NativeCodegen, _: []ast.Node) h.CodegenError!void {
    const b = try self.getBuilder();
    try b.emitValue(builder_mod.ZigValue.int(231), builder_mod.EmitConfig.forExpression());
}

fn genErrorAlreadyExists(self: *h.NativeCodegen, _: []ast.Node) h.CodegenError!void {
    const b = try self.getBuilder();
    try b.emitValue(builder_mod.ZigValue.int(183), builder_mod.EmitConfig.forExpression());
}

fn genErrorBrokenPipe(self: *h.NativeCodegen, _: []ast.Node) h.CodegenError!void {
    const b = try self.getBuilder();
    try b.emitValue(builder_mod.ZigValue.int(109), builder_mod.EmitConfig.forExpression());
}

fn genErrorNoData(self: *h.NativeCodegen, _: []ast.Node) h.CodegenError!void {
    const b = try self.getBuilder();
    try b.emitValue(builder_mod.ZigValue.int(232), builder_mod.EmitConfig.forExpression());
}

fn genErrorNoSystemResources(self: *h.NativeCodegen, _: []ast.Node) h.CodegenError!void {
    const b = try self.getBuilder();
    try b.emitValue(builder_mod.ZigValue.int(1450), builder_mod.EmitConfig.forExpression());
}

fn genErrorOperationAborted(self: *h.NativeCodegen, _: []ast.Node) h.CodegenError!void {
    const b = try self.getBuilder();
    try b.emitValue(builder_mod.ZigValue.int(995), builder_mod.EmitConfig.forExpression());
}

fn genErrorPipeConnected(self: *h.NativeCodegen, _: []ast.Node) h.CodegenError!void {
    const b = try self.getBuilder();
    try b.emitValue(builder_mod.ZigValue.int(535), builder_mod.EmitConfig.forExpression());
}

fn genErrorSemTimeout(self: *h.NativeCodegen, _: []ast.Node) h.CodegenError!void {
    const b = try self.getBuilder();
    try b.emitValue(builder_mod.ZigValue.int(121), builder_mod.EmitConfig.forExpression());
}

fn genErrorMoreData(self: *h.NativeCodegen, _: []ast.Node) h.CodegenError!void {
    const b = try self.getBuilder();
    try b.emitValue(builder_mod.ZigValue.int(234), builder_mod.EmitConfig.forExpression());
}

fn genErrorNetnameDeleted(self: *h.NativeCodegen, _: []ast.Node) h.CodegenError!void {
    const b = try self.getBuilder();
    try b.emitValue(builder_mod.ZigValue.int(64), builder_mod.EmitConfig.forExpression());
}

fn genNull(self: *h.NativeCodegen, _: []ast.Node) h.CodegenError!void {
    const b = try self.getBuilder();
    try b.emitValue(builder_mod.ZigValue.int(0), builder_mod.EmitConfig.forExpression());
}

