/// Python ossaudiodev module - OSS audio device access
const std = @import("std");
const ast = @import("ast");
const CodegenError = @import("main.zig").CodegenError;
const NativeCodegen = @import("main.zig").NativeCodegen;

const ModuleHandler = *const fn (*NativeCodegen, []ast.Node) CodegenError!void;
pub const Funcs = std.StaticStringMap(ModuleHandler).initComptime(.{
    .{ "open", genOpen },
    .{ "openmixer", genOpenmixer },
    .{ "error", genError },
    .{ "a_f_m_t__u8", genAFMT_U8 },
    .{ "a_f_m_t__s16__l_e", genAFMT_S16_LE },
    .{ "a_f_m_t__s16__b_e", genAFMT_S16_BE },
    .{ "a_f_m_t__s16__n_e", genAFMT_S16_NE },
    .{ "a_f_m_t__a_c3", genAFMT_AC3 },
    .{ "a_f_m_t__q_u_e_r_y", genAFMT_QUERY },
    .{ "s_n_d_c_t_l__d_s_p__c_h_a_n_n_e_l_s", genSNDCTL_DSP_CHANNELS },
    .{ "s_n_d_c_t_l__d_s_p__g_e_t_f_m_t_s", genSNDCTL_DSP_GETFMTS },
    .{ "s_n_d_c_t_l__d_s_p__s_e_t_f_m_t", genSNDCTL_DSP_SETFMT },
    .{ "s_n_d_c_t_l__d_s_p__s_p_e_e_d", genSNDCTL_DSP_SPEED },
    .{ "s_n_d_c_t_l__d_s_p__s_t_e_r_e_o", genSNDCTL_DSP_STEREO },
    .{ "s_n_d_c_t_l__d_s_p__s_y_n_c", genSNDCTL_DSP_SYNC },
    .{ "s_n_d_c_t_l__d_s_p__r_e_s_e_t", genSNDCTL_DSP_RESET },
    .{ "s_n_d_c_t_l__d_s_p__g_e_t_o_s_p_a_c_e", genSNDCTL_DSP_GETOSPACE },
    .{ "s_n_d_c_t_l__d_s_p__g_e_t_i_s_p_a_c_e", genSNDCTL_DSP_GETISPACE },
    .{ "s_n_d_c_t_l__d_s_p__n_o_n_b_l_o_c_k", genSNDCTL_DSP_NONBLOCK },
    .{ "s_n_d_c_t_l__d_s_p__g_e_t_c_a_p_s", genSNDCTL_DSP_GETCAPS },
    .{ "s_n_d_c_t_l__d_s_p__s_e_t_f_r_a_g_m_e_n_t", genSNDCTL_DSP_SETFRAGMENT },
    .{ "s_o_u_n_d__m_i_x_e_r__n_r_d_e_v_i_c_e_s", genSOUND_MIXER_NRDEVICES },
    .{ "s_o_u_n_d__m_i_x_e_r__v_o_l_u_m_e", genSOUND_MIXER_VOLUME },
    .{ "s_o_u_n_d__m_i_x_e_r__b_a_s_s", genSOUND_MIXER_BASS },
    .{ "s_o_u_n_d__m_i_x_e_r__t_r_e_b_l_e", genSOUND_MIXER_TREBLE },
    .{ "s_o_u_n_d__m_i_x_e_r__p_c_m", genSOUND_MIXER_PCM },
    .{ "s_o_u_n_d__m_i_x_e_r__l_i_n_e", genSOUND_MIXER_LINE },
    .{ "s_o_u_n_d__m_i_x_e_r__m_i_c", genSOUND_MIXER_MIC },
    .{ "s_o_u_n_d__m_i_x_e_r__c_d", genSOUND_MIXER_CD },
    .{ "s_o_u_n_d__m_i_x_e_r__r_e_c", genSOUND_MIXER_REC },
});

/// Generate ossaudiodev.open(device, mode) - Open audio device
pub fn genOpen(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    _ = args;
    try self.emit(".{}");
}

/// Generate ossaudiodev.openmixer(device=None) - Open mixer device
pub fn genOpenmixer(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    _ = args;
    try self.emit(".{}");
}

/// Generate ossaudiodev.error exception
pub fn genError(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    _ = args;
    try self.emit("error.OSSAudioError");
}

/// Generate ossaudiodev.AFMT_U8 constant
pub fn genAFMT_U8(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    _ = args;
    try self.emit("0x08");
}

/// Generate ossaudiodev.AFMT_S16_LE constant
pub fn genAFMT_S16_LE(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    _ = args;
    try self.emit("0x10");
}

