/// Python reprlib module - Alternate repr() implementation
const std = @import("std");
const ast = @import("ast");
const CodegenError = @import("main.zig").CodegenError;
const NativeCodegen = @import("main.zig").NativeCodegen;

// ============================================================================
// Repr Class
// ============================================================================

/// Generate reprlib.Repr()
pub fn genRepr(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    _ = args;
    try self.emit(".{ .maxlevel = 6, .maxtuple = 6, .maxlist = 6, .maxarray = 5, .maxdict = 4, .maxset = 6, .maxfrozenset = 6, .maxdeque = 6, .maxstring = 30, .maxlong = 40, .maxother = 30, .fillvalue = \"...\" }");
}

/// Generate reprlib.repr(obj)
pub fn genReprFunc(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    if (args.len > 0) {
        try self.emit("blk: { const obj = ");
        try self.genExpr(args[0]);
        try self.emit("; break :blk std.fmt.allocPrint(pyaot_allocator, \"{any}\", .{obj}) catch \"<repr error>\"; }");
    } else {
        try self.emit("\"\"");
    }
}

/// Generate reprlib.recursive_repr(fillvalue='...')
pub fn genRecursive_repr(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    _ = args;
    // Returns a decorator
    try self.emit("@as(?*const fn(anytype) anytype, null)");
}

// ============================================================================
// Repr Methods (for method call support)
// ============================================================================

pub fn genRepr_repr(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    return genReprFunc(self, args);
}

pub fn genRepr_repr1(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    return genReprFunc(self, args);
}

pub fn genRepr_repr_str(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    if (args.len > 0) {
        try self.emit("blk: { const s = ");
        try self.genExpr(args[0]);
        try self.emit("; if (s.len > 30) { break :blk std.fmt.allocPrint(pyaot_allocator, \"'{s}...'\", .{s[0..27]}) catch \"'...'\"; } break :blk std.fmt.allocPrint(pyaot_allocator, \"'{s}'\", .{s}) catch \"'...'\"; }");
    } else {
        try self.emit("\"''\"");
    }
}

pub fn genRepr_repr_int(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    if (args.len > 0) {
        try self.emit("blk: { const n = ");
        try self.genExpr(args[0]);
        try self.emit("; break :blk std.fmt.allocPrint(pyaot_allocator, \"{d}\", .{n}) catch \"...\"; }");
    } else {
        try self.emit("\"0\"");
    }
}

pub fn genRepr_repr_tuple(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    _ = args;
    try self.emit("\"(...)\"");
}

pub fn genRepr_repr_list(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    _ = args;
    try self.emit("\"[...]\"");
}

pub fn genRepr_repr_dict(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    _ = args;
    try self.emit("\"{...}\"");
}

pub fn genRepr_repr_set(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    _ = args;
    try self.emit("\"{...}\"");
}
