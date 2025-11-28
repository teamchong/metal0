/// Python mailbox module - Mailbox handling
const std = @import("std");
const ast = @import("ast");
const CodegenError = @import("main.zig").CodegenError;
const NativeCodegen = @import("main.zig").NativeCodegen;

/// Generate mailbox.Mailbox class (base class)
pub fn genMailbox(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    if (args.len > 0) {
        try self.emit("blk: { const path = ");
        try self.genExpr(args[0]);
        try self.emit("; break :blk .{ .path = path, .factory = @as(?*anyopaque, null), .create = true }; }");
    } else {
        try self.emit(".{ .path = \"\", .factory = @as(?*anyopaque, null), .create = true }");
    }
}

/// Generate mailbox.Maildir class
pub fn genMaildir(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    if (args.len > 0) {
        try self.emit("blk: { const path = ");
        try self.genExpr(args[0]);
        try self.emit("; break :blk .{ .path = path, .factory = @as(?*anyopaque, null), .create = true }; }");
    } else {
        try self.emit(".{ .path = \"\", .factory = @as(?*anyopaque, null), .create = true }");
    }
}

/// Generate mailbox.mbox class
pub fn genMbox(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    if (args.len > 0) {
        try self.emit("blk: { const path = ");
        try self.genExpr(args[0]);
        try self.emit("; break :blk .{ .path = path, .factory = @as(?*anyopaque, null), .create = true }; }");
    } else {
        try self.emit(".{ .path = \"\", .factory = @as(?*anyopaque, null), .create = true }");
    }
}

/// Generate mailbox.MH class
pub fn genMH(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    if (args.len > 0) {
        try self.emit("blk: { const path = ");
        try self.genExpr(args[0]);
        try self.emit("; break :blk .{ .path = path, .factory = @as(?*anyopaque, null), .create = true }; }");
    } else {
        try self.emit(".{ .path = \"\", .factory = @as(?*anyopaque, null), .create = true }");
    }
}

/// Generate mailbox.Babyl class
pub fn genBabyl(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    if (args.len > 0) {
        try self.emit("blk: { const path = ");
        try self.genExpr(args[0]);
        try self.emit("; break :blk .{ .path = path, .factory = @as(?*anyopaque, null), .create = true }; }");
    } else {
        try self.emit(".{ .path = \"\", .factory = @as(?*anyopaque, null), .create = true }");
    }
}

/// Generate mailbox.MMDF class
pub fn genMMDF(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    if (args.len > 0) {
        try self.emit("blk: { const path = ");
        try self.genExpr(args[0]);
        try self.emit("; break :blk .{ .path = path, .factory = @as(?*anyopaque, null), .create = true }; }");
    } else {
        try self.emit(".{ .path = \"\", .factory = @as(?*anyopaque, null), .create = true }");
    }
}

// ============================================================================
// Message classes
// ============================================================================

/// Generate mailbox.Message class (base class)
pub fn genMessage(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    _ = args;
    try self.emit(".{}");
}

/// Generate mailbox.MaildirMessage class
pub fn genMaildirMessage(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    _ = args;
    try self.emit(".{ .subdir = \"new\", .info = \"\", .date = @as(f64, 0) }");
}

/// Generate mailbox.mboxMessage class
pub fn genMboxMessage(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    _ = args;
    try self.emit(".{ .from_ = \"\" }");
}

/// Generate mailbox.MHMessage class
pub fn genMHMessage(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    _ = args;
    try self.emit(".{ .sequences = &[_][]const u8{} }");
}

/// Generate mailbox.BabylMessage class
pub fn genBabylMessage(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    _ = args;
    try self.emit(".{ .labels = &[_][]const u8{} }");
}

/// Generate mailbox.MMDFMessage class
pub fn genMMDFMessage(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    _ = args;
    try self.emit(".{ .from_ = \"\" }");
}

// ============================================================================
// Exceptions
// ============================================================================

pub fn genError(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    _ = args;
    try self.emit("error.MailboxError");
}

pub fn genNoSuchMailboxError(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    _ = args;
    try self.emit("error.NoSuchMailboxError");
}

pub fn genNotEmptyError(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    _ = args;
    try self.emit("error.NotEmptyError");
}

pub fn genExternalClashError(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    _ = args;
    try self.emit("error.ExternalClashError");
}

pub fn genFormatError(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    _ = args;
    try self.emit("error.FormatError");
}
