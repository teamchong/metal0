/// Python typing_extensions module - Backports of typing features
const std = @import("std");
const ast = @import("ast");
const CodegenError = @import("main.zig").CodegenError;
const NativeCodegen = @import("main.zig").NativeCodegen;

const ModuleHandler = *const fn (*NativeCodegen, []ast.Node) CodegenError!void;
pub const Funcs = std.StaticStringMap(ModuleHandler).initComptime(.{
    .{ "Annotated", genType }, .{ "ParamSpec", genType }, .{ "ParamSpecArgs", genType }, .{ "ParamSpecKwargs", genType },
    .{ "Concatenate", genType }, .{ "TypeAlias", genType }, .{ "TypeGuard", genType }, .{ "TypeIs", genType },
    .{ "Self", genType }, .{ "Never", genNever }, .{ "Required", genType }, .{ "NotRequired", genType },
    .{ "LiteralString", genLiteralString }, .{ "Unpack", genType }, .{ "TypeVarTuple", genType },
    .{ "override", genPassthrough }, .{ "final", genPassthrough }, .{ "deprecated", genPassthrough },
    .{ "dataclass_transform", genPassthrough }, .{ "runtime_checkable", genPassthrough },
    .{ "Protocol", genType }, .{ "TypedDict", genEmpty }, .{ "NamedTuple", genEmpty },
    .{ "get_type_hints", genEmpty }, .{ "get_origin", genNullType }, .{ "get_args", genEmpty },
    .{ "is_typeddict", genFalse }, .{ "get_annotations", genEmpty },
    .{ "assert_type", genPassthrough }, .{ "reveal_type", genPassthrough },
    .{ "assert_never", genUnreachable }, .{ "clear_overloads", genUnit }, .{ "get_overloads", genEmptySlice },
    .{ "Doc", genType }, .{ "ReadOnly", genType }, .{ "Any", genType }, .{ "Union", genType },
    .{ "Optional", genType }, .{ "List", genType }, .{ "Dict", genType }, .{ "Set", genType },
    .{ "Tuple", genType }, .{ "Callable", genType }, .{ "Type", genType }, .{ "Literal", genType },
    .{ "ClassVar", genType }, .{ "TypeVar", genType }, .{ "Generic", genType }, .{ "NoReturn", genNever },
    .{ "cast", genCast }, .{ "overload", genPassthrough }, .{ "no_type_check", genPassthrough },
    .{ "TYPE_CHECKING", genFalse },
});

// Helper
fn genConst(self: *NativeCodegen, args: []ast.Node, value: []const u8) CodegenError!void { _ = args; try self.emit(value); }

// Type placeholder
fn genType(self: *NativeCodegen, args: []ast.Node) CodegenError!void { try genConst(self, args, "@TypeOf(undefined)"); }
fn genNever(self: *NativeCodegen, args: []ast.Node) CodegenError!void { try genConst(self, args, "noreturn"); }
fn genLiteralString(self: *NativeCodegen, args: []ast.Node) CodegenError!void { try genConst(self, args, "[]const u8"); }
fn genEmpty(self: *NativeCodegen, args: []ast.Node) CodegenError!void { try genConst(self, args, ".{}"); }
fn genNullType(self: *NativeCodegen, args: []ast.Node) CodegenError!void { try genConst(self, args, "@as(?@TypeOf(undefined), null)"); }
fn genFalse(self: *NativeCodegen, args: []ast.Node) CodegenError!void { try genConst(self, args, "false"); }
fn genUnreachable(self: *NativeCodegen, args: []ast.Node) CodegenError!void { try genConst(self, args, "unreachable"); }
fn genUnit(self: *NativeCodegen, args: []ast.Node) CodegenError!void { try genConst(self, args, "{}"); }
fn genEmptySlice(self: *NativeCodegen, args: []ast.Node) CodegenError!void { try genConst(self, args, "&[_]*anyopaque{}"); }

// Passthrough decorator: returns arg[0] or null
fn genPassthrough(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    if (args.len > 0) try self.genExpr(args[0]) else try self.emit("@as(?*anyopaque, null)");
}

// cast(typ, val) returns val
pub fn genCast(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    if (args.len >= 2) try self.genExpr(args[1]) else if (args.len == 1) try self.genExpr(args[0]) else try self.emit("@as(?*anyopaque, null)");
}
