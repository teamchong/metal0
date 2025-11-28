/// Python pwd module - Unix password database access
const std = @import("std");
const ast = @import("ast");
const CodegenError = @import("main.zig").CodegenError;
const NativeCodegen = @import("main.zig").NativeCodegen;

/// Generate pwd.getpwnam(name) - get user by username
/// Returns struct_passwd(pw_name, pw_passwd, pw_uid, pw_gid, pw_gecos, pw_dir, pw_shell)
pub fn genGetpwnam(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    _ = args;
    try self.emit(".{ .pw_name = \"\", .pw_passwd = \"x\", .pw_uid = @as(u32, 0), .pw_gid = @as(u32, 0), .pw_gecos = \"\", .pw_dir = \"/\", .pw_shell = \"/bin/sh\" }");
}

/// Generate pwd.getpwuid(uid) - get user by UID
/// Returns struct_passwd
pub fn genGetpwuid(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    _ = args;
    try self.emit(".{ .pw_name = \"\", .pw_passwd = \"x\", .pw_uid = @as(u32, 0), .pw_gid = @as(u32, 0), .pw_gecos = \"\", .pw_dir = \"/\", .pw_shell = \"/bin/sh\" }");
}

/// Generate pwd.getpwall() - get all password entries
/// Returns list of struct_passwd
pub fn genGetpwall(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    _ = args;
    try self.emit("&[_]@TypeOf(.{ .pw_name = \"\", .pw_passwd = \"\", .pw_uid = @as(u32, 0), .pw_gid = @as(u32, 0), .pw_gecos = \"\", .pw_dir = \"\", .pw_shell = \"\" }){}");
}

/// Generate pwd.struct_passwd - named tuple type for password entries
pub fn genStruct_passwd(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    _ = args;
    try self.emit("struct { pw_name: []const u8, pw_passwd: []const u8, pw_uid: u32, pw_gid: u32, pw_gecos: []const u8, pw_dir: []const u8, pw_shell: []const u8 }");
}
