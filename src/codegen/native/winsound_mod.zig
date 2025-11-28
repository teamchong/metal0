/// Python winsound module - Windows sound playing interface
const std = @import("std");
const ast = @import("ast");
const CodegenError = @import("main.zig").CodegenError;
const NativeCodegen = @import("main.zig").NativeCodegen;

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
