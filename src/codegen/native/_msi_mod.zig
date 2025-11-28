/// Python _msi module - Windows MSI database access
const std = @import("std");
const ast = @import("ast");
const CodegenError = @import("main.zig").CodegenError;
const NativeCodegen = @import("main.zig").NativeCodegen;

/// Generate _msi.OpenDatabase(path, persist) - Open MSI database
pub fn genOpenDatabase(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    _ = args;
    try self.emit(".{}");
}

/// Generate _msi.CreateRecord(count) - Create MSI record
pub fn genCreateRecord(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    _ = args;
    try self.emit(".{}");
}

/// Generate _msi.UuidCreate() - Create UUID
pub fn genUuidCreate(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    _ = args;
    try self.emit("\"00000000-0000-0000-0000-000000000000\"");
}

/// Generate _msi.FCICreate(cab_name, files) - Create cabinet
pub fn genFCICreate(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    _ = args;
    try self.emit("{}");
}

/// Generate _msi.MSIDBOPEN_READONLY constant
pub fn genMSIDBOPEN_READONLY(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    _ = args;
    try self.emit("0");
}

/// Generate _msi.MSIDBOPEN_TRANSACT constant
pub fn genMSIDBOPEN_TRANSACT(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    _ = args;
    try self.emit("1");
}

/// Generate _msi.MSIDBOPEN_CREATE constant
pub fn genMSIDBOPEN_CREATE(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    _ = args;
    try self.emit("3");
}

/// Generate _msi.MSIDBOPEN_CREATEDIRECT constant
pub fn genMSIDBOPEN_CREATEDIRECT(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    _ = args;
    try self.emit("4");
}

/// Generate _msi.MSIDBOPEN_DIRECT constant
pub fn genMSIDBOPEN_DIRECT(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    _ = args;
    try self.emit("2");
}

/// Generate _msi.PID_CODEPAGE constant
pub fn genPID_CODEPAGE(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    _ = args;
    try self.emit("1");
}

/// Generate _msi.PID_TITLE constant
pub fn genPID_TITLE(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    _ = args;
    try self.emit("2");
}

/// Generate _msi.PID_SUBJECT constant
pub fn genPID_SUBJECT(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    _ = args;
    try self.emit("3");
}

/// Generate _msi.PID_AUTHOR constant
pub fn genPID_AUTHOR(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    _ = args;
    try self.emit("4");
}

/// Generate _msi.PID_KEYWORDS constant
pub fn genPID_KEYWORDS(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    _ = args;
    try self.emit("5");
}

/// Generate _msi.PID_COMMENTS constant
pub fn genPID_COMMENTS(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    _ = args;
    try self.emit("6");
}

/// Generate _msi.PID_TEMPLATE constant
pub fn genPID_TEMPLATE(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    _ = args;
    try self.emit("7");
}

/// Generate _msi.PID_REVNUMBER constant
pub fn genPID_REVNUMBER(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    _ = args;
    try self.emit("9");
}

/// Generate _msi.PID_PAGECOUNT constant
pub fn genPID_PAGECOUNT(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    _ = args;
    try self.emit("14");
}

/// Generate _msi.PID_WORDCOUNT constant
pub fn genPID_WORDCOUNT(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    _ = args;
    try self.emit("15");
}

/// Generate _msi.PID_APPNAME constant
pub fn genPID_APPNAME(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    _ = args;
    try self.emit("18");
}

/// Generate _msi.PID_SECURITY constant
pub fn genPID_SECURITY(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    _ = args;
    try self.emit("19");
}
