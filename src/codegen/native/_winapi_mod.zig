/// Python _winapi module - Windows API functions
const std = @import("std");
const ast = @import("ast");
const CodegenError = @import("main.zig").CodegenError;
const NativeCodegen = @import("main.zig").NativeCodegen;

const ModuleHandler = *const fn (*NativeCodegen, []ast.Node) CodegenError!void;
pub const Funcs = std.StaticStringMap(ModuleHandler).initComptime(.{
    .{ "close_handle", genCloseHandle }, .{ "create_file", genCreateFile }, .{ "create_junction", genCreateJunction },
    .{ "create_named_pipe", genCreateNamedPipe }, .{ "create_pipe", genCreatePipe }, .{ "create_process", genCreateProcess },
    .{ "duplicate_handle", genDuplicateHandle }, .{ "exit_process", genExitProcess }, .{ "get_current_process", genGetCurrentProcess },
    .{ "get_exit_code_process", genGetExitCodeProcess }, .{ "get_last_error", genGetLastError }, .{ "get_module_file_name", genGetModuleFileName },
    .{ "get_std_handle", genGetStdHandle }, .{ "get_version", genGetVersion }, .{ "open_process", genOpenProcess },
    .{ "peek_named_pipe", genPeekNamedPipe }, .{ "read_file", genReadFile }, .{ "set_named_pipe_handle_state", genSetNamedPipeHandleState },
    .{ "terminate_process", genTerminateProcess }, .{ "wait_for_multiple_objects", genWaitForMultipleObjects },
    .{ "wait_for_single_object", genWaitForSingleObject }, .{ "wait_named_pipe", genWaitNamedPipe }, .{ "write_file", genWriteFile },
    .{ "connect_named_pipe", genConnectNamedPipe }, .{ "get_file_type", genGetFileType },
    .{ "s_t_d__i_n_p_u_t__h_a_n_d_l_e", genSTD_INPUT_HANDLE }, .{ "s_t_d__o_u_t_p_u_t__h_a_n_d_l_e", genSTD_OUTPUT_HANDLE },
    .{ "s_t_d__e_r_r_o_r__h_a_n_d_l_e", genSTD_ERROR_HANDLE }, .{ "d_u_p_l_i_c_a_t_e__s_a_m_e__a_c_c_e_s_s", genDUPLICATE_SAME_ACCESS },
    .{ "d_u_p_l_i_c_a_t_e__c_l_o_s_e__s_o_u_r_c_e", genDUPLICATE_CLOSE_SOURCE }, .{ "s_t_a_r_t_u_p_i_n_f_o", genSTARTUPINFO },
    .{ "i_n_f_i_n_i_t_e", genINFINITE }, .{ "w_a_i_t__o_b_j_e_c_t_0", genWAIT_OBJECT_0 }, .{ "w_a_i_t__a_b_a_n_d_o_n_e_d_0", genWAIT_ABANDONED_0 },
    .{ "w_a_i_t__t_i_m_e_o_u_t", genWAIT_TIMEOUT }, .{ "c_r_e_a_t_e__n_e_w__c_o_n_s_o_l_e", genCREATE_NEW_CONSOLE },
    .{ "c_r_e_a_t_e__n_e_w__p_r_o_c_e_s_s__g_r_o_u_p", genCREATE_NEW_PROCESS_GROUP }, .{ "s_t_i_l_l__a_c_t_i_v_e", genSTILL_ACTIVE },
    .{ "p_i_p_e__a_c_c_e_s_s__i_n_b_o_u_n_d", genPIPE_ACCESS_INBOUND }, .{ "p_i_p_e__a_c_c_e_s_s__o_u_t_b_o_u_n_d", genPIPE_ACCESS_OUTBOUND },
    .{ "p_i_p_e__a_c_c_e_s_s__d_u_p_l_e_x", genPIPE_ACCESS_DUPLEX }, .{ "n_m_p_w_a_i_t__w_a_i_t__f_o_r_e_v_e_r", genNMPWAIT_WAIT_FOREVER },
    .{ "g_e_n_e_r_i_c__r_e_a_d", genGENERIC_READ }, .{ "g_e_n_e_r_i_c__w_r_i_t_e", genGENERIC_WRITE }, .{ "o_p_e_n__e_x_i_s_t_i_n_g", genOPEN_EXISTING },
    .{ "f_i_l_e__f_l_a_g__o_v_e_r_l_a_p_p_e_d", genFILE_FLAG_OVERLAPPED }, .{ "f_i_l_e__f_l_a_g__f_i_r_s_t__p_i_p_e__i_n_s_t_a_n_c_e", genFILE_FLAG_FIRST_PIPE_INSTANCE },
    .{ "p_i_p_e__w_a_i_t", genPIPE_WAIT }, .{ "p_i_p_e__t_y_p_e__m_e_s_s_a_g_e", genPIPE_TYPE_MESSAGE },
    .{ "p_i_p_e__r_e_a_d_m_o_d_e__m_e_s_s_a_g_e", genPIPE_READMODE_MESSAGE }, .{ "p_i_p_e__u_n_l_i_m_i_t_e_d__i_n_s_t_a_n_c_e_s", genPIPE_UNLIMITED_INSTANCES },
    .{ "e_r_r_o_r__i_o__p_e_n_d_i_n_g", genERROR_IO_PENDING }, .{ "e_r_r_o_r__p_i_p_e__b_u_s_y", genERROR_PIPE_BUSY },
    .{ "e_r_r_o_r__a_l_r_e_a_d_y__e_x_i_s_t_s", genERROR_ALREADY_EXISTS }, .{ "e_r_r_o_r__b_r_o_k_e_n__p_i_p_e", genERROR_BROKEN_PIPE },
    .{ "e_r_r_o_r__n_o__d_a_t_a", genERROR_NO_DATA }, .{ "e_r_r_o_r__n_o__s_y_s_t_e_m__r_e_s_o_u_r_c_e_s", genERROR_NO_SYSTEM_RESOURCES },
    .{ "e_r_r_o_r__o_p_e_r_a_t_i_o_n__a_b_o_r_t_e_d", genERROR_OPERATION_ABORTED }, .{ "e_r_r_o_r__p_i_p_e__c_o_n_n_e_c_t_e_d", genERROR_PIPE_CONNECTED },
    .{ "e_r_r_o_r__s_e_m__t_i_m_e_o_u_t", genERROR_SEM_TIMEOUT }, .{ "e_r_r_o_r__m_o_r_e__d_a_t_a", genERROR_MORE_DATA },
    .{ "e_r_r_o_r__n_e_t_n_a_m_e__d_e_l_e_t_e_d", genERROR_NETNAME_DELETED }, .{ "n_u_l_l", genNULL },
});

