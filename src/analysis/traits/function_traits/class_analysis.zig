/// Class traits analysis - inheritance patterns, dunder method overrides
/// Used for determining how to handle class instances in codegen
const std = @import("std");
const ast = @import("analysis.ast");
const hashmap_helper = @import("utils.hashmap_helper");
const types = @import("types.zig");
const shared_maps = @import("codegen.shared_maps");

pub const ClassTraits = types.ClassTraits;

/// Analyze a class definition and extract its traits
pub fn analyzeClassTraits(class_def: ast.Node.ClassDef, parent_scope: ?[]const u8) ClassTraits {
    var traits_val = ClassTraits{
        .name = class_def.name,
        .is_nested = parent_scope != null,
        .parent_scope = parent_scope,
    };

    // Check base classes for builtin types
    for (class_def.bases) |base| {
        if (base == .name) {
            const base_name = base.name.id;
            if (shared_maps.isBuiltinBase(base_name)) {
                traits_val.builtin_base = base_name;
                break;
            }
        }
    }

    // Scan class body for dunder method overrides
    for (class_def.body) |stmt| {
        if (stmt == .function_def) {
            const func = stmt.function_def;
            const method_name = func.name;

            if (shared_maps.getDunderTraitKind(method_name)) |kind| {
                switch (kind) {
                    .float => traits_val.overridden_dunders.float = true,
                    .int => traits_val.overridden_dunders.int = true,
                    .str => traits_val.overridden_dunders.str = true,
                    .repr => traits_val.overridden_dunders.repr = true,
                    .bool_ => traits_val.overridden_dunders.bool_ = true,
                    .index => traits_val.overridden_dunders.index = true,
                    .hash => traits_val.overridden_dunders.hash = true,
                    .len => traits_val.overridden_dunders.len = true,
                    .iter => traits_val.overridden_dunders.iter = true,
                    .next => traits_val.overridden_dunders.next = true,
                    .call => traits_val.overridden_dunders.call = true,
                    .new => traits_val.overridden_dunders.new = true,
                    .init => traits_val.overridden_dunders.init = true,
                }
            }
        }
    }

    return traits_val;
}

