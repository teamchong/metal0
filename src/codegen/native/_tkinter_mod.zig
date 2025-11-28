/// Python _tkinter module - Tcl/Tk interface
const std = @import("std");
const ast = @import("ast");
const CodegenError = @import("main.zig").CodegenError;
const NativeCodegen = @import("main.zig").NativeCodegen;

/// Generate _tkinter.create(screenName, baseName, className, interactive, wantobjects, wantTk, sync, use) - Create Tk app
pub fn genCreate(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    _ = args;
    try self.emit(".{}");
}

/// Generate _tkinter.setbusywaitinterval(ms) - Set busy wait interval
pub fn genSetbusywaitinterval(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    _ = args;
    try self.emit("{}");
}

/// Generate _tkinter.getbusywaitinterval() - Get busy wait interval
pub fn genGetbusywaitinterval(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    _ = args;
    try self.emit("20");
}

/// Generate _tkinter.TclError exception
pub fn genTclError(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    _ = args;
    try self.emit("error.TclError");
}

/// Generate _tkinter.TK_VERSION constant
pub fn genTK_VERSION(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    _ = args;
    try self.emit("\"8.6\"");
}

/// Generate _tkinter.TCL_VERSION constant
pub fn genTCL_VERSION(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    _ = args;
    try self.emit("\"8.6\"");
}

/// Generate _tkinter.READABLE constant
pub fn genREADABLE(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    _ = args;
    try self.emit("2");
}

/// Generate _tkinter.WRITABLE constant
pub fn genWRITABLE(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    _ = args;
    try self.emit("4");
}

/// Generate _tkinter.EXCEPTION constant
pub fn genEXCEPTION(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    _ = args;
    try self.emit("8");
}

/// Generate _tkinter.DONT_WAIT constant
pub fn genDONT_WAIT(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    _ = args;
    try self.emit("2");
}

/// Generate _tkinter.WINDOW_EVENTS constant
pub fn genWINDOW_EVENTS(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    _ = args;
    try self.emit("4");
}

/// Generate _tkinter.FILE_EVENTS constant
pub fn genFILE_EVENTS(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    _ = args;
    try self.emit("8");
}

/// Generate _tkinter.TIMER_EVENTS constant
pub fn genTIMER_EVENTS(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    _ = args;
    try self.emit("16");
}

/// Generate _tkinter.IDLE_EVENTS constant
pub fn genIDLE_EVENTS(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    _ = args;
    try self.emit("32");
}

/// Generate _tkinter.ALL_EVENTS constant
pub fn genALL_EVENTS(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    _ = args;
    try self.emit("-3");
}
