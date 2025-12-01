/// Standard closure generation with captured variables
const std = @import("std");
const ast = @import("ast");
const NativeCodegen = @import("../../../main.zig").NativeCodegen;
const CodegenError = @import("../../../main.zig").CodegenError;
const zig_keywords = @import("zig_keywords");
const hashmap_helper = @import("hashmap_helper");
const var_tracking = @import("var_tracking.zig");

/// Generate standard closure with captured variables
pub fn genStandardClosure(
    self: *NativeCodegen,
    func: ast.Node.FunctionDef,
    captured_vars: [][]const u8,
) CodegenError!void {
    // Save counter before any nested generation that might increment it
    const saved_counter = self.lambda_counter;
    self.lambda_counter += 1;

    // Generate comptime closure using runtime.Closure1 helper
    const closure_impl_name = try std.fmt.allocPrint(
        self.allocator,
        "__ClosureImpl_{s}_{d}",
        .{ func.name, saved_counter },
    );
    defer self.allocator.free(closure_impl_name);

    // Generate the capture struct type (must be defined once and reused)
    const capture_type_name = try std.fmt.allocPrint(
        self.allocator,
        "__CaptureType_{s}_{d}",
        .{ func.name, saved_counter },
    );
    defer self.allocator.free(capture_type_name);

    try self.emitIndent();
    try self.output.writer(self.allocator).print("const {s} = struct {{", .{capture_type_name});
    for (captured_vars, 0..) |var_name, i| {
        if (i > 0) try self.emit(", ");
        try self.output.writer(self.allocator).print(" {s}: i64", .{var_name});
    }
    try self.emit(" };\n");

    // Generate the inner function that takes (captures, args...)
    try self.emitIndent();
    try self.output.writer(self.allocator).print("const {s} = struct {{\n", .{closure_impl_name});
    self.indent();

    // Generate static function that closure will call
    // Use unique name based on function name + saved counter to avoid shadowing
    const impl_fn_name = try std.fmt.allocPrint(
        self.allocator,
        "call_{s}_{d}",
        .{ func.name, saved_counter },
    );
    defer self.allocator.free(impl_fn_name);

    // Use unique capture param name to avoid shadowing in nested closures
    const capture_param_name = try std.fmt.allocPrint(
        self.allocator,
        "__cap_{s}_{d}",
        .{ func.name, saved_counter },
    );
    defer self.allocator.free(capture_param_name);

    // Check if captured vars are actually used in the function body
    const captures_used = var_tracking.areCapturedVarsUsed(captured_vars, func.body);

    try self.emitIndent();
    if (captures_used) {
        try self.output.writer(self.allocator).print("fn {s}({s}: {s}", .{ impl_fn_name, capture_param_name, capture_type_name });
    } else {
        // Captures not used, use _ to avoid unused parameter error
        try self.output.writer(self.allocator).print("fn {s}(_: {s}", .{ impl_fn_name, capture_type_name });
    }

    // Generate renamed parameters to avoid shadowing outer scope
    // Build a mapping from original param names to renamed versions
    var param_renames = std.StringHashMap([]const u8).init(self.allocator);
    defer param_renames.deinit();

    for (func.args) |arg| {
        // Check if param is used in body - if not, use _ to discard (Zig 0.15 requirement)
        const is_used = var_tracking.isParamUsedInStmts(arg.name, func.body);
        if (is_used) {
            // Create a unique parameter name to avoid shadowing: __p_name_counter
            const unique_param_name = try std.fmt.allocPrint(
                self.allocator,
                "__p_{s}_{d}",
                .{ arg.name, saved_counter },
            );
            try param_renames.put(arg.name, unique_param_name);
            try self.output.writer(self.allocator).print(", {s}: i64", .{unique_param_name});
        } else {
            try self.output.writer(self.allocator).print(", _: i64", .{});
        }
    }
    try self.emit(") i64 {\n");

    // Generate body with captured vars renamed to capture_param.varname
    self.indent();
    try self.pushScope();

    // Save and populate func_local_uses for this nested function
    // This prevents incorrect "unused variable" detection for local vars
    const saved_func_local_uses = self.func_local_uses;
    self.func_local_uses = hashmap_helper.StringHashMap(void).init(self.allocator);
    defer {
        self.func_local_uses.deinit();
        self.func_local_uses = saved_func_local_uses;
    }

    // Populate func_local_uses with variables used in this function body
    try var_tracking.collectUsedNames(func.body, &self.func_local_uses);

    // Add captured variable renames so they get prefixed with capture struct access
    var capture_renames = std.ArrayList([]const u8){};
    defer capture_renames.deinit(self.allocator);

    for (captured_vars) |var_name| {
        const rename = try std.fmt.allocPrint(
            self.allocator,
            "{s}.{s}",
            .{ capture_param_name, var_name },
        );
        try capture_renames.append(self.allocator, rename);
        try self.var_renames.put(var_name, rename);
    }

    for (func.args) |arg| {
        try self.declareVar(arg.name);
        // Add rename mapping for parameter access in body
        if (param_renames.get(arg.name)) |renamed| {
            try self.var_renames.put(arg.name, renamed);
        }
    }

    for (func.body) |stmt| {
        try self.generateStmt(stmt);
    }

    // Remove param renames after body generation
    for (func.args) |arg| {
        _ = self.var_renames.swapRemove(arg.name);
    }

    // Remove capture renames and free memory
    for (captured_vars, 0..) |var_name, i| {
        _ = self.var_renames.swapRemove(var_name);
        self.allocator.free(capture_renames.items[i]);
    }

    self.popScope();
    self.dedent();

    try self.emitIndent();
    try self.emit("}\n");

    self.dedent();
    try self.emitIndent();
    try self.emit("};\n");

    // Create closure type using comptime helper based on arg count
    // Use unique variable name to avoid shadowing nested functions - use saved_counter
    const closure_var_name = try std.fmt.allocPrint(
        self.allocator,
        "__closure_{s}_{d}",
        .{ func.name, saved_counter },
    );
    defer self.allocator.free(closure_var_name);

    try self.emitIndent();
    if (func.args.len == 0) {
        // No arguments - use Closure0
        try self.output.writer(self.allocator).print(
            "const {s} = runtime.Closure0({s}, ",
            .{ closure_var_name, capture_type_name },
        );
    } else if (func.args.len == 1) {
        try self.output.writer(self.allocator).print(
            "const {s} = runtime.Closure1({s}, ",
            .{ closure_var_name, capture_type_name },
        );
    } else if (func.args.len == 2) {
        try self.output.writer(self.allocator).print(
            "const {s} = runtime.Closure2({s}, ",
            .{ closure_var_name, capture_type_name },
        );
    } else if (func.args.len == 3) {
        try self.output.writer(self.allocator).print(
            "const {s} = runtime.Closure3({s}, ",
            .{ closure_var_name, capture_type_name },
        );
    } else {
        // Fallback to single arg tuple
        try self.output.writer(self.allocator).print(
            "const {s} = runtime.Closure1({s}, ",
            .{ closure_var_name, capture_type_name },
        );
    }

    // Arg types (skip for zero-arg closures)
    for (func.args, 0..) |_, i| {
        if (func.args.len > 1 and i > 0) try self.emit(", ");
        try self.emit("i64");
        if (func.args.len == 1 or i == func.args.len - 1) {
            try self.emit(", ");
        }
    }

    // Return type and function - use saved_counter for consistency
    const impl_fn_ref = try std.fmt.allocPrint(
        self.allocator,
        "call_{s}_{d}",
        .{ func.name, saved_counter },
    );
    defer self.allocator.free(impl_fn_ref);

    try self.output.writer(self.allocator).print(
        "i64, {s}.{s}){{ .captures = .{{",
        .{ closure_impl_name, impl_fn_ref },
    );

    // Initialize captures - use renamed variable names if applicable
    for (captured_vars, 0..) |var_name, i| {
        if (i > 0) try self.emit(", ");
        // Check if this var was renamed (e.g., function parameter renamed to avoid shadowing)
        const actual_name = self.var_renames.get(var_name) orelse var_name;
        try self.output.writer(self.allocator).print(" .{s} = {s}", .{ var_name, actual_name });
    }
    try self.emit(" } };\n");

    // Create alias with original function name - use saved_counter
    const closure_alias_name = try std.fmt.allocPrint(
        self.allocator,
        "__closure_{s}_{d}",
        .{ func.name, saved_counter },
    );
    defer self.allocator.free(closure_alias_name);

    try self.emitIndent();
    try self.emit("const ");
    try zig_keywords.writeEscapedIdent(self.output.writer(self.allocator), func.name);
    try self.output.writer(self.allocator).print(" = {s};\n", .{closure_alias_name});

    // Mark this variable as a closure so calls use .call() syntax
    const func_name_copy = try self.allocator.dupe(u8, func.name);
    try self.closure_vars.put(func_name_copy, {});
}

