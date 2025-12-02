/// Python mailbox module - Mailbox handling
const std = @import("std");
const ast = @import("ast");
const h = @import("mod_helper.zig");
const CodegenError = h.CodegenError;
const NativeCodegen = h.NativeCodegen;

pub const Funcs = std.StaticStringMap(h.H).initComptime(.{
    .{ "Mailbox", genMailboxType }, .{ "Maildir", genMailboxType }, .{ "mbox", genMailboxType },
    .{ "MH", genMailboxType }, .{ "Babyl", genMailboxType }, .{ "MMDF", genMailboxType },
    .{ "Message", h.c(".{}") },
    .{ "MaildirMessage", h.c(".{ .subdir = \"new\", .info = \"\", .date = @as(f64, 0) }") },
    .{ "mboxMessage", h.c(".{ .from_ = \"\" }") }, .{ "MMDFMessage", h.c(".{ .from_ = \"\" }") },
    .{ "MHMessage", h.c(".{ .sequences = &[_][]const u8{} }") },
    .{ "BabylMessage", h.c(".{ .labels = &[_][]const u8{} }") },
    .{ "Error", h.err("MailboxError") }, .{ "NoSuchMailboxError", h.err("NoSuchMailboxError") },
    .{ "NotEmptyError", h.err("NotEmptyError") }, .{ "ExternalClashError", h.err("ExternalClashError") },
    .{ "FormatError", h.err("FormatError") },
});

fn genMailboxType(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    if (args.len > 0) { try self.emit("blk: { const path = "); try self.genExpr(args[0]); try self.emit("; break :blk .{ .path = path, .factory = @as(?*anyopaque, null), .create = true }; }"); } else { try self.emit(".{ .path = \"\", .factory = @as(?*anyopaque, null), .create = true }"); }
}
