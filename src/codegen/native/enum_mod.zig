/// Python enum module - Enumerations
const std = @import("std");
const ast = @import("ast");
const CodegenError = @import("main.zig").CodegenError;
const NativeCodegen = @import("main.zig").NativeCodegen;

/// Generate enum.Enum base class
pub fn genEnum(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    _ = args;
    try self.emit("struct {\n");
    self.indent();
    try self.emitIndent();
    try self.emit("name: []const u8,\n");
    try self.emitIndent();
    try self.emit("value: i64,\n");
    try self.emitIndent();
    try self.emit("pub fn __str__(self: @This()) []const u8 { return self.name; }\n");
    try self.emitIndent();
    try self.emit("pub fn __repr__(self: @This()) []const u8 { return self.name; }\n");
    self.dedent();
    try self.emitIndent();
    try self.emit("}{ .name = \"\", .value = 0 }");
}

/// Generate enum.IntEnum base class
pub fn genIntEnum(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    try genEnum(self, args);
}

/// Generate enum.StrEnum base class
pub fn genStrEnum(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    _ = args;
    try self.emit("struct {\n");
    self.indent();
    try self.emitIndent();
    try self.emit("name: []const u8,\n");
    try self.emitIndent();
    try self.emit("value: []const u8,\n");
    try self.emitIndent();
    try self.emit("pub fn __str__(self: @This()) []const u8 { return self.value; }\n");
    try self.emitIndent();
    try self.emit("pub fn __repr__(self: @This()) []const u8 { return self.name; }\n");
    self.dedent();
    try self.emitIndent();
    try self.emit("}{ .name = \"\", .value = \"\" }");
}

/// Generate enum.Flag base class
pub fn genFlag(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    _ = args;
    try self.emit("struct {\n");
    self.indent();
    try self.emitIndent();
    try self.emit("name: []const u8,\n");
    try self.emitIndent();
    try self.emit("value: i64,\n");
    try self.emitIndent();
    try self.emit("pub fn __or__(self: @This(), other: @This()) @This() { return @This(){ .name = self.name, .value = self.value | other.value }; }\n");
    try self.emitIndent();
    try self.emit("pub fn __and__(self: @This(), other: @This()) @This() { return @This(){ .name = self.name, .value = self.value & other.value }; }\n");
    try self.emitIndent();
    try self.emit("pub fn __xor__(self: @This(), other: @This()) @This() { return @This(){ .name = self.name, .value = self.value ^ other.value }; }\n");
    try self.emitIndent();
    try self.emit("pub fn __invert__(self: @This()) @This() { return @This(){ .name = self.name, .value = ~self.value }; }\n");
    self.dedent();
    try self.emitIndent();
    try self.emit("}{ .name = \"\", .value = 0 }");
}

/// Generate enum.IntFlag base class
pub fn genIntFlag(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    try genFlag(self, args);
}

/// Generate enum.auto() for automatic values
pub fn genAuto(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    _ = args;
    try self.emit("@as(i64, 0)"); // Simplified - would need state for proper auto
}

/// Generate enum.unique decorator
pub fn genUnique(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    // Decorator returns class as-is
    if (args.len > 0) {
        try self.genExpr(args[0]);
    } else {
        try self.emit("struct {}{}");
    }
}

/// Generate enum.verify decorator (Python 3.11+)
pub fn genVerify(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    // Decorator returns class as-is
    if (args.len > 0) {
        try self.genExpr(args[0]);
    } else {
        try self.emit("struct {}{}");
    }
}

/// Generate enum.member decorator (Python 3.11+)
pub fn genMember(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    if (args.len > 0) {
        try self.genExpr(args[0]);
    } else {
        try self.emit("struct {}{}");
    }
}

/// Generate enum.nonmember decorator (Python 3.11+)
pub fn genNonmember(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    if (args.len > 0) {
        try self.genExpr(args[0]);
    } else {
        try self.emit("struct {}{}");
    }
}

/// Generate enum.global_enum decorator (Python 3.11+)
pub fn genGlobalEnum(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    if (args.len > 0) {
        try self.genExpr(args[0]);
    } else {
        try self.emit("struct {}{}");
    }
}

/// Generate enum.EJECT constant
pub fn genEJECT(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    _ = args;
    try self.emit("@as(i64, 1)");
}

/// Generate enum.KEEP constant
pub fn genKEEP(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    _ = args;
    try self.emit("@as(i64, 2)");
}

/// Generate enum.STRICT constant
pub fn genSTRICT(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    _ = args;
    try self.emit("@as(i64, 3)");
}

/// Generate enum.CONFORM constant
pub fn genCONFORM(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    _ = args;
    try self.emit("@as(i64, 4)");
}

/// Generate enum.CONTINUOUS constant
pub fn genCONTINUOUS(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    _ = args;
    try self.emit("@as(i64, 5)");
}

/// Generate enum.NAMED_FLAGS constant
pub fn genNAMED_FLAGS(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    _ = args;
    try self.emit("@as(i64, 6)");
}

/// Generate enum.EnumType metaclass
pub fn genEnumType(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    _ = args;
    try self.emit("\"EnumType\"");
}

/// Generate enum.EnumCheck for verify
pub fn genEnumCheck(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    _ = args;
    try self.emit("struct {}{}");
}

/// Generate enum.FlagBoundary
pub fn genFlagBoundary(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    try genEnum(self, args);
}

/// Generate enum.property decorator
pub fn genProperty(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    if (args.len > 0) {
        try self.genExpr(args[0]);
    } else {
        try self.emit("struct { fget: ?*anyopaque = null }{}");
    }
}
