/// String/List/Dict methods - .split(), .append(), .keys(), etc.
const std = @import("std");
const ast = @import("../../ast.zig");
const CodegenError = @import("main.zig").CodegenError;
const NativeCodegen = @import("main.zig").NativeCodegen;

// TODO: Implement string methods
// - text.split(sep) -> [][]const u8
// - text.upper() -> []const u8
// - text.lower() -> []const u8
// - text.strip() -> []const u8
// - text.replace(old, new) -> []const u8

// TODO: Implement list methods
// - list.append(item)
// - list.pop() -> T
// - list.extend(other)
// - list.insert(index, item)
// - list.remove(item)

// TODO: Implement dict methods
// - dict.get(key) -> ?V
// - dict.keys() -> []K
// - dict.values() -> []V
// - dict.items() -> [][2]{K, V}
