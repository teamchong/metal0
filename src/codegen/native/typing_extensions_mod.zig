/// Python typing_extensions module - Backports of typing features
const std = @import("std");
const ast = @import("ast");
const CodegenError = @import("main.zig").CodegenError;
const NativeCodegen = @import("main.zig").NativeCodegen;

// All typing_extensions types compile to type annotations (erased at runtime)
// These generate placeholder values for AOT compilation

/// Generate typing_extensions.Annotated
pub fn genAnnotated(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    _ = args;
    try self.emit("@TypeOf(undefined)");
}

/// Generate typing_extensions.ParamSpec
pub fn genParamSpec(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    _ = args;
    try self.emit("@TypeOf(undefined)");
}

/// Generate typing_extensions.ParamSpecArgs
pub fn genParamSpecArgs(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    _ = args;
    try self.emit("@TypeOf(undefined)");
}

/// Generate typing_extensions.ParamSpecKwargs
pub fn genParamSpecKwargs(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    _ = args;
    try self.emit("@TypeOf(undefined)");
}

/// Generate typing_extensions.Concatenate
pub fn genConcatenate(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    _ = args;
    try self.emit("@TypeOf(undefined)");
}

/// Generate typing_extensions.TypeAlias
pub fn genTypeAlias(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    _ = args;
    try self.emit("@TypeOf(undefined)");
}

/// Generate typing_extensions.TypeGuard
pub fn genTypeGuard(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    _ = args;
    try self.emit("@TypeOf(undefined)");
}

/// Generate typing_extensions.TypeIs
pub fn genTypeIs(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    _ = args;
    try self.emit("@TypeOf(undefined)");
}

/// Generate typing_extensions.Self
pub fn genSelf(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    _ = args;
    try self.emit("@TypeOf(undefined)");
}

/// Generate typing_extensions.Never
pub fn genNever(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    _ = args;
    try self.emit("noreturn");
}

/// Generate typing_extensions.Required
pub fn genRequired(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    _ = args;
    try self.emit("@TypeOf(undefined)");
}

/// Generate typing_extensions.NotRequired
pub fn genNotRequired(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    _ = args;
    try self.emit("@TypeOf(undefined)");
}

/// Generate typing_extensions.LiteralString
pub fn genLiteralString(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    _ = args;
    try self.emit("[]const u8");
}

/// Generate typing_extensions.Unpack
pub fn genUnpack(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    _ = args;
    try self.emit("@TypeOf(undefined)");
}

/// Generate typing_extensions.TypeVarTuple
pub fn genTypeVarTuple(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    _ = args;
    try self.emit("@TypeOf(undefined)");
}

/// Generate typing_extensions.override decorator
pub fn genOverride(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    if (args.len > 0) {
        try self.genExpr(args[0]);
    } else {
        try self.emit("@as(?*anyopaque, null)");
    }
}

/// Generate typing_extensions.final decorator
pub fn genFinal(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    if (args.len > 0) {
        try self.genExpr(args[0]);
    } else {
        try self.emit("@as(?*anyopaque, null)");
    }
}

/// Generate typing_extensions.deprecated decorator
pub fn genDeprecated(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    if (args.len > 0) {
        try self.genExpr(args[0]);
    } else {
        try self.emit("@as(?*anyopaque, null)");
    }
}

/// Generate typing_extensions.dataclass_transform decorator
pub fn genDataclass_transform(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    if (args.len > 0) {
        try self.genExpr(args[0]);
    } else {
        try self.emit("@as(?*anyopaque, null)");
    }
}

/// Generate typing_extensions.runtime_checkable decorator
pub fn genRuntime_checkable(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    if (args.len > 0) {
        try self.genExpr(args[0]);
    } else {
        try self.emit("@as(?*anyopaque, null)");
    }
}

/// Generate typing_extensions.Protocol
pub fn genProtocol(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    _ = args;
    try self.emit("@TypeOf(undefined)");
}

/// Generate typing_extensions.TypedDict
pub fn genTypedDict(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    _ = args;
    try self.emit(".{}");
}

