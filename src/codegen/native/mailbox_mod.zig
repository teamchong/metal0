/// Python mailbox module - Mailbox handling
const std = @import("std");
const ast = @import("ast");
const CodegenError = @import("main.zig").CodegenError;
const NativeCodegen = @import("main.zig").NativeCodegen;

const ModuleHandler = *const fn (*NativeCodegen, []ast.Node) CodegenError!void;
fn genConst(self: *NativeCodegen, args: []ast.Node, v: []const u8) CodegenError!void { _ = args; try self.emit(v); }
fn genEmpty(self: *NativeCodegen, args: []ast.Node) CodegenError!void { try genConst(self, args, ".{}"); }
fn genMaildirMsg(self: *NativeCodegen, args: []ast.Node) CodegenError!void { try genConst(self, args, ".{ .subdir = \"new\", .info = \"\", .date = @as(f64, 0) }"); }
fn genMboxMsg(self: *NativeCodegen, args: []ast.Node) CodegenError!void { try genConst(self, args, ".{ .from_ = \"\" }"); }
fn genMHMsg(self: *NativeCodegen, args: []ast.Node) CodegenError!void { try genConst(self, args, ".{ .sequences = &[_][]const u8{} }"); }
fn genBabylMsg(self: *NativeCodegen, args: []ast.Node) CodegenError!void { try genConst(self, args, ".{ .labels = &[_][]const u8{} }"); }
fn genErr(self: *NativeCodegen, args: []ast.Node) CodegenError!void { try genConst(self, args, "error.MailboxError"); }
fn genNoSuchErr(self: *NativeCodegen, args: []ast.Node) CodegenError!void { try genConst(self, args, "error.NoSuchMailboxError"); }
fn genNotEmptyErr(self: *NativeCodegen, args: []ast.Node) CodegenError!void { try genConst(self, args, "error.NotEmptyError"); }
fn genClashErr(self: *NativeCodegen, args: []ast.Node) CodegenError!void { try genConst(self, args, "error.ExternalClashError"); }
fn genFmtErr(self: *NativeCodegen, args: []ast.Node) CodegenError!void { try genConst(self, args, "error.FormatError"); }

pub const Funcs = std.StaticStringMap(ModuleHandler).initComptime(.{
    .{ "Mailbox", genMailboxType }, .{ "Maildir", genMailboxType }, .{ "mbox", genMailboxType },
    .{ "MH", genMailboxType }, .{ "Babyl", genMailboxType }, .{ "MMDF", genMailboxType },
    .{ "Message", genEmpty }, .{ "MaildirMessage", genMaildirMsg }, .{ "mboxMessage", genMboxMsg },
    .{ "MHMessage", genMHMsg }, .{ "BabylMessage", genBabylMsg }, .{ "MMDFMessage", genMboxMsg },
    .{ "Error", genErr }, .{ "NoSuchMailboxError", genNoSuchErr }, .{ "NotEmptyError", genNotEmptyErr },
    .{ "ExternalClashError", genClashErr }, .{ "FormatError", genFmtErr },
});

fn genMailboxType(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    if (args.len > 0) { try self.emit("blk: { const path = "); try self.genExpr(args[0]); try self.emit("; break :blk .{ .path = path, .factory = @as(?*anyopaque, null), .create = true }; }"); } else { try self.emit(".{ .path = \"\", .factory = @as(?*anyopaque, null), .create = true }"); }
}