// Helper
fn genConst(self: *NativeCodegen, args: []ast.Node, value: []const u8) CodegenError!void { _ = args; try self.emit(value); }

// Functions
pub fn genCloseHandle(self: *NativeCodegen, args: []ast.Node) CodegenError!void { try genConst(self, args, "{}"); }
pub fn genCreateFile(self: *NativeCodegen, args: []ast.Node) CodegenError!void { try genConst(self, args, "0"); }
pub fn genCreateJunction(self: *NativeCodegen, args: []ast.Node) CodegenError!void { try genConst(self, args, "{}"); }
pub fn genCreateNamedPipe(self: *NativeCodegen, args: []ast.Node) CodegenError!void { try genConst(self, args, "0"); }
pub fn genCreatePipe(self: *NativeCodegen, args: []ast.Node) CodegenError!void { try genConst(self, args, ".{ .read = 0, .write = 0 }"); }
pub fn genCreateProcess(self: *NativeCodegen, args: []ast.Node) CodegenError!void { try genConst(self, args, ".{ .process = 0, .thread = 0, .pid = 0, .tid = 0 }"); }
pub fn genDuplicateHandle(self: *NativeCodegen, args: []ast.Node) CodegenError!void { try genConst(self, args, "0"); }
pub fn genExitProcess(self: *NativeCodegen, args: []ast.Node) CodegenError!void { try genConst(self, args, "{}"); }
pub fn genGetCurrentProcess(self: *NativeCodegen, args: []ast.Node) CodegenError!void { try genConst(self, args, "-1"); }
pub fn genGetExitCodeProcess(self: *NativeCodegen, args: []ast.Node) CodegenError!void { try genConst(self, args, "0"); }
pub fn genGetLastError(self: *NativeCodegen, args: []ast.Node) CodegenError!void { try genConst(self, args, "0"); }
pub fn genGetModuleFileName(self: *NativeCodegen, args: []ast.Node) CodegenError!void { try genConst(self, args, "\"\""); }
pub fn genGetStdHandle(self: *NativeCodegen, args: []ast.Node) CodegenError!void { try genConst(self, args, "0"); }
pub fn genGetVersion(self: *NativeCodegen, args: []ast.Node) CodegenError!void { try genConst(self, args, "0"); }
pub fn genOpenProcess(self: *NativeCodegen, args: []ast.Node) CodegenError!void { try genConst(self, args, "0"); }
pub fn genPeekNamedPipe(self: *NativeCodegen, args: []ast.Node) CodegenError!void { try genConst(self, args, ".{ .data = \"\", .available = 0, .message = 0 }"); }
pub fn genReadFile(self: *NativeCodegen, args: []ast.Node) CodegenError!void { try genConst(self, args, ".{ .data = \"\", .error = 0 }"); }
pub fn genSetNamedPipeHandleState(self: *NativeCodegen, args: []ast.Node) CodegenError!void { try genConst(self, args, "{}"); }
pub fn genTerminateProcess(self: *NativeCodegen, args: []ast.Node) CodegenError!void { try genConst(self, args, "{}"); }
pub fn genWaitForMultipleObjects(self: *NativeCodegen, args: []ast.Node) CodegenError!void { try genConst(self, args, "0"); }
pub fn genWaitForSingleObject(self: *NativeCodegen, args: []ast.Node) CodegenError!void { try genConst(self, args, "0"); }
pub fn genWaitNamedPipe(self: *NativeCodegen, args: []ast.Node) CodegenError!void { try genConst(self, args, "{}"); }
pub fn genWriteFile(self: *NativeCodegen, args: []ast.Node) CodegenError!void { try genConst(self, args, ".{ .written = 0, .error = 0 }"); }
pub fn genConnectNamedPipe(self: *NativeCodegen, args: []ast.Node) CodegenError!void { try genConst(self, args, "{}"); }
pub fn genGetFileType(self: *NativeCodegen, args: []ast.Node) CodegenError!void { try genConst(self, args, "1"); }

