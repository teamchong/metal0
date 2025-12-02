/// Shared StaticStringMaps for operator dispatch
/// Consolidates duplicate definitions across codegen modules for DCE efficiency
const std = @import("std");

/// Binary operator to Zig operator string mapping
pub const BinOpStrings = std.StaticStringMap([]const u8).initComptime(.{
    .{ "Add", " + " },  .{ "Sub", " - " },   .{ "Mult", " * " },
    .{ "Div", " / " },  .{ "FloorDiv", " / " }, .{ "Mod", " % " },
    .{ "Pow", " ** " }, .{ "BitAnd", " & " }, .{ "BitOr", " | " },
    .{ "BitXor", " ^ " }, .{ "LShift", " << " }, .{ "RShift", " >> " },
    .{ "MatMul", " @ " },
});

/// Comparison operator to Zig operator string mapping
pub const CompOpStrings = std.StaticStringMap([]const u8).initComptime(.{
    .{ "Eq", " == " },   .{ "NotEq", " != " },
    .{ "Lt", " < " },    .{ "LtEq", " <= " },
    .{ "Gt", " > " },    .{ "GtEq", " >= " },
    .{ "Is", " == " },   .{ "IsNot", " != " },
});