/// Analyze all classes in a module/function body and return their traits
pub fn analyzeAllClassTraits(
    allocator: std.mem.Allocator,
    body: []const ast.Node,
    parent_scope: ?[]const u8,
) !hashmap_helper.StringHashMap(ClassTraits) {
    var result = hashmap_helper.StringHashMap(ClassTraits).init(allocator);

    for (body) |stmt| {
        switch (stmt) {
            .class_def => |class_def| {
                const traits_val = analyzeClassTraits(class_def, parent_scope);
                try result.put(allocator, class_def.name, traits_val);

                // Recursively analyze nested classes in class body
                const nested = try analyzeAllClassTraits(allocator, class_def.body, class_def.name);
                var nested_iter = nested.iterator();
                while (nested_iter.next()) |entry| {
                    const qualified_name = try std.fmt.allocPrint(allocator, "{s}.{s}", .{ class_def.name, entry.key_ptr.* });
                    try result.put(allocator, qualified_name, entry.value_ptr.*);
                }
            },
            .function_def => |func_def| {
                const nested = try analyzeAllClassTraits(allocator, func_def.body, func_def.name);
                var nested_iter = nested.iterator();
                while (nested_iter.next()) |entry| {
                    var nested_traits = entry.value_ptr.*;
                    nested_traits.is_nested = true;
                    nested_traits.parent_scope = func_def.name;
                    try result.put(allocator, entry.key_ptr.*, nested_traits);
                }
            },
            .if_stmt => |if_stmt| {
                const if_nested = try analyzeAllClassTraits(allocator, if_stmt.body, parent_scope);
                var if_iter = if_nested.iterator();
                while (if_iter.next()) |entry| {
                    try result.put(allocator, entry.key_ptr.*, entry.value_ptr.*);
                }
                const else_nested = try analyzeAllClassTraits(allocator, if_stmt.else_body, parent_scope);
                var else_iter = else_nested.iterator();
                while (else_iter.next()) |entry| {
                    try result.put(allocator, entry.key_ptr.*, entry.value_ptr.*);
                }
            },
            .for_stmt => |for_stmt| {
                const for_nested = try analyzeAllClassTraits(allocator, for_stmt.body, parent_scope);
                var for_iter = for_nested.iterator();
                while (for_iter.next()) |entry| {
                    try result.put(allocator, entry.key_ptr.*, entry.value_ptr.*);
                }
                if (for_stmt.orelse_body) |orelse_body| {
                    const orelse_nested = try analyzeAllClassTraits(allocator, orelse_body, parent_scope);
                    var orelse_iter = orelse_nested.iterator();
                    while (orelse_iter.next()) |entry| {
                        try result.put(allocator, entry.key_ptr.*, entry.value_ptr.*);
                    }
                }
            },
            .while_stmt => |while_stmt| {
                const while_nested = try analyzeAllClassTraits(allocator, while_stmt.body, parent_scope);
                var while_iter = while_nested.iterator();
                while (while_iter.next()) |entry| {
                    try result.put(allocator, entry.key_ptr.*, entry.value_ptr.*);
                }
                if (while_stmt.orelse_body) |orelse_body| {
                    const orelse_nested = try analyzeAllClassTraits(allocator, orelse_body, parent_scope);
                    var orelse_iter = orelse_nested.iterator();
                    while (orelse_iter.next()) |entry| {
                        try result.put(allocator, entry.key_ptr.*, entry.value_ptr.*);
                    }
                }
            },
            .try_stmt => |try_stmt| {
                const try_nested = try analyzeAllClassTraits(allocator, try_stmt.body, parent_scope);
                var try_iter = try_nested.iterator();
                while (try_iter.next()) |entry| {
                    try result.put(allocator, entry.key_ptr.*, entry.value_ptr.*);
                }
                for (try_stmt.handlers) |handler| {
                    const handler_nested = try analyzeAllClassTraits(allocator, handler.body, parent_scope);
                    var handler_iter = handler_nested.iterator();
                    while (handler_iter.next()) |entry| {
                        try result.put(allocator, entry.key_ptr.*, entry.value_ptr.*);
                    }
                }
                const else_nested = try analyzeAllClassTraits(allocator, try_stmt.else_body, parent_scope);
                var else_iter = else_nested.iterator();
                while (else_iter.next()) |entry| {
                    try result.put(allocator, entry.key_ptr.*, entry.value_ptr.*);
                }
                const finally_nested = try analyzeAllClassTraits(allocator, try_stmt.finalbody, parent_scope);
                var finally_iter = finally_nested.iterator();
                while (finally_iter.next()) |entry| {
                    try result.put(allocator, entry.key_ptr.*, entry.value_ptr.*);
                }
            },
            .with_stmt => |with_stmt| {
                const with_nested = try analyzeAllClassTraits(allocator, with_stmt.body, parent_scope);
                var with_iter = with_nested.iterator();
                while (with_iter.next()) |entry| {
                    try result.put(allocator, entry.key_ptr.*, entry.value_ptr.*);
                }
            },
            .match_stmt => |match_stmt| {
                for (match_stmt.cases) |case| {
                    const case_nested = try analyzeAllClassTraits(allocator, case.body, parent_scope);
                    var case_iter = case_nested.iterator();
                    while (case_iter.next()) |entry| {
                        try result.put(allocator, entry.key_ptr.*, entry.value_ptr.*);
                    }
                }
            },
            else => {},
        }
    }

    return result;
}

/// Bound method reference analysis
pub const BoundMethodRef = struct {
    field_name: []const u8,
    method_name: []const u8,
};

