/// Return variable analysis for function/method bodies
/// Identifies variables that are returned from functions to prevent
/// emitting defer deinit for them (caller takes ownership)
const std = @import("std");
const ast = @import("analysis.ast");
const NativeCodegen = @import("../../../../main.zig").NativeCodegen;
const CodegenError = @import("../../../../main.zig").CodegenError;
const hashmap_helper = @import("utils.hashmap_helper");

/// Analyze function body and collect all variables that are returned
/// These variables should NOT have defer deinit emitted because
/// ownership transfers to the caller
pub fn analyzeReturnedVars(self: *NativeCodegen, func: ast.Node.FunctionDef) !void {
    self.returned_vars.clearRetainingCapacity();
    for (func.body) |stmt| {
        try collectReturnedVars(self, stmt);
    }
}

/// Analyze module-level code (for script mode main function)
pub fn analyzeModuleLevelReturnedVars(self: *NativeCodegen, module_body: []const ast.Node) !void {
    self.returned_vars.clearRetainingCapacity();
    for (module_body) |stmt| {
        // Skip function_def, class_def, import_stmt, import_from (not executed in main)
        if (stmt != .function_def and stmt != .class_def and stmt != .import_stmt and stmt != .import_from) {
            try collectReturnedVars(self, stmt);
        }
    }
}

/// Recursively collect returned variable names from statements
fn collectReturnedVars(self: *NativeCodegen, stmt: ast.Node) CodegenError!void {
    switch (stmt) {
        .return_stmt => |ret| {
            if (ret.value) |val| {
                // Direct variable return: return log
                if (val.* == .name) {
                    try self.returned_vars.put(val.name.id, {});
                }
                // Could extend to handle: return x, y (tuple) or return [x] (list)
                // but for now the main case is direct variable return
            }
        },
        .if_stmt => |if_stmt| {
            for (if_stmt.body) |body_stmt| {
                try collectReturnedVars(self, body_stmt);
            }
            for (if_stmt.else_body) |else_stmt| {
                try collectReturnedVars(self, else_stmt);
            }
        },
        .while_stmt => |while_stmt| {
            for (while_stmt.body) |body_stmt| {
                try collectReturnedVars(self, body_stmt);
            }
            if (while_stmt.orelse_body) |ob| {
                for (ob) |body_stmt| {
                    try collectReturnedVars(self, body_stmt);
                }
            }
        },
        .for_stmt => |for_stmt| {
            for (for_stmt.body) |body_stmt| {
                try collectReturnedVars(self, body_stmt);
            }
            if (for_stmt.orelse_body) |ob| {
                for (ob) |body_stmt| {
                    try collectReturnedVars(self, body_stmt);
                }
            }
        },
        .try_stmt => |try_stmt| {
            for (try_stmt.body) |body_stmt| {
                try collectReturnedVars(self, body_stmt);
            }
            for (try_stmt.handlers) |handler| {
                for (handler.body) |body_stmt| {
                    try collectReturnedVars(self, body_stmt);
                }
            }
            for (try_stmt.else_body) |body_stmt| {
                try collectReturnedVars(self, body_stmt);
            }
            for (try_stmt.finalbody) |body_stmt| {
                try collectReturnedVars(self, body_stmt);
            }
        },
        .with_stmt => |with_stmt| {
            for (with_stmt.body) |body_stmt| {
                try collectReturnedVars(self, body_stmt);
            }
        },
        .match_stmt => |match_stmt| {
            for (match_stmt.cases) |case| {
                for (case.body) |body_stmt| {
                    try collectReturnedVars(self, body_stmt);
                }
            }
        },
        else => {},
    }
}
