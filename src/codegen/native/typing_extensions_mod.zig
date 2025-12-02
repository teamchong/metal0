/// Python typing_extensions module - Backports of typing features
const std = @import("std");
const ast = @import("ast");
const CodegenError = @import("main.zig").CodegenError;
const NativeCodegen = @import("main.zig").NativeCodegen;

const ModuleHandler = *const fn (*NativeCodegen, []ast.Node) CodegenError!void;
fn genConst(comptime v: []const u8) ModuleHandler {
    return struct { fn f(self: *NativeCodegen, args: []ast.Node) CodegenError!void { _ = args; try self.emit(v); } }.f;
}

pub const Funcs = std.StaticStringMap(ModuleHandler).initComptime(.{
    .{ "Annotated", genConst("@TypeOf(undefined)") }, .{ "ParamSpec", genConst("@TypeOf(undefined)") },
    .{ "ParamSpecArgs", genConst("@TypeOf(undefined)") }, .{ "ParamSpecKwargs", genConst("@TypeOf(undefined)") },
    .{ "Concatenate", genConst("@TypeOf(undefined)") }, .{ "TypeAlias", genConst("@TypeOf(undefined)") },
    .{ "TypeGuard", genConst("@TypeOf(undefined)") }, .{ "TypeIs", genConst("@TypeOf(undefined)") },
    .{ "Self", genConst("@TypeOf(undefined)") }, .{ "Never", genConst("noreturn") },
    .{ "Required", genConst("@TypeOf(undefined)") }, .{ "NotRequired", genConst("@TypeOf(undefined)") },
    .{ "LiteralString", genConst("[]const u8") }, .{ "Unpack", genConst("@TypeOf(undefined)") },
    .{ "TypeVarTuple", genConst("@TypeOf(undefined)") },
    .{ "override", genPassthrough }, .{ "final", genPassthrough }, .{ "deprecated", genPassthrough },
    .{ "dataclass_transform", genPassthrough }, .{ "runtime_checkable", genPassthrough },
    .{ "Protocol", genConst("@TypeOf(undefined)") }, .{ "TypedDict", genConst(".{}") }, .{ "NamedTuple", genConst(".{}") },
    .{ "get_type_hints", genConst(".{}") }, .{ "get_origin", genConst("@as(?@TypeOf(undefined), null)") },
    .{ "get_args", genConst(".{}") }, .{ "is_typeddict", genConst("false") }, .{ "get_annotations", genConst(".{}") },
    .{ "assert_type", genPassthrough }, .{ "reveal_type", genPassthrough },
    .{ "assert_never", genConst("unreachable") }, .{ "clear_overloads", genConst("{}") },
    .{ "get_overloads", genConst("&[_]*anyopaque{}") },
    .{ "Doc", genConst("@TypeOf(undefined)") }, .{ "ReadOnly", genConst("@TypeOf(undefined)") },
    .{ "Any", genConst("@TypeOf(undefined)") }, .{ "Union", genConst("@TypeOf(undefined)") },
    .{ "Optional", genConst("@TypeOf(undefined)") }, .{ "List", genConst("@TypeOf(undefined)") },
    .{ "Dict", genConst("@TypeOf(undefined)") }, .{ "Set", genConst("@TypeOf(undefined)") },
    .{ "Tuple", genConst("@TypeOf(undefined)") }, .{ "Callable", genConst("@TypeOf(undefined)") },
    .{ "Type", genConst("@TypeOf(undefined)") }, .{ "Literal", genConst("@TypeOf(undefined)") },
    .{ "ClassVar", genConst("@TypeOf(undefined)") }, .{ "TypeVar", genConst("@TypeOf(undefined)") },
    .{ "Generic", genConst("@TypeOf(undefined)") }, .{ "NoReturn", genConst("noreturn") },
    .{ "cast", genCast }, .{ "overload", genPassthrough }, .{ "no_type_check", genPassthrough },
    .{ "TYPE_CHECKING", genConst("false") },
});

fn genPassthrough(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    if (args.len > 0) try self.genExpr(args[0]) else try self.emit("@as(?*anyopaque, null)");
}

pub fn genCast(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    if (args.len >= 2) try self.genExpr(args[1]) else if (args.len == 1) try self.genExpr(args[0]) else try self.emit("@as(?*anyopaque, null)");
}