pub const BoundMethodRefs = struct {
    refs: [16]BoundMethodRef = undefined,
    count: usize = 0,

    pub fn add(self: *BoundMethodRefs, ref: BoundMethodRef) void {
        if (self.count < 16) {
            self.refs[self.count] = ref;
            self.count += 1;
        }
    }

    pub fn contains(self: *const BoundMethodRefs, field_name: []const u8) bool {
        for (self.refs[0..self.count]) |ref| {
            if (std.mem.eql(u8, ref.field_name, field_name)) return true;
        }
        return false;
    }

    pub fn getMethod(self: *const BoundMethodRefs, field_name: []const u8) ?[]const u8 {
        for (self.refs[0..self.count]) |ref| {
            if (std.mem.eql(u8, ref.field_name, field_name)) return ref.method_name;
        }
        return null;
    }
};

/// Check if a function body contains bound method references
pub fn findBoundMethodRefs(body: []const ast.Node, class_methods: []const []const u8) BoundMethodRefs {
    var result = BoundMethodRefs{};
    for (body) |stmt| {
        collectBoundMethodRefs(stmt, class_methods, &result);
    }
    return result;
}

fn collectBoundMethodRefs(stmt: ast.Node, class_methods: []const []const u8, result: *BoundMethodRefs) void {
    switch (stmt) {
        .assign => |assign| {
            if (assign.targets.len > 0 and assign.targets[0] == .attribute) {
                const target_attr = assign.targets[0].attribute;
                if (target_attr.value.* == .name and std.mem.eql(u8, target_attr.value.name.id, "self")) {
                    if (assign.value.* == .attribute) {
                        const value_attr = assign.value.attribute;
                        if (value_attr.value.* == .name and std.mem.eql(u8, value_attr.value.name.id, "self")) {
                            for (class_methods) |method| {
                                if (std.mem.eql(u8, value_attr.attr, method)) {
                                    result.add(.{
                                        .field_name = target_attr.attr,
                                        .method_name = value_attr.attr,
                                    });
                                    break;
                                }
                            }
                        }
                    }
                }
            }
        },
        .if_stmt => |if_stmt| {
            for (if_stmt.body) |s| collectBoundMethodRefs(s, class_methods, result);
            for (if_stmt.else_body) |s| collectBoundMethodRefs(s, class_methods, result);
        },
        .for_stmt => |for_stmt| {
            for (for_stmt.body) |s| collectBoundMethodRefs(s, class_methods, result);
            if (for_stmt.orelse_body) |orelse_body| {
                for (orelse_body) |s| collectBoundMethodRefs(s, class_methods, result);
            }
        },
        .while_stmt => |while_stmt| {
            for (while_stmt.body) |s| collectBoundMethodRefs(s, class_methods, result);
            if (while_stmt.orelse_body) |orelse_body| {
                for (orelse_body) |s| collectBoundMethodRefs(s, class_methods, result);
            }
        },
        .try_stmt => |try_stmt| {
            for (try_stmt.body) |s| collectBoundMethodRefs(s, class_methods, result);
            for (try_stmt.handlers) |handler| {
                for (handler.body) |s| collectBoundMethodRefs(s, class_methods, result);
            }
            for (try_stmt.else_body) |s| collectBoundMethodRefs(s, class_methods, result);
            for (try_stmt.finalbody) |s| collectBoundMethodRefs(s, class_methods, result);
        },
        .with_stmt => |with_stmt| {
            for (with_stmt.body) |s| collectBoundMethodRefs(s, class_methods, result);
        },
        .match_stmt => |match_stmt| {
            for (match_stmt.cases) |case| {
                for (case.body) |s| collectBoundMethodRefs(s, class_methods, result);
            }
        },
        else => {},
    }
}

/// Get all method names from a class definition
pub fn getClassMethods(class_def: ast.Node.ClassDef) [64][]const u8 {
    var methods: [64][]const u8 = undefined;
    var count: usize = 0;

    for (class_def.body) |stmt| {
        if (stmt == .function_def) {
            if (count < 64) {
                methods[count] = stmt.function_def.name;
                count += 1;
            }
        }
    }

    if (count < 64) {
        methods[count] = "";
    }

    return methods;
}