/// Generate ossaudiodev.AFMT_S16_BE constant
pub fn genAFMT_S16_BE(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    _ = args;
    try self.emit("0x20");
}

/// Generate ossaudiodev.AFMT_S16_NE constant
pub fn genAFMT_S16_NE(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    _ = args;
    try self.emit("0x10");
}

/// Generate ossaudiodev.AFMT_AC3 constant
pub fn genAFMT_AC3(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    _ = args;
    try self.emit("0x400");
}

/// Generate ossaudiodev.AFMT_QUERY constant
pub fn genAFMT_QUERY(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    _ = args;
    try self.emit("0");
}

/// Generate ossaudiodev.SNDCTL_DSP_CHANNELS constant
pub fn genSNDCTL_DSP_CHANNELS(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    _ = args;
    try self.emit("0xC0045006");
}

/// Generate ossaudiodev.SNDCTL_DSP_GETFMTS constant
pub fn genSNDCTL_DSP_GETFMTS(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    _ = args;
    try self.emit("0x8004500B");
}

/// Generate ossaudiodev.SNDCTL_DSP_SETFMT constant
pub fn genSNDCTL_DSP_SETFMT(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    _ = args;
    try self.emit("0xC0045005");
}

/// Generate ossaudiodev.SNDCTL_DSP_SPEED constant
pub fn genSNDCTL_DSP_SPEED(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    _ = args;
    try self.emit("0xC0045002");
}

/// Generate ossaudiodev.SNDCTL_DSP_STEREO constant
pub fn genSNDCTL_DSP_STEREO(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    _ = args;
    try self.emit("0xC0045003");
}

/// Generate ossaudiodev.SNDCTL_DSP_SYNC constant
pub fn genSNDCTL_DSP_SYNC(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    _ = args;
    try self.emit("0x5001");
}

/// Generate ossaudiodev.SNDCTL_DSP_RESET constant
pub fn genSNDCTL_DSP_RESET(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    _ = args;
    try self.emit("0x5000");
}

/// Generate ossaudiodev.SNDCTL_DSP_GETOSPACE constant
pub fn genSNDCTL_DSP_GETOSPACE(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    _ = args;
    try self.emit("0x8010500C");
}

/// Generate ossaudiodev.SNDCTL_DSP_GETISPACE constant
pub fn genSNDCTL_DSP_GETISPACE(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    _ = args;
    try self.emit("0x8010500D");
}

/// Generate ossaudiodev.SNDCTL_DSP_NONBLOCK constant
pub fn genSNDCTL_DSP_NONBLOCK(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    _ = args;
    try self.emit("0x500E");
}

/// Generate ossaudiodev.SNDCTL_DSP_GETCAPS constant
pub fn genSNDCTL_DSP_GETCAPS(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    _ = args;
    try self.emit("0x8004500F");
}

/// Generate ossaudiodev.SNDCTL_DSP_SETFRAGMENT constant
pub fn genSNDCTL_DSP_SETFRAGMENT(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    _ = args;
    try self.emit("0xC004500A");
}

/// Generate ossaudiodev.SOUND_MIXER_NRDEVICES constant
pub fn genSOUND_MIXER_NRDEVICES(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    _ = args;
    try self.emit("25");
}

/// Generate ossaudiodev.SOUND_MIXER_VOLUME constant
pub fn genSOUND_MIXER_VOLUME(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    _ = args;
    try self.emit("0");
}

/// Generate ossaudiodev.SOUND_MIXER_BASS constant
pub fn genSOUND_MIXER_BASS(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    _ = args;
    try self.emit("1");
}

/// Generate ossaudiodev.SOUND_MIXER_TREBLE constant
pub fn genSOUND_MIXER_TREBLE(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    _ = args;
    try self.emit("2");
}

/// Generate ossaudiodev.SOUND_MIXER_PCM constant
pub fn genSOUND_MIXER_PCM(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    _ = args;
    try self.emit("4");
}

/// Generate ossaudiodev.SOUND_MIXER_LINE constant
pub fn genSOUND_MIXER_LINE(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    _ = args;
    try self.emit("6");
}

/// Generate ossaudiodev.SOUND_MIXER_MIC constant
pub fn genSOUND_MIXER_MIC(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    _ = args;
    try self.emit("7");
}

/// Generate ossaudiodev.SOUND_MIXER_CD constant
pub fn genSOUND_MIXER_CD(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    _ = args;
    try self.emit("8");
}

/// Generate ossaudiodev.SOUND_MIXER_REC constant
pub fn genSOUND_MIXER_REC(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    _ = args;
    try self.emit("11");
}
