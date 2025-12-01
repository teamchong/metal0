/// Python winsound module - Windows sound playing interface
const std = @import("std");
const ast = @import("ast");
const CodegenError = @import("main.zig").CodegenError;
const NativeCodegen = @import("main.zig").NativeCodegen;

const ModuleHandler = *const fn (*NativeCodegen, []ast.Node) CodegenError!void;
pub const Funcs = std.StaticStringMap(ModuleHandler).initComptime(.{
    .{ "beep", genBeep },
    .{ "play_sound", genPlaySound },
    .{ "message_beep", genMessageBeep },
    .{ "s_n_d__f_i_l_e_n_a_m_e", genSND_FILENAME },
    .{ "s_n_d__a_l_i_a_s", genSND_ALIAS },
    .{ "s_n_d__l_o_o_p", genSND_LOOP },
    .{ "s_n_d__m_e_m_o_r_y", genSND_MEMORY },
    .{ "s_n_d__p_u_r_g_e", genSND_PURGE },
    .{ "s_n_d__a_s_y_n_c", genSND_ASYNC },
    .{ "s_n_d__n_o_d_e_f_a_u_l_t", genSND_NODEFAULT },
    .{ "s_n_d__n_o_s_t_o_p", genSND_NOSTOP },
    .{ "s_n_d__n_o_w_a_i_t", genSND_NOWAIT },
    .{ "m_b__i_c_o_n_a_s_t_e_r_i_s_k", genMB_ICONASTERISK },
    .{ "m_b__i_c_o_n_e_x_c_l_a_m_a_t_i_o_n", genMB_ICONEXCLAMATION },
    .{ "m_b__i_c_o_n_h_a_n_d", genMB_ICONHAND },
    .{ "m_b__i_c_o_n_q_u_e_s_t_i_o_n", genMB_ICONQUESTION },
    .{ "m_b__o_k", genMB_OK },
});

/// Generate winsound.Beep(frequency, duration) - Beep speaker
pub fn genBeep(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    _ = args;
    try self.emit("{}");
}

/// Generate winsound.PlaySound(sound, flags) - Play sound
pub fn genPlaySound(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    _ = args;
    try self.emit("{}");
}

/// Generate winsound.MessageBeep(type) - Play Windows message sound
pub fn genMessageBeep(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    _ = args;
    try self.emit("{}");
}

// Sound flag constants

/// Generate winsound.SND_FILENAME constant - sound is a file name
pub fn genSND_FILENAME(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    _ = args;
    try self.emit("0x20000");
}

/// Generate winsound.SND_ALIAS constant - sound is a registry alias
pub fn genSND_ALIAS(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    _ = args;
    try self.emit("0x10000");
}

/// Generate winsound.SND_LOOP constant - loop the sound
pub fn genSND_LOOP(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    _ = args;
    try self.emit("0x0008");
}

/// Generate winsound.SND_MEMORY constant - sound is a memory image
pub fn genSND_MEMORY(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    _ = args;
    try self.emit("0x0004");
}

/// Generate winsound.SND_PURGE constant - purge non-static events
pub fn genSND_PURGE(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    _ = args;
    try self.emit("0x0040");
}

/// Generate winsound.SND_ASYNC constant - play asynchronously
pub fn genSND_ASYNC(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    _ = args;
    try self.emit("0x0001");
}

/// Generate winsound.SND_NODEFAULT constant - don't use default sound
pub fn genSND_NODEFAULT(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    _ = args;
    try self.emit("0x0002");
}

/// Generate winsound.SND_NOSTOP constant - don't stop currently playing sound
pub fn genSND_NOSTOP(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    _ = args;
    try self.emit("0x0010");
}

/// Generate winsound.SND_NOWAIT constant - don't wait if busy
pub fn genSND_NOWAIT(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    _ = args;
    try self.emit("0x2000");
}

// MessageBeep type constants

/// Generate winsound.MB_ICONASTERISK constant - asterisk sound
pub fn genMB_ICONASTERISK(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    _ = args;
    try self.emit("0x40");
}

/// Generate winsound.MB_ICONEXCLAMATION constant - exclamation sound
pub fn genMB_ICONEXCLAMATION(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    _ = args;
    try self.emit("0x30");
}

/// Generate winsound.MB_ICONHAND constant - hand/error sound
pub fn genMB_ICONHAND(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    _ = args;
    try self.emit("0x10");
}

/// Generate winsound.MB_ICONQUESTION constant - question sound
pub fn genMB_ICONQUESTION(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    _ = args;
    try self.emit("0x20");
}

/// Generate winsound.MB_OK constant - default beep
pub fn genMB_OK(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    _ = args;
    try self.emit("0x0");
}
