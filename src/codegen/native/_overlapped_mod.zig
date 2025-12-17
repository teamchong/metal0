/// Python _overlapped module - Windows overlapped I/O
/// MIGRATED TO ZIGBUILDER
const std = @import("std");
const h = @import("mod_helper.zig");
const builder_mod = @import("codegen.builder");
const ast = @import("analysis.ast");

pub const Funcs = std.StaticStringMap(h.H).initComptime(.{
    .{ "overlapped", genOverlapped },
    .{ "create_event", genCreateEvent },
    .{ "create_io_completion_port", genCreateIoCompletionPort },
    .{ "get_queued_completion_status", genGetQueuedCompletionStatus },
    .{ "post_queued_completion_status", genPostQueuedCompletionStatus },
    .{ "reset_event", genResetEvent },
    .{ "set_event", genSetEvent },
    .{ "format_message", genFormatMessage },
    .{ "bind_local", genBindLocal },
    .{ "register_wait_with_queue", genRegisterWaitWithQueue },
    .{ "unregister_wait", genUnregisterWait },
    .{ "unregister_wait_ex", genUnregisterWaitEx },
    .{ "connect_pipe", genConnectPipe },
    .{ "w_s_a_connect", genWsaConnect },
    .{ "i_n_v_a_l_i_d__h_a_n_d_l_e__v_a_l_u_e", genInvalidHandleValue },
    .{ "n_u_l_l", genNull },
    .{ "e_r_r_o_r__i_o__p_e_n_d_i_n_g", genErrorIoPending },
    .{ "e_r_r_o_r__n_e_t_n_a_m_e__d_e_l_e_t_e_d", genErrorNetnameDeleted },
    .{ "e_r_r_o_r__s_e_m__t_i_m_e_o_u_t", genErrorSemTimeout },
    .{ "e_r_r_o_r__p_i_p_e__b_u_s_y", genErrorPipeBusy },
    .{ "i_n_f_i_n_i_t_e", genInfinite },
});

fn genOverlapped(self: *h.NativeCodegen, _: []ast.Node) h.CodegenError!void {
    const b = try self.getBuilder();
    try b.emitValue(builder_mod.ZigValue.raw(".{}"), builder_mod.EmitConfig.forExpression());
}

fn genCreateEvent(self: *h.NativeCodegen, _: []ast.Node) h.CodegenError!void {
    const b = try self.getBuilder();
    try b.emitValue(builder_mod.ZigValue.int(0), builder_mod.EmitConfig.forExpression());
}

fn genCreateIoCompletionPort(self: *h.NativeCodegen, _: []ast.Node) h.CodegenError!void {
    const b = try self.getBuilder();
    try b.emitValue(builder_mod.ZigValue.int(0), builder_mod.EmitConfig.forExpression());
}

fn genGetQueuedCompletionStatus(self: *h.NativeCodegen, _: []ast.Node) h.CodegenError!void {
    const b = try self.getBuilder();
    try b.emitValue(builder_mod.ZigValue.raw(".{ .bytes = 0, .key = 0, .overlapped = null }"), builder_mod.EmitConfig.forExpression());
}

fn genPostQueuedCompletionStatus(self: *h.NativeCodegen, _: []ast.Node) h.CodegenError!void {
    const b = try self.getBuilder();
    try b.emitValue(builder_mod.ZigValue.raw("{}"), builder_mod.EmitConfig.forExpression());
}

fn genResetEvent(self: *h.NativeCodegen, _: []ast.Node) h.CodegenError!void {
    const b = try self.getBuilder();
    try b.emitValue(builder_mod.ZigValue.raw("{}"), builder_mod.EmitConfig.forExpression());
}

fn genSetEvent(self: *h.NativeCodegen, _: []ast.Node) h.CodegenError!void {
    const b = try self.getBuilder();
    try b.emitValue(builder_mod.ZigValue.raw("{}"), builder_mod.EmitConfig.forExpression());
}

fn genFormatMessage(self: *h.NativeCodegen, _: []ast.Node) h.CodegenError!void {
    const b = try self.getBuilder();
    try b.emitValue(builder_mod.ZigValue.string(""), builder_mod.EmitConfig.forExpression());
}

fn genBindLocal(self: *h.NativeCodegen, _: []ast.Node) h.CodegenError!void {
    const b = try self.getBuilder();
    try b.emitValue(builder_mod.ZigValue.raw("{}"), builder_mod.EmitConfig.forExpression());
}

fn genRegisterWaitWithQueue(self: *h.NativeCodegen, _: []ast.Node) h.CodegenError!void {
    const b = try self.getBuilder();
    try b.emitValue(builder_mod.ZigValue.int(0), builder_mod.EmitConfig.forExpression());
}

fn genUnregisterWait(self: *h.NativeCodegen, _: []ast.Node) h.CodegenError!void {
    const b = try self.getBuilder();
    try b.emitValue(builder_mod.ZigValue.raw("{}"), builder_mod.EmitConfig.forExpression());
}

fn genUnregisterWaitEx(self: *h.NativeCodegen, _: []ast.Node) h.CodegenError!void {
    const b = try self.getBuilder();
    try b.emitValue(builder_mod.ZigValue.raw("{}"), builder_mod.EmitConfig.forExpression());
}

fn genConnectPipe(self: *h.NativeCodegen, _: []ast.Node) h.CodegenError!void {
    const b = try self.getBuilder();
    try b.emitValue(builder_mod.ZigValue.raw(".{}"), builder_mod.EmitConfig.forExpression());
}

fn genWsaConnect(self: *h.NativeCodegen, _: []ast.Node) h.CodegenError!void {
    const b = try self.getBuilder();
    try b.emitValue(builder_mod.ZigValue.raw(".{}"), builder_mod.EmitConfig.forExpression());
}

fn genInvalidHandleValue(self: *h.NativeCodegen, _: []ast.Node) h.CodegenError!void {
    const b = try self.getBuilder();
    try b.emitValue(builder_mod.ZigValue.int(-1), builder_mod.EmitConfig.forExpression());
}

fn genNull(self: *h.NativeCodegen, _: []ast.Node) h.CodegenError!void {
    const b = try self.getBuilder();
    try b.emitValue(builder_mod.ZigValue.int(0), builder_mod.EmitConfig.forExpression());
}

fn genErrorIoPending(self: *h.NativeCodegen, _: []ast.Node) h.CodegenError!void {
    const b = try self.getBuilder();
    try b.emitValue(builder_mod.ZigValue.int(997), builder_mod.EmitConfig.forExpression());
}

fn genErrorNetnameDeleted(self: *h.NativeCodegen, _: []ast.Node) h.CodegenError!void {
    const b = try self.getBuilder();
    try b.emitValue(builder_mod.ZigValue.int(64), builder_mod.EmitConfig.forExpression());
}

fn genErrorSemTimeout(self: *h.NativeCodegen, _: []ast.Node) h.CodegenError!void {
    const b = try self.getBuilder();
    try b.emitValue(builder_mod.ZigValue.int(121), builder_mod.EmitConfig.forExpression());
}

fn genErrorPipeBusy(self: *h.NativeCodegen, _: []ast.Node) h.CodegenError!void {
    const b = try self.getBuilder();
    try b.emitValue(builder_mod.ZigValue.int(231), builder_mod.EmitConfig.forExpression());
}

fn genInfinite(self: *h.NativeCodegen, _: []ast.Node) h.CodegenError!void {
    const b = try self.getBuilder();
    try b.emitValue(builder_mod.ZigValue.raw("0xFFFFFFFF"), builder_mod.EmitConfig.forExpression());
}

