/// Python stringprep module - Internet string preparation (RFC 3454)
const std = @import("std");
const ast = @import("ast");

const ModuleHandler = *const fn (*NativeCodegen, []ast.Node) CodegenError!void;
pub const Funcs = std.StaticStringMap(ModuleHandler).initComptime(.{
    .{ "in_table_a1", genInTableA1 },
    .{ "in_table_b1", genInTableB1 },
    .{ "map_table_b2", genMapTableB2 },
    .{ "map_table_b3", genMapTableB3 },
    .{ "in_table_c11", genInTableC11 },
    .{ "in_table_c12", genInTableC12 },
    .{ "in_table_c11_c12", genInTableC11C12 },
    .{ "in_table_c21", genInTableC21 },
    .{ "in_table_c22", genInTableC22 },
    .{ "in_table_c21_c22", genInTableC21C22 },
    .{ "in_table_c3", genInTableC3 },
    .{ "in_table_c4", genInTableC4 },
    .{ "in_table_c5", genInTableC5 },
    .{ "in_table_c6", genInTableC6 },
    .{ "in_table_c7", genInTableC7 },
    .{ "in_table_c8", genInTableC8 },
    .{ "in_table_c9", genInTableC9 },
    .{ "in_table_d1", genInTableD1 },
    .{ "in_table_d2", genInTableD2 },
});
const CodegenError = @import("main.zig").CodegenError;
const NativeCodegen = @import("main.zig").NativeCodegen;

/// Generate stringprep.in_table_a1(code)
pub fn genInTableA1(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    _ = args;
    try self.emit("false");
}

/// Generate stringprep.in_table_b1(code)
pub fn genInTableB1(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    _ = args;
    try self.emit("false");
}

/// Generate stringprep.map_table_b2(code)
pub fn genMapTableB2(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    if (args.len > 0) {
        try self.genExpr(args[0]);
    } else {
        try self.emit("\"\"");
    }
}

/// Generate stringprep.map_table_b3(code)
pub fn genMapTableB3(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    if (args.len > 0) {
        try self.genExpr(args[0]);
    } else {
        try self.emit("\"\"");
    }
}

/// Generate stringprep.in_table_c11(code)
pub fn genInTableC11(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    _ = args;
    try self.emit("false");
}

/// Generate stringprep.in_table_c12(code)
pub fn genInTableC12(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    _ = args;
    try self.emit("false");
}

/// Generate stringprep.in_table_c11_c12(code)
pub fn genInTableC11C12(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    _ = args;
    try self.emit("false");
}

/// Generate stringprep.in_table_c21(code)
pub fn genInTableC21(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    _ = args;
    try self.emit("false");
}

/// Generate stringprep.in_table_c22(code)
pub fn genInTableC22(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    _ = args;
    try self.emit("false");
}

/// Generate stringprep.in_table_c21_c22(code)
pub fn genInTableC21C22(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    _ = args;
    try self.emit("false");
}

/// Generate stringprep.in_table_c3(code)
pub fn genInTableC3(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    _ = args;
    try self.emit("false");
}

/// Generate stringprep.in_table_c4(code)
pub fn genInTableC4(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    _ = args;
    try self.emit("false");
}

/// Generate stringprep.in_table_c5(code)
pub fn genInTableC5(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    _ = args;
    try self.emit("false");
}

/// Generate stringprep.in_table_c6(code)
pub fn genInTableC6(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    _ = args;
    try self.emit("false");
}

/// Generate stringprep.in_table_c7(code)
pub fn genInTableC7(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    _ = args;
    try self.emit("false");
}

/// Generate stringprep.in_table_c8(code)
pub fn genInTableC8(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    _ = args;
    try self.emit("false");
}

/// Generate stringprep.in_table_c9(code)
pub fn genInTableC9(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    _ = args;
    try self.emit("false");
}

/// Generate stringprep.in_table_d1(code)
pub fn genInTableD1(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    _ = args;
    try self.emit("false");
}

/// Generate stringprep.in_table_d2(code)
pub fn genInTableD2(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    _ = args;
    try self.emit("false");
}
