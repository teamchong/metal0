/// Python ossaudiodev module - OSS audio device access
const std = @import("std");
const ast = @import("ast");
const CodegenError = @import("main.zig").CodegenError;
const NativeCodegen = @import("main.zig").NativeCodegen;

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
