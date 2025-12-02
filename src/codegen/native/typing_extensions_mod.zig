/// Python typing_extensions module - Backports of typing features
const std = @import("std");
const ast = @import("ast");
const h = @import("mod_helper.zig");
const CodegenError = h.CodegenError;
const NativeCodegen = h.NativeCodegen;

pub const Funcs = std.StaticStringMap(h.H).initComptime(.{
    .{ "Annotated", h.c("@TypeOf(undefined)") }, .{ "ParamSpec", h.c("@TypeOf(undefined)") },
    .{ "ParamSpecArgs", h.c("@TypeOf(undefined)") }, .{ "ParamSpecKwargs", h.c("@TypeOf(undefined)") },
    .{ "Concatenate", h.c("@TypeOf(undefined)") }, .{ "TypeAlias", h.c("@TypeOf(undefined)") },
    .{ "TypeGuard", h.c("@TypeOf(undefined)") }, .{ "TypeIs", h.c("@TypeOf(undefined)") },
    .{ "Self", h.c("@TypeOf(undefined)") }, .{ "Never", h.c("noreturn") },
    .{ "Required", h.c("@TypeOf(undefined)") }, .{ "NotRequired", h.c("@TypeOf(undefined)") },
    .{ "LiteralString", h.c("[]const u8") }, .{ "Unpack", h.c("@TypeOf(undefined)") },
    .{ "TypeVarTuple", h.c("@TypeOf(undefined)") },
    .{ "override", genPassthrough }, .{ "final", genPassthrough }, .{ "deprecated", genPassthrough },
    .{ "dataclass_transform", genPassthrough }, .{ "runtime_checkable", genPassthrough },
    .{ "Protocol", h.c("@TypeOf(undefined)") }, .{ "TypedDict", h.c(".{}") }, .{ "NamedTuple", h.c(".{}") },
    .{ "get_type_hints", h.c(".{}") }, .{ "get_origin", h.c("@as(?@TypeOf(undefined), null)") },
    .{ "get_args", h.c(".{}") }, .{ "is_typeddict", h.c("false") }, .{ "get_annotations", h.c(".{}") },
    .{ "assert_type", genPassthrough }, .{ "reveal_type", genPassthrough },
    .{ "assert_never", h.c("unreachable") }, .{ "clear_overloads", h.c("{}") },
    .{ "get_overloads", h.c("&[_]*anyopaque{}") },
    .{ "Doc", h.c("@TypeOf(undefined)") }, .{ "ReadOnly", h.c("@TypeOf(undefined)") },
    .{ "Any", h.c("@TypeOf(undefined)") }, .{ "Union", h.c("@TypeOf(undefined)") },
    .{ "Optional", h.c("@TypeOf(undefined)") }, .{ "List", h.c("@TypeOf(undefined)") },
    .{ "Dict", h.c("@TypeOf(undefined)") }, .{ "Set", h.c("@TypeOf(undefined)") },
    .{ "Tuple", h.c("@TypeOf(undefined)") }, .{ "Callable", h.c("@TypeOf(undefined)") },
    .{ "Type", h.c("@TypeOf(undefined)") }, .{ "Literal", h.c("@TypeOf(undefined)") },
    .{ "ClassVar", h.c("@TypeOf(undefined)") }, .{ "TypeVar", h.c("@TypeOf(undefined)") },
    .{ "Generic", h.c("@TypeOf(undefined)") }, .{ "NoReturn", h.c("noreturn") },
    .{ "cast", genCast }, .{ "overload", genPassthrough }, .{ "no_type_check", genPassthrough },
    .{ "TYPE_CHECKING", h.c("false") },
});

fn genPassthrough(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    if (args.len > 0) try self.genExpr(args[0]) else try self.emit("@as(?*anyopaque, null)");
}

pub fn genCast(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    if (args.len >= 2) try self.genExpr(args[1]) else if (args.len == 1) try self.genExpr(args[0]) else try self.emit("@as(?*anyopaque, null)");
}