// Constants
pub fn genSTD_INPUT_HANDLE(self: *NativeCodegen, args: []ast.Node) CodegenError!void { try genConst(self, args, "-10"); }
pub fn genSTD_OUTPUT_HANDLE(self: *NativeCodegen, args: []ast.Node) CodegenError!void { try genConst(self, args, "-11"); }
pub fn genSTD_ERROR_HANDLE(self: *NativeCodegen, args: []ast.Node) CodegenError!void { try genConst(self, args, "-12"); }
pub fn genDUPLICATE_SAME_ACCESS(self: *NativeCodegen, args: []ast.Node) CodegenError!void { try genConst(self, args, "2"); }
pub fn genDUPLICATE_CLOSE_SOURCE(self: *NativeCodegen, args: []ast.Node) CodegenError!void { try genConst(self, args, "1"); }
pub fn genSTARTUPINFO(self: *NativeCodegen, args: []ast.Node) CodegenError!void { try genConst(self, args, ".{}"); }
pub fn genINFINITE(self: *NativeCodegen, args: []ast.Node) CodegenError!void { try genConst(self, args, "0xFFFFFFFF"); }
pub fn genWAIT_OBJECT_0(self: *NativeCodegen, args: []ast.Node) CodegenError!void { try genConst(self, args, "0"); }
pub fn genWAIT_ABANDONED_0(self: *NativeCodegen, args: []ast.Node) CodegenError!void { try genConst(self, args, "0x80"); }
pub fn genWAIT_TIMEOUT(self: *NativeCodegen, args: []ast.Node) CodegenError!void { try genConst(self, args, "258"); }
pub fn genCREATE_NEW_CONSOLE(self: *NativeCodegen, args: []ast.Node) CodegenError!void { try genConst(self, args, "0x10"); }
pub fn genCREATE_NEW_PROCESS_GROUP(self: *NativeCodegen, args: []ast.Node) CodegenError!void { try genConst(self, args, "0x200"); }
pub fn genSTILL_ACTIVE(self: *NativeCodegen, args: []ast.Node) CodegenError!void { try genConst(self, args, "259"); }
pub fn genPIPE_ACCESS_INBOUND(self: *NativeCodegen, args: []ast.Node) CodegenError!void { try genConst(self, args, "1"); }
pub fn genPIPE_ACCESS_OUTBOUND(self: *NativeCodegen, args: []ast.Node) CodegenError!void { try genConst(self, args, "2"); }
pub fn genPIPE_ACCESS_DUPLEX(self: *NativeCodegen, args: []ast.Node) CodegenError!void { try genConst(self, args, "3"); }
pub fn genNMPWAIT_WAIT_FOREVER(self: *NativeCodegen, args: []ast.Node) CodegenError!void { try genConst(self, args, "0xFFFFFFFF"); }
pub fn genGENERIC_READ(self: *NativeCodegen, args: []ast.Node) CodegenError!void { try genConst(self, args, "0x80000000"); }
pub fn genGENERIC_WRITE(self: *NativeCodegen, args: []ast.Node) CodegenError!void { try genConst(self, args, "0x40000000"); }
pub fn genOPEN_EXISTING(self: *NativeCodegen, args: []ast.Node) CodegenError!void { try genConst(self, args, "3"); }
pub fn genFILE_FLAG_OVERLAPPED(self: *NativeCodegen, args: []ast.Node) CodegenError!void { try genConst(self, args, "0x40000000"); }
pub fn genFILE_FLAG_FIRST_PIPE_INSTANCE(self: *NativeCodegen, args: []ast.Node) CodegenError!void { try genConst(self, args, "0x80000"); }
pub fn genPIPE_WAIT(self: *NativeCodegen, args: []ast.Node) CodegenError!void { try genConst(self, args, "0"); }
pub fn genPIPE_TYPE_MESSAGE(self: *NativeCodegen, args: []ast.Node) CodegenError!void { try genConst(self, args, "4"); }
pub fn genPIPE_READMODE_MESSAGE(self: *NativeCodegen, args: []ast.Node) CodegenError!void { try genConst(self, args, "2"); }
pub fn genPIPE_UNLIMITED_INSTANCES(self: *NativeCodegen, args: []ast.Node) CodegenError!void { try genConst(self, args, "255"); }
pub fn genERROR_IO_PENDING(self: *NativeCodegen, args: []ast.Node) CodegenError!void { try genConst(self, args, "997"); }
pub fn genERROR_PIPE_BUSY(self: *NativeCodegen, args: []ast.Node) CodegenError!void { try genConst(self, args, "231"); }
pub fn genERROR_ALREADY_EXISTS(self: *NativeCodegen, args: []ast.Node) CodegenError!void { try genConst(self, args, "183"); }
pub fn genERROR_BROKEN_PIPE(self: *NativeCodegen, args: []ast.Node) CodegenError!void { try genConst(self, args, "109"); }
pub fn genERROR_NO_DATA(self: *NativeCodegen, args: []ast.Node) CodegenError!void { try genConst(self, args, "232"); }
pub fn genERROR_NO_SYSTEM_RESOURCES(self: *NativeCodegen, args: []ast.Node) CodegenError!void { try genConst(self, args, "1450"); }
pub fn genERROR_OPERATION_ABORTED(self: *NativeCodegen, args: []ast.Node) CodegenError!void { try genConst(self, args, "995"); }
pub fn genERROR_PIPE_CONNECTED(self: *NativeCodegen, args: []ast.Node) CodegenError!void { try genConst(self, args, "535"); }
pub fn genERROR_SEM_TIMEOUT(self: *NativeCodegen, args: []ast.Node) CodegenError!void { try genConst(self, args, "121"); }
pub fn genERROR_MORE_DATA(self: *NativeCodegen, args: []ast.Node) CodegenError!void { try genConst(self, args, "234"); }
pub fn genERROR_NETNAME_DELETED(self: *NativeCodegen, args: []ast.Node) CodegenError!void { try genConst(self, args, "64"); }
pub fn genNULL(self: *NativeCodegen, args: []ast.Node) CodegenError!void { try genConst(self, args, "0"); }
