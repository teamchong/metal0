/// Python mailbox module - Mailbox handling
const std = @import("std");
const ast = @import("ast");
const CodegenError = @import("main.zig").CodegenError;
const NativeCodegen = @import("main.zig").NativeCodegen;

const ModuleHandler = *const fn (*NativeCodegen, []ast.Node) CodegenError!void;
fn genConst(comptime v: []const u8) ModuleHandler {
    return struct { fn f(self: *NativeCodegen, args: []ast.Node) CodegenError!void { _ = args; try self.emit(v); } }.f;
}

pub const Funcs = std.StaticStringMap(ModuleHandler).initComptime(.{
    .{ "Mailbox", genMailboxType }, .{ "Maildir", genMailboxType }, .{ "mbox", genMailboxType },
    .{ "MH", genMailboxType }, .{ "Babyl", genMailboxType }, .{ "MMDF", genMailboxType },
    .{ "Message", genConst(".{}") },
    .{ "MaildirMessage", genConst(".{ .subdir = \"new\", .info = \"\", .date = @as(f64, 0) }") },
    .{ "mboxMessage", genConst(".{ .from_ = \"\" }") }, .{ "MMDFMessage", genConst(".{ .from_ = \"\" }") },
    .{ "MHMessage", genConst(".{ .sequences = &[_][]const u8{} }") },
    .{ "BabylMessage", genConst(".{ .labels = &[_][]const u8{} }") },
    .{ "Error", genConst("error.MailboxError") }, .{ "NoSuchMailboxError", genConst("error.NoSuchMailboxError") },
    .{ "NotEmptyError", genConst("error.NotEmptyError") }, .{ "ExternalClashError", genConst("error.ExternalClashError") },
    .{ "FormatError", genConst("error.FormatError") },
});

fn genMailboxType(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    if (args.len > 0) { try self.emit("blk: { const path = "); try self.genExpr(args[0]); try self.emit("; break :blk .{ .path = path, .factory = @as(?*anyopaque, null), .create = true }; }"); } else { try self.emit(".{ .path = \"\", .factory = @as(?*anyopaque, null), .create = true }"); }
}