/// Generate nested function with outer capture context awareness
/// This handles the case where a closure is defined inside another closure
pub fn genNestedFunctionWithOuterCapture(
    self: *NativeCodegen,
    func: ast.Node.FunctionDef,
    outer_captured_vars: [][]const u8,
    outer_capture_param: []const u8,
) CodegenError!void {
    // Use captured variables from AST (pre-computed by closure analyzer)
    const captured_vars = func.captured_vars;

    if (captured_vars.len == 0) {
        // No captures - use ZeroClosure comptime pattern
        const zero_capture = @import("zero_capture.zig");
        try self.emitIndent();
        try zero_capture.genZeroCaptureClosure(self, func);
        return;
    }

    // Save counter before any nested generation that might increment it
    const saved_counter = self.lambda_counter;
    self.lambda_counter += 1;

    // Generate comptime closure using runtime.Closure1 helper
    const closure_impl_name = try std.fmt.allocPrint(
        self.allocator,
        "__ClosureImpl_{s}_{d}",
        .{ func.name, saved_counter },
    );
    defer self.allocator.free(closure_impl_name);

    // Generate the capture struct type (must be defined once and reused)
    const capture_type_name = try std.fmt.allocPrint(
        self.allocator,
        "__CaptureType_{s}_{d}",
        .{ func.name, saved_counter },
    );
    defer self.allocator.free(capture_type_name);

    try self.emitIndent();
    try self.output.writer(self.allocator).print("const {s} = struct {{", .{capture_type_name});
    for (captured_vars, 0..) |var_name, i| {
        if (i > 0) try self.emit(", ");
        try self.output.writer(self.allocator).print(" {s}: i64", .{var_name});
    }
    try self.emit(" };\n");

    // Generate the inner function that takes (captures, args...)
    try self.emitIndent();
    try self.output.writer(self.allocator).print("const {s} = struct {{\n", .{closure_impl_name});
    self.indent();

    // Generate static function that closure will call
    const impl_fn_name = try std.fmt.allocPrint(
        self.allocator,
        "call_{s}_{d}",
        .{ func.name, saved_counter },
    );
    defer self.allocator.free(impl_fn_name);

    // Use unique capture param name to avoid shadowing in nested closures
    const capture_param_name = try std.fmt.allocPrint(
        self.allocator,
        "__cap_{s}_{d}",
        .{ func.name, saved_counter },
    );
    defer self.allocator.free(capture_param_name);

    // Check if captured vars are actually used in the function body
    const captures_used = var_tracking.areCapturedVarsUsed(captured_vars, func.body);

    try self.emitIndent();
    if (captures_used) {
        try self.output.writer(self.allocator).print("fn {s}({s}: {s}", .{ impl_fn_name, capture_param_name, capture_type_name });
    } else {
        // Captures not used, use _ to avoid unused parameter error
        try self.output.writer(self.allocator).print("fn {s}(_: {s}", .{ impl_fn_name, capture_type_name });
    }

    // Generate renamed parameters to avoid shadowing outer scope (duplicate of above section)
    var param_renames = std.StringHashMap([]const u8).init(self.allocator);
    defer param_renames.deinit();

    for (func.args) |arg| {
        // Check if param is used in body - if not, use _ to discard (Zig 0.15 requirement)
        const is_used = var_tracking.isParamUsedInStmts(arg.name, func.body);
        if (is_used) {
            // Create a unique parameter name to avoid shadowing: __p_name_counter
            const unique_param_name = try std.fmt.allocPrint(
                self.allocator,
                "__p_{s}_{d}",
                .{ arg.name, saved_counter },
            );
            try param_renames.put(arg.name, unique_param_name);
            try self.output.writer(self.allocator).print(", {s}: i64", .{unique_param_name});
        } else {
            try self.output.writer(self.allocator).print(", _: i64", .{});
        }
    }
    try self.emit(") i64 {\n");

    // Generate body with captured vars renamed to capture_param.varname
    self.indent();
    try self.pushScope();

    // Save and populate func_local_uses for this nested function
    const saved_func_local_uses = self.func_local_uses;
    self.func_local_uses = hashmap_helper.StringHashMap(void).init(self.allocator);
    defer {
        self.func_local_uses.deinit();
        self.func_local_uses = saved_func_local_uses;
    }

    // Populate func_local_uses with variables used in this function body
    try var_tracking.collectUsedNames(func.body, &self.func_local_uses);

    // Add captured variable renames so they get prefixed with capture struct access
    var capture_renames = std.ArrayList([]const u8){};
    defer capture_renames.deinit(self.allocator);

    for (captured_vars) |var_name| {
        const rename = try std.fmt.allocPrint(
            self.allocator,
            "{s}.{s}",
            .{ capture_param_name, var_name },
        );
        try capture_renames.append(self.allocator, rename);
        try self.var_renames.put(var_name, rename);
    }

    for (func.args) |arg| {
        try self.declareVar(arg.name);
        // Add rename mapping for parameter access in body
        if (param_renames.get(arg.name)) |renamed| {
            try self.var_renames.put(arg.name, renamed);
        }
    }

    for (func.body) |stmt| {
        try self.generateStmt(stmt);
    }

    // Remove param renames after body generation
    for (func.args) |arg| {
        _ = self.var_renames.swapRemove(arg.name);
    }

    // Remove capture renames and free memory
    for (captured_vars, 0..) |var_name, i| {
        _ = self.var_renames.swapRemove(var_name);
        self.allocator.free(capture_renames.items[i]);
    }

    self.popScope();
    self.dedent();

    try self.emitIndent();
    try self.emit("}\n");

    self.dedent();
    try self.emitIndent();
    try self.emit("};\n");

    // Create closure type using comptime helper based on arg count
    const closure_var_name = try std.fmt.allocPrint(
        self.allocator,
        "__closure_{s}_{d}",
        .{ func.name, saved_counter },
    );
    defer self.allocator.free(closure_var_name);

    try self.emitIndent();
    if (func.args.len == 0) {
        try self.output.writer(self.allocator).print(
            "const {s} = runtime.Closure0({s}, ",
            .{ closure_var_name, capture_type_name },
        );
    } else if (func.args.len == 1) {
        try self.output.writer(self.allocator).print(
            "const {s} = runtime.Closure1({s}, ",
            .{ closure_var_name, capture_type_name },
        );
    } else if (func.args.len == 2) {
        try self.output.writer(self.allocator).print(
            "const {s} = runtime.Closure2({s}, ",
            .{ closure_var_name, capture_type_name },
        );
    } else if (func.args.len == 3) {
        try self.output.writer(self.allocator).print(
            "const {s} = runtime.Closure3({s}, ",
            .{ closure_var_name, capture_type_name },
        );
    } else {
        try self.output.writer(self.allocator).print(
            "const {s} = runtime.Closure1({s}, ",
            .{ closure_var_name, capture_type_name },
        );
    }

    // Arg types (skip for zero-arg closures)
    for (func.args, 0..) |_, i| {
        if (func.args.len > 1 and i > 0) try self.emit(", ");
        try self.emit("i64");
        if (func.args.len == 1 or i == func.args.len - 1) {
            try self.emit(", ");
        }
    }

    // Return type and function
    const impl_fn_ref = try std.fmt.allocPrint(
        self.allocator,
        "call_{s}_{d}",
        .{ func.name, saved_counter },
    );
    defer self.allocator.free(impl_fn_ref);

    try self.output.writer(self.allocator).print(
        "i64, {s}.{s}){{ .captures = .{{",
        .{ closure_impl_name, impl_fn_ref },
    );

    // Initialize captures - reference outer captured vars through outer capture struct
    // or use renamed variable names if applicable
    for (captured_vars, 0..) |var_name, i| {
        if (i > 0) try self.emit(", ");
        // Check if this var is from outer closure's captures
        var is_outer_capture = false;
        for (outer_captured_vars) |outer_var| {
            if (std.mem.eql(u8, var_name, outer_var)) {
                is_outer_capture = true;
                break;
            }
        }
        if (is_outer_capture) {
            try self.output.writer(self.allocator).print(" .{s} = {s}.{s}", .{ var_name, outer_capture_param, var_name });
        } else {
            // Check if this var was renamed (e.g., function parameter renamed to avoid shadowing)
            const actual_name = self.var_renames.get(var_name) orelse var_name;
            try self.output.writer(self.allocator).print(" .{s} = {s}", .{ var_name, actual_name });
        }
    }
    try self.emit(" } };\n");

    // Create alias with original function name
    const closure_alias_name = try std.fmt.allocPrint(
        self.allocator,
        "__closure_{s}_{d}",
        .{ func.name, saved_counter },
    );
    defer self.allocator.free(closure_alias_name);

    try self.emitIndent();
    try self.emit("const ");
    try zig_keywords.writeEscapedIdent(self.output.writer(self.allocator), func.name);
    try self.output.writer(self.allocator).print(" = {s};\n", .{closure_alias_name});

    // Mark this variable as a closure so calls use .call() syntax
    const func_name_copy = try self.allocator.dupe(u8, func.name);
    try self.closure_vars.put(func_name_copy, {});
}
