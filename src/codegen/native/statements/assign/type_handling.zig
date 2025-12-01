/// Type analysis and detection for assignment statements
const std = @import("std");
const ast = @import("ast");
const NativeCodegen = @import("../../main.zig").NativeCodegen;

/// Check if a list contains only literal values
pub fn isConstantList(list: ast.Node.List) bool {
    if (list.elts.len == 0) return false;

    for (list.elts) |elem| {
        const is_literal = switch (elem) {
            .constant => true,
            else => false,
        };
        if (!is_literal) return false;
    }

    return true;
}

/// Check if all elements have the same type
pub fn allSameType(elements: []ast.Node) bool {
    if (elements.len == 0) return true;

    const first_const = switch (elements[0]) {
        .constant => |c| c,
        else => return false,
    };

    const first_type_tag = @as(std.meta.Tag(@TypeOf(first_const.value)), first_const.value);

    for (elements[1..]) |elem| {
        const elem_const = switch (elem) {
            .constant => |c| c,
            else => return false,
        };

        const elem_type_tag = @as(std.meta.Tag(@TypeOf(elem_const.value)), elem_const.value);
        if (elem_type_tag != first_type_tag) return false;
    }

    return true;
}

/// Check if assignment value is a constant array (homogeneous literals, not mutated)
pub fn isConstantArray(self: *NativeCodegen, assign: ast.Node.Assign, var_name: []const u8) bool {
    if (assign.value.* != .list) return false;
    const list = assign.value.list;

    // Check if list is constant and homogeneous
    if (!isConstantList(list) or !allSameType(list.elts)) return false;

    // Check mutation analysis - if variable will be mutated, use ArrayList not array
    if (self.mutation_info) |mutations| {
        const mutation_analyzer = @import("../../../../analysis/native_types/mutation_analyzer.zig");
        if (mutation_analyzer.hasListMutation(mutations.*, var_name)) {
            return false; // Will be mutated -> ArrayList, not array
        }
    }

    return true; // Constant, homogeneous, not mutated -> fixed array
}

/// Check if assignment value should be an ArrayList
pub fn isArrayList(self: *NativeCodegen, assign: ast.Node.Assign, var_name: []const u8) bool {
    // Check if RHS is a variable that is already an ArrayList
    // y = x where x is ArrayList -> y should also be ArrayList
    if (assign.value.* == .name) {
        if (self.isArrayListVar(assign.value.name.id)) {
            return true;
        }
    }

    if (assign.value.* != .list) return false;
    const list = assign.value.list;

    // Check if variable has explicit list[T] type annotation
    // Type annotations take priority over value inference
    const var_type = self.type_inferrer.var_types.get(var_name);
    if (var_type) |vt| {
        if (vt == .list) {
            return true; // Explicit list[T] annotation -> ArrayList
        }
    }

    // Non-constant lists always become ArrayList
    if (!isConstantList(list) or !allSameType(list.elts)) return true;

    // Constant lists that will be mutated become ArrayList
    if (self.mutation_info) |mutations| {
        const mutation_analyzer = @import("../../../../analysis/native_types/mutation_analyzer.zig");
        if (mutation_analyzer.hasListMutation(mutations.*, var_name)) {
            return true; // Will be mutated -> ArrayList
        }
    }

    return false; // Constant, homogeneous, not mutated -> fixed array
}

/// Check if value allocates memory (string operations, sorted, etc.)
pub fn isAllocatedString(self: *NativeCodegen, value: ast.Node) bool {
    if (value == .call) {
        // String method calls that allocate new strings
        if (value.call.func.* == .attribute) {
            const attr = value.call.func.attribute;
            const obj_type = self.type_inferrer.inferExpr(attr.value.*) catch return false;

            if (obj_type == .string) {
                const method_name = attr.attr;
                // All string methods that allocate and return new strings
                // NOTE: strip/lstrip/rstrip use std.mem.trim - they DON'T allocate!
                const allocating_methods = [_][]const u8{
                    "upper",   "lower",
                    "replace", "capitalize",
                    "title",   "swapcase",
                    "center",  "ljust",
                    "rjust",   "join",
                };

                for (allocating_methods) |method| {
                    if (std.mem.eql(u8, method_name, method)) {
                        return true;
                    }
                }
            }
        }
        // Built-in functions that allocate: sorted(), reversed()
        if (value.call.func.* == .name) {
            const func_name = value.call.func.name.id;
            if (std.mem.eql(u8, func_name, "sorted") or
                std.mem.eql(u8, func_name, "reversed"))
            {
                return true;
            }
        }
    }
    // String concatenation allocates: s1 + s2
    if (value == .binop and value.binop.op == .Add) {
        const left_type = self.type_inferrer.inferExpr(value.binop.left.*) catch return false;
        const right_type = self.type_inferrer.inferExpr(value.binop.right.*) catch return false;
        if (left_type == .string or right_type == .string) {
            return true;
        }
    }
    return false;
}

/// Check if this is a mutable class instantiation (has methods that mutate self)
pub fn isMutableClassInstance(self: *NativeCodegen, value: ast.Node) bool {
    if (value != .call) return false;
    if (value.call.func.* != .name) return false;
    const func_name = value.call.func.name.id;
    if (func_name.len == 0) return false;
    // Check if it's a class (uppercase) and has mutating methods
    if (!std.ascii.isUpper(func_name[0])) return false;
    return self.mutable_classes.contains(func_name);
}

/// Check if assignment value is an array slice (subscript of constant array)
pub fn isArraySlice(self: *NativeCodegen, value: ast.Node) bool {
    if (value == .subscript and value.subscript.slice == .slice) {
        if (value.subscript.value.* == .name) {
            return self.isArrayVar(value.subscript.value.name.id);
        }
    }
    return false;
}

/// Check if value is an iter() call - iterators need to be mutable for next() to work
pub fn isIteratorCall(value: ast.Node) bool {
    if (value != .call) return false;
    if (value.call.func.* != .name) return false;
    const func_name = value.call.func.name.id;
    return std.mem.eql(u8, func_name, "iter");
}
