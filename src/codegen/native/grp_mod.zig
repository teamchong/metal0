/// Python grp module - Unix group database access
const std = @import("std");
const ast = @import("ast");
const CodegenError = @import("main.zig").CodegenError;
const NativeCodegen = @import("main.zig").NativeCodegen;

/// Generate grp.getgrnam(name) - get group by name
/// Returns struct_group(gr_name, gr_passwd, gr_gid, gr_mem)
pub fn genGetgrnam(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    _ = args;
    try self.emit(".{ .gr_name = \"\", .gr_passwd = \"x\", .gr_gid = @as(u32, 0), .gr_mem = &[_][]const u8{} }");
}

/// Generate grp.getgrgid(gid) - get group by GID
/// Returns struct_group(gr_name, gr_passwd, gr_gid, gr_mem)
pub fn genGetgrgid(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    _ = args;
    try self.emit(".{ .gr_name = \"\", .gr_passwd = \"x\", .gr_gid = @as(u32, 0), .gr_mem = &[_][]const u8{} }");
}

/// Generate grp.getgrall() - get all group entries
/// Returns list of struct_group
pub fn genGetgrall(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    _ = args;
    try self.emit("&[_]@TypeOf(.{ .gr_name = \"\", .gr_passwd = \"\", .gr_gid = @as(u32, 0), .gr_mem = &[_][]const u8{} }){}");
}

/// Generate grp.struct_group - named tuple type for group entries
pub fn genStruct_group(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    _ = args;
    try self.emit("struct { gr_name: []const u8, gr_passwd: []const u8, gr_gid: u32, gr_mem: []const []const u8 }");
}