/// Generate typing_extensions.NamedTuple
pub fn genNamedTuple(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    _ = args;
    try self.emit(".{}");
}

/// Generate typing_extensions.get_type_hints
pub fn genGet_type_hints(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    _ = args;
    try self.emit(".{}");
}

/// Generate typing_extensions.get_origin
pub fn genGet_origin(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    _ = args;
    try self.emit("@as(?@TypeOf(undefined), null)");
}

/// Generate typing_extensions.get_args
pub fn genGet_args(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    _ = args;
    try self.emit(".{}");
}

/// Generate typing_extensions.is_typeddict
pub fn genIs_typeddict(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    _ = args;
    try self.emit("false");
}

/// Generate typing_extensions.get_annotations
pub fn genGet_annotations(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    _ = args;
    try self.emit(".{}");
}

/// Generate typing_extensions.assert_type
pub fn genAssert_type(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    if (args.len > 0) {
        try self.genExpr(args[0]);
    } else {
        try self.emit("@as(?*anyopaque, null)");
    }
}

/// Generate typing_extensions.reveal_type
pub fn genReveal_type(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    if (args.len > 0) {
        try self.genExpr(args[0]);
    } else {
        try self.emit("@as(?*anyopaque, null)");
    }
}

/// Generate typing_extensions.assert_never
pub fn genAssert_never(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    _ = args;
    try self.emit("unreachable");
}

/// Generate typing_extensions.clear_overloads
pub fn genClear_overloads(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    _ = args;
    try self.emit("{}");
}

/// Generate typing_extensions.get_overloads
pub fn genGet_overloads(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    _ = args;
    try self.emit("&[_]*anyopaque{}");
}

/// Generate typing_extensions.Doc (PEP 727)
pub fn genDoc(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    _ = args;
    try self.emit("@TypeOf(undefined)");
}

/// Generate typing_extensions.ReadOnly
pub fn genReadOnly(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    _ = args;
    try self.emit("@TypeOf(undefined)");
}

// ============================================================================
// Re-exported from typing (for convenience)
// ============================================================================

pub fn genAny(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    _ = args;
    try self.emit("@TypeOf(undefined)");
}

pub fn genUnion(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    _ = args;
    try self.emit("@TypeOf(undefined)");
}

pub fn genOptional(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    _ = args;
    try self.emit("@TypeOf(undefined)");
}

pub fn genList(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    _ = args;
    try self.emit("@TypeOf(undefined)");
}

pub fn genDict(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    _ = args;
    try self.emit("@TypeOf(undefined)");
}

pub fn genSet(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    _ = args;
    try self.emit("@TypeOf(undefined)");
}

pub fn genTuple(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    _ = args;
    try self.emit("@TypeOf(undefined)");
}

pub fn genCallable(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    _ = args;
    try self.emit("@TypeOf(undefined)");
}

pub fn genType(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    _ = args;
    try self.emit("@TypeOf(undefined)");
}

pub fn genLiteral(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    _ = args;
    try self.emit("@TypeOf(undefined)");
}

pub fn genClassVar(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    _ = args;
    try self.emit("@TypeOf(undefined)");
}

pub fn genTypeVar(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    _ = args;
    try self.emit("@TypeOf(undefined)");
}

pub fn genGeneric(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    _ = args;
    try self.emit("@TypeOf(undefined)");
}

pub fn genNoReturn(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    _ = args;
    try self.emit("noreturn");
}

pub fn genCast(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    // cast(typ, val) returns val
    if (args.len >= 2) {
        try self.genExpr(args[1]);
    } else if (args.len == 1) {
        try self.genExpr(args[0]);
    } else {
        try self.emit("@as(?*anyopaque, null)");
    }
}

pub fn genOverload(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    if (args.len > 0) {
        try self.genExpr(args[0]);
    } else {
        try self.emit("@as(?*anyopaque, null)");
    }
}

pub fn genNo_type_check(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    if (args.len > 0) {
        try self.genExpr(args[0]);
    } else {
        try self.emit("@as(?*anyopaque, null)");
    }
}

pub fn genTYPE_CHECKING(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    _ = args;
    try self.emit("false"); // Always false at runtime
}
